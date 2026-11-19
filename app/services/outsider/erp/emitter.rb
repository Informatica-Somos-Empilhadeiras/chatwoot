# OUTSIDER: dados da empresa emitente de uma unidade (cabeçalho do PDF do orçamento): nome, CNPJ, IE, endereço,
# telefone, site, e-mail e logo, lidos da tabela empresa do ERP (a mesma que o Mais Prático usa nos relatórios: as
# colunas *Impressao). Só leitura, filtrado pelo banco da unidade; fica no Redis por um dia. Coluna que não existe ou
# vem vazia cai na próxima candidata. Logo só JPEG/PNG (o que o Prawn desenha); senão vai o logo padrão da Somos.
class Outsider::Erp::Emitter
  S = Outsider::Erp::Sql
  TABLE = 'empresa'.freeze
  TTL = 1.day
  DEFAULT_LOGO = Rails.root.join('config/outsider_erp/logo.jpg')
  # campo => colunas candidatas, na ordem de preferência (vale a primeira preenchida)
  FIELDS = {
    'nome' => %w[NomeImpressao RazaoSocial Nome NomeEmpresa], 'cnpj' => %w[CNPJ CPF_CNPJ CGC], 'ie' => %w[IE InscricaoEstadual InscEstadual RGIE],
    'endereco' => %w[Endereco Logradouro], 'numero' => %w[Numero], 'bairro' => %w[Bairro], 'cidade' => %w[Cidade Municipio],
    'uf' => %w[UF Estado], 'cep' => %w[CEP], 'fone' => %w[TelefoneImpressao Telefone Fone], 'site' => %w[homepage Site],
    'email' => %w[EmailImpressao Email]
  }.freeze

  def initialize(account, client: nil)
    @account = account
    @client = client || Outsider::Erp::Client.new(Outsider::Erp::Settings.new(account))
    @schema = Outsider::Erp::Schema.new(account, client: @client)
  end

  # { 'nome', 'cnpj', ..., 'logo' => bytes JPEG/PNG }
  def data_for(company)
    data = cached(company)
    data.merge('logo' => logo_bytes(data.delete('logo64')))
  end

  private

  def cached(company)
    key = "outsider_erp:#{@account.id}:emitter:#{company}"
    raw = Redis::Alfred.get(key)
    return JSON.parse(raw) if raw

    data = read(company)
    Redis::Alfred.set(key, data.to_json, ex: TTL.to_i) if data['nome'].present?
    data
  rescue Outsider::Erp::Client::Error
    {}
  end

  def read(company)
    selects = select_list(@schema.columns(company, TABLE).index_by(&:downcase))
    return {} if selects.empty?

    row = @client.query_execute("SELECT #{selects.join(', ')} FROM #{S.ident(company)}.empresa E LIMIT 1").grep(Hash).first.to_h
    FIELDS.keys.index_with { |key| first_filled(row, key) }.merge('logo64' => row['logo64'].to_s.delete("\n").presence)
  end

  # cada candidata vira key__N (a primeira preenchida vale); o logo vem em base64 (o JSON não leva binário)
  def select_list(columns)
    selects = FIELDS.flat_map do |key, candidates|
      candidates.each_with_index.filter_map { |name, index| "E.#{S.column(columns[name.downcase])} AS #{key}__#{index}" if columns[name.downcase] }
    end
    columns['logo'] ? selects + ['TO_BASE64(E.`Logo`) AS logo64'] : selects
  end

  def first_filled(row, key)
    row.select { |name, _| name.start_with?("#{key}__") }.sort.map { |_, value| value.to_s.strip }.find(&:present?)
  end

  def logo_bytes(base64)
    bytes = base64.present? ? Base64.decode64(base64) : nil
    return bytes if bytes&.start_with?("\xFF\xD8".b, "\x89PNG".b)

    File.binread(DEFAULT_LOGO) if File.exist?(DEFAULT_LOGO)
  end
end
