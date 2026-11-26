# OUTSIDER (Maps): grava no cadastro do cliente do Mais Prático os campos VAZIOS que a consulta do CNPJ completou
# (Outsider::Erp::ScheduleMap#client). O ERP não tem rotina para alterar um cliente que já existe (só sp_CadastraCliente,
# que cria), então é um UPDATE direto e só de campo vazio: cada coluna recebe o valor só se ainda estiver vazia na hora
# (a condição está no próprio UPDATE), e o resto do cadastro nunca muda. Só com "Gravar no ERP" ligado e a linha
# "Completar cadastro do cliente no ERP" no perfil (o controlador confere). Respeita o tamanho de cada coluna e o hábito da
# unidade de nomes em maiúsculas (Outsider::Erp::ClientProfile). Lê de volta para dizer o que ficou gravado.
class Outsider::Erp::ClientCompleter
  S = Outsider::Erp::Sql
  # os campos que podem ser completados (nome e CPF/CNPJ nunca)
  FIELDS = Outsider::Erp::CustomerRecord::FIELDS.slice('fantasia', 'ie', 'endereco', 'numero', 'complemento', 'bairro', 'cidade', 'uf',
                                                       'cep', 'fone', 'email')

  class Disabled < StandardError; end

  def initialize(account)
    @account = account
    @settings = Outsider::Erp::Settings.new(account)
  end

  # values: { 'bairro' => 'Centro', ... } (os completados que a tela mostrou) => { written: [campos], record: cadastro novo }
  def call(company, code, values)
    raise Disabled unless @settings.write_enabled?
    raise ArgumentError, 'empresa' unless @settings.companies.include?(company.to_s)

    columns = columns_for(company, values.to_h.stringify_keys.slice(*FIELDS.keys))
    before = record(company, code)
    if columns.any?
      sets = columns.map do |column, value|
        "#{S.column(column)} = IF(#{S.column(column)} IS NULL OR TRIM(#{S.column(column)}) = '', #{S.str(value)}, #{S.column(column)})"
      end
      client.query_execute("UPDATE #{S.ident(company)}.clientes SET #{sets.join(', ')} WHERE CodigoCliente = #{S.int(code)} LIMIT 1")
    end
    after = record(company, code)
    Rails.cache.delete("outsider_erp_map_record/v1/#{@account.id}/#{company}/#{code}")
    { written: FIELDS.keys.select { |field| before[field].blank? && after[field].present? }, record: after }
  end

  private

  # { 'Bairro' => 'CENTRO' } com o nome real da coluna, o tamanho dela e as maiúsculas da unidade
  def columns_for(company, values)
    schema = Outsider::Erp::Schema.new(@account, client: client)
    upper = Outsider::Erp::ClientProfile.new(@account, company, client: client).uppercase?
    sizes = column_sizes(company)
    values.each_with_object({}) do |(field, value), out|
      column = schema.pick(company, 'clientes', FIELDS[field])
      text = value.to_s.squish
      next if column.nil? || text.blank?

      text = text.upcase if upper && field != 'email'
      out[column] = text.first(sizes[column.downcase] || 60)
    end
  end

  def column_sizes(company)
    sql = 'SELECT COLUMN_NAME AS nome, CHARACTER_MAXIMUM_LENGTH AS tamanho FROM information_schema.COLUMNS ' \
          "WHERE TABLE_SCHEMA = #{S.str(company)} AND LOWER(TABLE_NAME) = 'clientes'"
    client.query_execute(sql).grep(Hash).to_h { |row| [row['nome'].to_s.downcase, row['tamanho'].to_i.positive? ? row['tamanho'].to_i : nil] }
  end

  def record(company, code) = Outsider::Erp::CustomerRecord.new(@account, client: client).find(company, code)
  def client = @client ||= Outsider::Erp::Client.new(@settings)
end
