# OUTSIDER: confere e arruma os dados do "Cadastrar cliente no ERP" antes de irem para a função do Mais Prático
# (Outsider::Erp::ClientRegistrar). Não fala com o ERP: só valida o CPF/CNPJ pelos dígitos verificadores (o CNPJ pode
# ser o alfanumérico da Receita, de julho/2026), o nome, a UF, o CEP e o e-mail, e limpa os textos.
class Outsider::Erp::ClientForm
  UFS = %w[AC AL AP AM BA CE DF ES GO MA MT MS MG PA PB PR PE PI RJ RN RS RO RR SC SP SE TO].freeze
  # campo da tela => tamanho máximo antes de conferir no ERP (o corte final é o da coluna/parâmetro da unidade)
  TEXTS = {
    'nome' => 120, 'apelido' => 80, 'rg_ie' => 30, 'endereco' => 120, 'numero' => 20, 'bairro' => 80, 'referencia' => 120,
    'cidade' => 80, 'telefone' => 30, 'celular' => 30, 'observacoes' => 500, 'contato_nome' => 80, 'contato_telefone' => 30
  }.freeze
  EMAILS = %w[email contato_email].freeze
  # textos que vão em maiúsculas quando a unidade cadastra assim (Outsider::Erp::ClientProfile#uppercase?)
  UPPER = %w[nome apelido rg_ie endereco numero bairro referencia cidade contato_nome].freeze
  CNPJ = /\A[0-9A-Z]{12}\d{2}\z/
  CPF = /\A\d{11}\z/

  attr_reader :values, :errors

  def initialize(params)
    @params = params.to_h.stringify_keys
    @errors = []
    @values = build
  end

  def valid? = errors.empty?
  # só os caracteres do documento (números e, no CNPJ novo, letras)
  def document = values['documento']
  def person = document.size == 14 ? 'J' : 'F'
  def copy_address? = @params['copiar_endereco'] != false && @params['copiar_endereco'].to_s != 'false'
  def address? = values['endereco'].present?

  # "12.345.678/0001-90" ou "123.456.789-01"
  def masked_document
    return "#{document[0, 2]}.#{document[2, 3]}.#{document[5, 3]}/#{document[8, 4]}-#{document[12, 2]}" if person == 'J'

    "#{document[0, 3]}.#{document[3, 3]}.#{document[6, 3]}-#{document[9, 2]}"
  end

  def masked_cep = values['cep'].present? ? "#{values['cep'][0, 5]}-#{values['cep'][5, 3]}" : nil

  def self.clean_document(value) = value.to_s.upcase.gsub(/[^0-9A-Z]/, '')

  # CPF (11 números) ou CNPJ (14: 12 números/letras + 2 dígitos), com os dígitos verificadores certos
  def self.valid_document?(value)
    return cpf?(value) if value.match?(CPF)

    value.match?(CNPJ) && cnpj?(value)
  end

  def self.cpf?(value)
    return false if value.chars.uniq.size == 1

    [9, 10].all? { |size| check_digit(value.first(size).chars.map(&:to_i), (2..size + 1).to_a.reverse) == value[size].to_i }
  end

  # o valor de cada caractere é o código ASCII menos 48 (0-9 continuam 0-9; A = 17), como na regra da Receita
  def self.cnpj?(value)
    return false if value.chars.uniq.size == 1

    numbers = value.chars.map { |char| char.ord - 48 }
    weights = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]
    check_digit(numbers.first(12), weights) == numbers[12] && check_digit(numbers.first(13), [6] + weights) == numbers[13]
  end

  def self.check_digit(numbers, weights)
    rest = numbers.zip(weights).sum { |number, weight| number * weight } % 11
    rest < 2 ? 0 : 11 - rest
  end

  private

  def build
    values = TEXTS.to_h { |key, max| [key, @params[key].to_s.squish.first(max).presence] }
    EMAILS.each { |key| values[key] = email(key) }
    values.merge('documento' => document_value, 'uf' => uf, 'cep' => cep, 'vendedor' => seller).tap { |out| check_name(out) }
  end

  def document_value
    value = self.class.clean_document(@params['documento'])
    @errors << 'documento' unless self.class.valid_document?(value)
    value
  end

  def check_name(values)
    @errors << 'nome' if values['nome'].to_s.length < 3
  end

  def email(key)
    value = @params[key].to_s.strip.downcase.presence
    @errors << key if value && (value.length > 100 || !value.match?(URI::MailTo::EMAIL_REGEXP))
    value
  end

  def uf
    value = @params['uf'].to_s.strip.upcase.presence
    @errors << 'uf' if value && UFS.exclude?(value)
    value
  end

  def cep
    value = @params['cep'].to_s.gsub(/\D/, '').presence
    @errors << 'cep' if value && value.length != 8
    value
  end

  def seller
    value = Integer(@params['vendedor'].to_s.strip.presence || '0', exception: false)
    @errors << 'vendedor' if value.nil? || value.negative? || value > 999_999_999
    value.to_i
  end
end
