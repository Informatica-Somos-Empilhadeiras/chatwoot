# OUTSIDER: lista das faturas de locação do ERP (tabela faturacontrato), só para ver. É um documento próprio do contrato
# (não é NF-e nem NFS-e); o contrato vem de faturacontratocorrelacao (fatura + série -> contrato). A pessoa é o vendedor.
class Outsider::Erp::Records::RentalInvoiceKind < Outsider::Erp::Records::Kind
  S = Outsider::Erp::Sql

  def table = 'faturacontrato'
  def person = :pessoa_codigo
  def status_views? = true

  def columns
    {
      numero: %w[CodigoFatura], data: %w[DataEmissao], status: %w[Status], total: %w[TotalFatura Total],
      cliente_codigo: %w[CodigoDestinatario], pessoa_codigo: %w[Vendedor], serie: %w[Serie]
    }
  end

  def computed(company, schema)
    return ['NULL AS contrato'] unless schema.pick(company, 'faturacontratocorrelacao', %w[CodigoContrato])

    ["(SELECT MIN(R.`CodigoContrato`) FROM #{S.ident(company)}.faturacontratocorrelacao R " \
     'WHERE R.`CodigoFatura` = O.`CodigoFatura` AND R.`Serie` = O.`Serie`) AS contrato']
  end
end
