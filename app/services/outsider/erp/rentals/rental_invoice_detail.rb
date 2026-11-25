# OUTSIDER: o detalhe de uma fatura de locação (faturacontrato) para o painel da aba Faturas de locação: cabeçalho,
# cliente (CodigoDestinatario), os contratos que ela cobra (faturacontratocorrelacao) e as máquinas cobradas
# (detalhefaturacontrato, com o período de cada uma). É um documento do contrato, não é NF-e nem NFS-e. Só leitura.
class Outsider::Erp::Rentals::RentalInvoiceDetail < Outsider::Erp::Rentals::Reader
  HEADER = INVOICE.merge('cliente_codigo' => %w[CodigoDestinatario], 'vendedor' => %w[Vendedor], 'vendedor_nome' => %w[NomeVendedor])
  ITEMS = { 'contrato' => %w[CodigoContrato], 'item' => %w[CodigoItemContrato], 'maquina' => %w[CodigoEquipto],
            'inicio' => %w[DataInicioContratoMaq_Impresso], 'termino' => %w[DataTerminoContratoMaq_Impresso] }.freeze

  def build(company, number)
    check!(company)
    header = header(company, number)
    {
      'kind' => 'rental_invoices', 'company' => company, 'numero' => number.to_i, 'header' => header,
      'cliente' => customer(company, header['cliente_codigo']), 'contratos' => contracts(company, header),
      'maquinas' => machines(company, header)
    }.merge(contact(company, header['cliente_codigo']))
  end

  private

  # a mesma numeração pode ter mais de uma série: vale a emitida por último
  def header(company, number)
    sql = "SELECT #{list(company, 'faturacontrato', 'O', HEADER)} FROM #{S.ident(company)}.faturacontrato O " \
          "WHERE O.`CodigoFatura` = #{S.int(number)} ORDER BY O.`DataEmissao` DESC LIMIT 1"
    row = run(sql).first || raise(NotFound, number.to_s)
    row['vendedor_nome'].present? ? row : row.merge('vendedor_nome' => person(company, row['vendedor']))
  end

  def same_invoice(table_alias, header)
    "#{table_alias}.`CodigoFatura` = #{S.int(header['numero'])} AND #{table_alias}.`Serie` = #{S.str(header['serie'].to_s)}"
  end

  def contracts(company, header)
    bank = S.ident(company)
    sql = "SELECT DISTINCT #{list(company, 'contrato', 'C', CONTRACT)} FROM #{bank}.faturacontratocorrelacao R " \
          "JOIN #{bank}.contrato C ON C.`CodigoContrato` = R.`CodigoContrato` WHERE #{same_invoice('R', header)} ORDER BY contrato"
    run(sql)
  end

  def machines(company, header)
    bank = S.ident(company)
    sql = "SELECT #{list(company, 'detalhefaturacontrato', 'M', ITEMS)}, #{list(company, 'equipamentos', 'O', MACHINE)} " \
          "FROM #{bank}.detalhefaturacontrato M LEFT JOIN #{bank}.equipamentos O ON O.`Seq` = M.`CodigoEquipto` " \
          "WHERE #{same_invoice('M', header)} ORDER BY contrato, item LIMIT 100"
    run(sql).map { |row| row.merge('base' => @fleet.base(company)) }
  end
end
