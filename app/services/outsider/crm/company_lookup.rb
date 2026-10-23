# OUTSIDER: dados da empresa do cliente pelo CNPJ, para a proposta (Entrega 19).
#
# A consulta direta na SEFAZ (CadConsultaCadastro4) exige o certificado digital e-CNPJ em cada chamada, e o
# SINTEGRA de cada estado tem captcha. Por isso a busca usa serviços públicos que leem esses cadastros, nesta
# ordem, e para assim que já tem razão social, inscrição estadual e e-mail:
# 1. CNPJá (aberta): Receita Federal + Cadastro Centralizado de Contribuintes (CCC) das SEFAZ, com a IE;
# 2. CNPJ.ws (pública): Receita Federal + SINTEGRA, com a IE; só completa o que a primeira não trouxe;
# 3. BrasilAPI: só Receita Federal (sem IE), quando nenhuma das duas respondeu.
# Cada serviço aceita poucas consultas por minuto por servidor (5 e 3 nas duas primeiras), então o
# resultado fica um dia em cache.
#
# Só os campos da proposta saem daqui. A resposta de cada serviço é lida até MAX_BYTES e descartada, e a
# busca inteira para em DEADLINE, abaixo dos 15 s do rack-timeout. Aceita o CNPJ alfanumérico (letras nas
# 12 primeiras posições, em uso desde julho de 2026).
class Outsider::Crm::CompanyLookup
  class Invalid < StandardError; end
  class NotFound < StandardError; end
  class Unavailable < StandardError; end
  class TooLarge < StandardError; end

  FIELDS = %w[company document state_registration address district city state zip phone email].freeze
  COMPLETE = %w[company state_registration email].freeze
  URLS = {
    cnpja: 'https://open.cnpja.com/office/%s',
    cnpjws: 'https://publica.cnpj.ws/cnpj/%s',
    brasilapi: 'https://brasilapi.com.br/api/cnpj/v1/%s'
  }.freeze
  # onde cada campo está na resposta de cada serviço (Hash#dig)
  PATHS = {
    cnpja: { company: %w[company name], street: %w[address street], number: %w[address number], details: %w[address details],
             district: %w[address district], city: %w[address city], state: %w[address state], zip: %w[address zip],
             area: ['phones', 0, 'area'], phone: ['phones', 0, 'number'], email: ['emails', 0, 'address'] },
    cnpjws: { company: %w[razao_social], street_type: %w[estabelecimento tipo_logradouro], street: %w[estabelecimento logradouro],
              number: %w[estabelecimento numero], details: %w[estabelecimento complemento], district: %w[estabelecimento bairro],
              city: %w[estabelecimento cidade nome], state: %w[estabelecimento estado sigla], zip: %w[estabelecimento cep],
              area: %w[estabelecimento ddd1], phone: %w[estabelecimento telefone1], email: %w[estabelecimento email] },
    brasilapi: { company: %w[razao_social], street_type: %w[descricao_tipo_logradouro], street: %w[logradouro], number: %w[numero],
                 details: %w[complemento], district: %w[bairro], city: %w[municipio], state: %w[uf], zip: %w[cep],
                 phone: %w[ddd_telefone_1], email: %w[email] }
  }.freeze
  # inscrições estaduais: a lista e, em cada uma, número, estado e se está ativa (a BrasilAPI não tem)
  REGISTRATIONS = {
    cnpja: { list: %w[registrations], number: %w[number], state: %w[state], enabled: %w[enabled] },
    cnpjws: { list: %w[estabelecimento inscricoes_estaduais], number: %w[inscricao_estadual], state: %w[estado sigla], enabled: %w[ativo] }
  }.freeze
  HEADERS = { 'Accept' => 'application/json', 'User-Agent' => 'Chatwoot CRM (consulta de CNPJ)' }.freeze
  OPEN_TIMEOUT = 2
  READ_TIMEOUT = 3
  DEADLINE = 7
  MAX_BYTES = 256.kilobytes
  CACHE_TTL = 1.day

  def self.normalize(document)
    value = document.to_s.upcase.gsub(/[^0-9A-Z]/, '')
    return unless value.match?(/\A[0-9A-Z]{12}\d{2}\z/) && !value.match?(/\A(.)\1+\z/)

    value if check_digits(value[0, 12]) == value[12, 2]
  end

  # Dígitos verificadores (módulo 11, pesos de 2 a 9 da direita para a esquerda). No CNPJ alfanumérico
  # cada caractere vale o código ASCII menos 48, então os números continuam valendo o próprio número.
  def self.check_digits(base)
    2.times.reduce(base) do |digits, _|
      sum = digits.chars.reverse.each_with_index.sum { |char, index| (char.ord - 48) * ((index % 8) + 2) }
      digits + (sum % 11 < 2 ? 0 : 11 - (sum % 11)).to_s
    end.last(2)
  end

  def initialize(document)
    @document = self.class.normalize(document)
    raise Invalid unless @document
  end

  # { customer: { company:, document:, ... }, sources: ['cnpja', ...] }
  def perform
    Rails.cache.fetch("outsider_crm_company_lookup/#{@document}", expires_in: CACHE_TTL) { lookup }
  end

  private

  def lookup
    @started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    found = {}
    sources = []
    URLS.each_key do |provider|
      next if skip?(provider, found)

      data = fetch(provider)
      next if data.blank?

      # o primeiro serviço que trouxe o campo vale; os outros só completam
      found = data.compact_blank.merge(found)
      sources << provider.to_s
    end
    raise(@not_found ? NotFound : Unavailable) if found.blank?

    { customer: FIELDS.index_with { |key| found[key].to_s }.merge('document' => formatted_document), sources: sources }
  end

  # já tem o que importa ou passou do tempo; a BrasilAPI (sem IE) só entra quando nenhum outro respondeu
  def skip?(provider, found)
    (COMPLETE - found.keys).empty? || Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started > DEADLINE ||
      (provider == :brasilapi && found.present?)
  end

  # Campos da proposta tirados da resposta do serviço; nil quando ele não trouxe a empresa
  def fetch(provider)
    body = download(format(URLS[provider], @document))
    @not_found ||= body == :not_found
    return unless body.is_a?(String)

    fields = customer_fields(provider, JSON.parse(body))
    fields if fields['company'].present?
  rescue JSON::ParserError, NoMethodError, TypeError => e
    Rails.logger.warn("[Outsider::Crm::CompanyLookup] #{provider}: resposta inesperada (#{e.class})")
    nil
  end

  def download(url)
    body = +''
    response = HTTParty.get(url, headers: HEADERS, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT, stream_body: true) do |fragment|
      next unless fragment.code == 200

      body << fragment
      raise TooLarge if body.bytesize > MAX_BYTES
    end
    return body if response.code == 200
    return :not_found if [400, 404].include?(response.code)

    failed(url, "HTTP #{response.code}")
  rescue TooLarge, HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, EOFError, OpenSSL::SSL::SSLError => e
    failed(url, e.class.name)
  end

  def failed(url, reason)
    Rails.logger.warn("[Outsider::Crm::CompanyLookup] #{URI(url).host}: #{reason}")
    nil
  end

  def customer_fields(provider, data)
    value = ->(key) { data.dig(*PATHS[provider][key]) if PATHS[provider][key] }
    state = value[:state]
    {
      'company' => value[:company], 'state_registration' => state_registration(provider, data, state),
      'address' => street_line([value[:street_type], value[:street]].compact_blank.join(' '), value[:number], value[:details]),
      'district' => value[:district], 'city' => value[:city], 'state' => state, 'zip' => format_zip(value[:zip]),
      'phone' => format_phone("#{value[:area]}#{value[:phone]}"), 'email' => value[:email]
    }
  end

  # IE ativa no estado do endereço: as de outros estados são de substituto tributário, não do cliente
  def state_registration(provider, data, state)
    keys = REGISTRATIONS[provider]
    return if keys.nil?

    registration = Array(data.dig(*keys[:list])).find do |item|
      item.dig(*keys[:enabled]) && item.dig(*keys[:state]) == state && item.dig(*keys[:number]).present?
    end
    registration&.dig(*keys[:number])
  end

  def street_line(street, number, details)
    line = [street, number].map { |part| part.to_s.strip }.compact_blank.join(', ')
    [line, details.to_s.strip].compact_blank.join(' - ')
  end

  def format_zip(value)
    digits = value.to_s.delete('^0-9')
    digits.length == 8 ? "#{digits[0, 5]}-#{digits[5, 3]}" : digits
  end

  def format_phone(value)
    digits = value.to_s.delete('^0-9')
    return digits unless [10, 11].include?(digits.length)

    "(#{digits[0, 2]}) #{digits[2..-5]}-#{digits[-4..]}"
  end

  def formatted_document
    "#{@document[0, 2]}.#{@document[2, 3]}.#{@document[5, 3]}/#{@document[8, 4]}-#{@document[12, 2]}"
  end
end
