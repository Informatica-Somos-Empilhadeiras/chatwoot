# OUTSIDER: troca as {{variáveis}} dos textos e dos blocos do bot.
#
#   {{contato.nome}} {{contato.primeiro_nome}} {{contato.telefone}} {{contato.email}} {{contato.empresa}}
#   {{contato.cidade}} {{conversa.numero}} {{primeira_mensagem}} {{resposta}} (respostas guardadas) e campos
#   dentro do resultado de um bloco: {{pedido.status}}, {{pedido.itens.0.nome}} (Outsider::Bot::JsonPath)
#
# Filtros, um depois do outro: {{cnpj | digitos}} {{nome | maiusculas}} {{nome | minusculas}}
#   {{nome | sem_acentos}} {{valor | moeda}} {{vencimento | data}} {{criado | data_hora}} {{codigo | url}}
#   {{telefone | digitos | ultimos:8}} {{texto | primeiros:20}} {{apelido | padrao:cliente}}
#
# context diz onde o valor vai entrar:
#   :text   mensagens (padrão)
#   :url    caminho da API: cada valor vai codificado, então o que o cliente digita nunca muda o endereço
#   :json   corpo JSON: dentro de aspas vira texto escapado; fora delas, número ou texto JSON
#   :xml    corpo XML: escapado
#   :header cabeçalho: sem quebra de linha
#   :segment pasta do Nextcloud: o valor não traz "/" nem "..", então não sai da pasta escolhida
class Outsider::Bot::Template
  PATTERN = /\{\{\s*([a-z0-9_.\[\]*]+)\s*((?:\|\s*[a-z_]+(?::[^|}]*)?\s*)*)\}\}/i
  FILTER = /\|\s*([a-z_]+)(?::([^|}]*))?/i
  NUMERIC = /\A-?(?:0|[1-9]\d{0,14})(?:\.\d+)?\z/
  TIMEZONE = 'America/Sao_Paulo'.freeze

  attr_reader :variables

  def self.for_conversation(conversation, variables)
    new(variables, contact: contact_values(conversation.contact),
                   conversation: { 'id' => conversation.display_id, 'numero' => conversation.display_id })
  end

  def self.contact_values(contact)
    return {} unless contact

    name = contact.name.to_s
    extra = contact.additional_attributes.to_h
    { 'nome' => name, 'primeiro_nome' => name.split.first.to_s, 'telefone' => contact.phone_number.to_s, 'email' => contact.email.to_s,
      'empresa' => extra['company_name'].to_s, 'cidade' => extra['city'].to_s, 'id' => contact.id }
  end

  # número escrito do jeito brasileiro ou não: "1.234,56", "1234.56", "R$ 99,90"
  def self.number(value)
    return value if value.is_a?(Numeric)

    text = value.to_s.gsub(/[^\d,.-]/, '')
    return unless text.match?(/\d/)

    BigDecimal(normalize_number(text))
  rescue ArgumentError
    nil
  end

  def self.normalize_number(text)
    if text.include?(',') && text.include?('.')
      text.rindex(',') > text.rindex('.') ? text.delete('.').tr(',', '.') : text.delete(',')
    elsif text.include?(',')
      text.count(',') == 1 ? text.tr(',', '.') : text.delete(',')
    elsif text.count('.') > 1 || text.match?(/\A-?\d{1,3}(\.\d{3})+\z/)
      text.delete('.')
    else
      text
    end
  end

  def initialize(variables, contact: nil, conversation: nil)
    @variables = variables.to_h.stringify_keys
    return if contact.nil? && conversation.nil?

    contact = contact.to_h.stringify_keys
    @variables = @variables.merge('contato' => contact, 'conversa' => conversation.to_h.stringify_keys,
                                  'nome_contato' => contact['nome'], 'primeiro_nome' => contact['primeiro_nome'])
  end

  # o mesmo, com mais variáveis (por exemplo {{link}} do documento)
  def with(extra)
    self.class.new(@variables.merge(extra.to_h.stringify_keys))
  end

  def render(text, context: :text)
    text = text.to_s
    return render_json(text) if context == :json

    text.gsub(PATTERN) { encode(value_of(Regexp.last_match(1), Regexp.last_match(2)), context) }
  end

  # SQL do bloco Banco de dados: cada {{variável}} vira um parâmetro ($1, $2...) e o valor vai à parte.
  # Dentro de aspas ('%{{busca}}%') o texto é fechado e emendado: '%' || $1::text || '%'
  def render_sql(text)
    params = []
    out = +''
    quoted = false
    scanner = StringScanner.new(text.to_s)
    until scanner.eos?
      if scanner.scan(PATTERN)
        params << sql_value(value_of(scanner[1], scanner[2]))
        out << (quoted ? "' || $#{params.size}::text || '" : "$#{params.size}")
        next
      end
      char = scanner.getch
      quoted = !quoted if char == "'"
      out << char
    end
    [out, params]
  end

  def value_of(path, filters = '')
    value = Outsider::Bot::JsonPath.dig(@variables, path)
    filters.to_s.scan(FILTER).reduce(value) { |current, (name, arg)| apply_filter(current, name.downcase, arg.to_s.strip) }
  end

  def to_text(value)
    case value
    when nil then ''
    when String then value
    when BigDecimal then value.to_s('F').delete_suffix('.0')
    when Float then value.finite? && value == value.floor && value.abs < 1e15 ? value.to_i.to_s : value.to_s
    when Array then value.none? { |item| item.is_a?(Hash) || item.is_a?(Array) } ? value.map { |item| to_text(item) }.join(', ') : value.to_json
    when Hash then value.to_json
    else value.to_s
    end
  end

  private

  def encode(value, context)
    text = to_text(value)
    case context
    when :url then url_encode(text)
    when :xml then ERB::Util.html_escape(text)
    when :header then text.gsub(/[\r\n]+/, ' ').first(1000)
    when :segment then text.tr('/\\', '  ').gsub(/\.{2,}/, '.')
    else text
    end
  end

  # "." e ".." viram %2E para não subir de pasta no endereço
  def url_encode(text)
    text.match?(/\A\.+\z/) ? text.gsub('.', '%2E') : ERB::Util.url_encode(text)
  end

  # rubocop:disable Metrics/CyclomaticComplexity
  def apply_filter(value, name, arg)
    case name
    when 'digitos' then to_text(value).gsub(/\D/, '')
    when 'maiusculas' then to_text(value).upcase
    when 'minusculas' then to_text(value).downcase
    when 'sem_acentos' then ActiveSupport::Inflector.transliterate(to_text(value), '')
    when 'ultimos' then to_text(value).last(arg.to_i.clamp(1, 1000))
    when 'primeiros' then to_text(value).first(arg.to_i.clamp(1, 1000))
    when 'padrao' then to_text(value).strip.empty? ? arg : value
    when 'moeda' then currency(value)
    when 'data' then date(value, '%d/%m/%Y')
    when 'data_hora' then date(value, '%d/%m/%Y %H:%M')
    when 'url' then url_encode(to_text(value))
    else value
    end
  end
  # rubocop:enable Metrics/CyclomaticComplexity

  def currency(value)
    number = self.class.number(value)
    return to_text(value) unless number

    ActiveSupport::NumberHelper.number_to_currency(number, unit: 'R$', format: '%u %n', separator: ',', delimiter: '.', precision: 2)
  end

  def date(value, pattern)
    text = to_text(value).strip
    return text if text.empty? || text.match?(%r{\A\d{2}/\d{2}/\d{4}})

    zone = ActiveSupport::TimeZone[TIMEZONE]
    time = text.match?(/\A\d{10}(\d{3})?\z/) ? zone.at(text.first(10).to_i) : zone.parse(text)
    time ? time.strftime(pattern) : text
  rescue ArgumentError
    text
  end

  # JSON: o valor entra escapado dentro de aspas e como número ou texto JSON fora delas
  def render_json(text)
    out = +''
    scanner = StringScanner.new(text)
    state = { string: false, escaped: false }
    until scanner.eos?
      if scanner.scan(PATTERN)
        value = value_of(scanner[1], scanner[2])
        out << (state[:string] ? to_text(value).to_json[1..-2] : json_literal(value))
        next
      end
      char = scanner.getch
      track_string(state, char)
      out << char
    end
    out
  end

  def track_string(state, char)
    if state[:escaped]
      state[:escaped] = false
    elsif state[:string] && char == '\\'
      state[:escaped] = true
    elsif char == '"'
      state[:string] = !state[:string]
    end
  end

  def sql_value(value)
    case value
    when nil then nil
    when Hash, Array then value.to_json
    else to_text(value)
    end
  end

  def json_literal(value)
    case value
    when String then value.match?(NUMERIC) ? value : value.to_json
    when nil then 'null'
    when BigDecimal then to_text(value)
    else value.to_json
    end
  end
end
