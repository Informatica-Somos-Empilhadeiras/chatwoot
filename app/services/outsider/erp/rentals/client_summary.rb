# OUTSIDER: o bloco "Contratos e máquinas" do contato (painel da conversa): para os clientes do ERP ligados ao contato
# (Outsider::Erp::ContactLink), os contratos (ativos primeiro), as máquinas que estão nos contratos ativos com a situação
# de agora (no cliente, em OS...) e as máquinas que são do próprio cliente (cadastro com o código dele, fora da frota da
# Somos). Só leitura; poucas consultas (uma por assunto, juntando as unidades).
class Outsider::Erp::Rentals::ClientSummary < Outsider::Erp::Rentals::Reader
  CONTRACTS = 8
  MACHINES = 20

  # links: [{ 'empresa' =>, 'codigo' => }]
  def build(links)
    pairs = links.filter_map do |link|
      [link['empresa'].to_s, link['codigo'].to_i] if @settings.companies.include?(link['empresa'].to_s) && link['codigo'].to_i.positive?
    end.uniq
    return { 'contracts' => [], 'machines' => [] } if pairs.empty?

    contracts = contracts(pairs)
    { 'contracts' => with_machines(contracts), 'machines' => own_machines(pairs) }
  end

  private

  def contracts(pairs)
    sql = union(pairs.map(&:first).uniq, order: "(X.status = 'ATIVO') DESC, X.inicio DESC, X.numero DESC", limit: CONTRACTS) do |company|
      codes = pairs.select { |pair| pair.first == company }.map(&:last)
      "SELECT #{S.str(company)} AS banco, #{list(company, 'contrato', 'O', contract_fields)} FROM #{S.ident(company)}.contrato O " \
        "WHERE O.`CodigoCliente` IN (#{codes.join(', ')})"
    end
    run(sql).map { |row| row.merge('status' => row['status'].to_s.upcase.presence) }
  end

  def contract_fields
    { 'numero' => %w[CodigoContrato], 'tipo' => %w[TipoContratos], 'status' => %w[Status], 'inicio' => %w[DataInicio],
      'termino' => %w[DataTermino], 'total' => %w[Total], 'parcela' => %w[Vrparcelas], 'periodicidade' => %w[periodicidadeContrato] }
  end

  # as máquinas ainda no cliente de cada contrato ativo (uma consulta por unidade com contrato ativo)
  def with_machines(contracts)
    active = contracts.select { |row| row['status'] == 'ATIVO' }.group_by { |row| row['banco'] }
    rows = active.flat_map { |company, items| machines_out(company, items.map { |row| row['numero'].to_i }) }
    contracts.map { |row| row.merge('maquinas' => rows.select { |item| same_contract?(item, row) }) }
  end

  def same_contract?(item, row) = item['banco'] == row['banco'] && item['contrato'].to_i == row['numero'].to_i

  def machines_out(company, numbers)
    bank = S.ident(company)
    sql = "SELECT D.`CodigoContrato` AS contrato, D.`CodigoEquipto` AS maquina, #{list(company, 'detalhecontrato', 'D',
                                                                                       ITEM.slice('saida', 'retorno'))}, " \
          "#{machine_fields(company)} FROM #{bank}.detalhecontrato D LEFT JOIN #{bank}.equipamentos O ON O.`Seq` = D.`CodigoEquipto`" \
          "#{status_joins(company)} WHERE D.`CodigoContrato` IN (#{numbers.join(', ')}) LIMIT #{MACHINES}"
    run(sql).reject { |row| past?(row['retorno']) }.map { |row| row.merge('banco' => company, 'base' => @fleet.base(company)) }
  end

  # máquinas do próprio cliente: cadastro com o código dele nas unidades com cadastro próprio, fora da frota da Somos
  def own_machines(pairs)
    sql = union(pairs.map(&:first).uniq & @fleet.bases, order: 'X.ultima_os DESC', limit: MACHINES) do |company|
      codes = pairs.select { |pair| pair.first == company }.map(&:last)
      "SELECT #{S.str(company)} AS banco, O.`Seq` AS numero, #{machine_fields(company)} FROM #{S.ident(company)}.equipamentos O" \
        "#{status_joins(company)} WHERE O.`CodClientes` IN (#{codes.join(', ')}) AND NOT #{@machine_status.own}"
    end
    run(sql)
  end
end
