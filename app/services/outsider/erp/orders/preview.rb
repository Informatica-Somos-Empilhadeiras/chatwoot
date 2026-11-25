# OUTSIDER: a conferência que a tela "Converter em OS" mostra antes de converter, só leitura (a mesma do
# Outsider::Erp::Orders::Creator, sem reservar nem gravar nada): orçamento em NEGOCIAÇÃO, sem OS, sem pedido e sem
# ninguém com ele aberto, permissão "Conversão OS" do usuário do ERP da pessoa, cliente e estrutura das tabelas.
class Outsider::Erp::Orders::Preview
  def initialize(draft, user:)
    @draft = draft
    @user = user
    @settings = Outsider::Erp::Settings.new(draft.account)
    @client = Outsider::Erp::Client.new(@settings)
    @schema = Outsider::Erp::Schema.new(draft.account, client: @client)
  end

  def call
    erp_user = @settings.data['user_erp_ids'].to_h[@user&.id.to_s].to_i
    sql = Outsider::Erp::Orders::Sql.new(@draft, erp_user: erp_user)
    quote = Array.wrap(@client.query_execute(sql.quote_state_sql)).grep(Hash).first
    checks = Outsider::Erp::Orders::Checks.new(@draft, erp_user: erp_user, client: @client, schema: @schema)
    begin
      list = checks.conversion!(quote, machine: false)
      { ok: true, checks: list, quote: summary(quote) }
    rescue Outsider::Erp::Orders::Checks::Invalid => e
      { ok: false, error: e.message, checks: e.checks, quote: summary(quote) }
    end
  end

  private

  def summary(row)
    return unless row

    { numero: row['numero'], status: row['status'], cliente: row['cliente'], total: row['total'], itens: row['itens'],
      os: row['os'].to_i.positive? ? row['os'] : row['os_ligada'], em_uso_por: row['em_uso_recente'].to_i == 1 ? row['em_uso_por'] : nil }
  end
end
