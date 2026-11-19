# OUTSIDER: formas de pagamento do ERP (tabela formapagto das unidades), para o administrador escolher a padrão do
# orçamento numa lista em vez de digitar o código. Só leitura, via query_execute, banco a banco. O mesmo código com
# descrições diferentes entre as unidades aparece junto ("BOLETO / À VISTA"), para ninguém escolher às cegas.
class Outsider::Erp::PaymentTerms
  S = Outsider::Erp::Sql
  READ_TIMEOUT = 6
  MAX = 500

  def initialize(account)
    @settings = Outsider::Erp::Settings.new(account)
    @client = Outsider::Erp::Client.new(@settings)
  end

  # [{ codigo:, descricao: }] em ordem alfabética
  def list
    rows = @settings.companies.flat_map { |company| @client.query_execute(sql(company), read_timeout: READ_TIMEOUT).grep(Hash) }
    terms = rows.group_by { |row| row['Codigo'].to_i }.except(0).map { |code, list| term(code, list) }
    terms.sort_by { |row| row[:descricao] }
  end

  private

  def term(code, list)
    { codigo: code, descricao: list.map { |row| row['Descricao'].to_s.squish }.compact_blank.uniq.join(' / ') }
  end

  def sql(company)
    "SELECT F.Codigo, F.Descricao FROM #{S.ident(company)}.formapagto F ORDER BY F.Descricao LIMIT #{MAX}"
  end
end
