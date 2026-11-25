# OUTSIDER: a situação de uma máquina (equipamentos) montada das outras tabelas, porque o ERP não preenche "locado" nem
# "contrato" no cadastro dela (descoberta de 25/11/2026: CkLocado, Contrato e NFRemessa vazios em todas). Regras, na ordem:
# - EM OS: tem OS aberta (fora das situações travadas das Configurações);
# - LOCADA: está num item de contrato de locação ATIVO e ainda não voltou (sem DataRetorno ou retorno no futuro);
# - EM CONTRATO: idem, num contrato ativo de outro tipo (manutenção, prestação de serviço);
# - DISPONÍVEL: frota da Somos (Propriedade 0 ou proprietário "SOMOS EMPILHADEIRAS...") fora de contrato e de OS;
# - DO CLIENTE: o resto (máquina que o cliente é dono, sem OS aberta nem contrato).
# As OS e os contratos são procurados em todas as unidades que enxergam o mesmo cadastro (Outsider::Erp::Rentals::Fleet).
# Só monta SQL: dois LEFT JOIN agrupados (MO: as OS; MC: os itens de contrato ativos) e as expressões sobre eles. "O" é o
# apelido da tabela equipamentos na consulta de quem chama. Número e unidade da OS/contrato vêm juntos num texto
# "0000002080:somosemp" (o MAX escolhe o mais novo) e são separados aqui.
class Outsider::Erp::Rentals::MachineStatus
  S = Outsider::Erp::Sql
  STATUSES = ['EM OS', 'LOCADA', 'EM CONTRATO', 'DISPONÍVEL', 'DO CLIENTE'].freeze

  def initialize(settings, fleet)
    @settings = settings
    @fleet = fleet
  end

  def joins(base, schema)
    members = @fleet.members(base)
    "#{order_join(members, schema)}#{contract_join(base, members, schema)}"
  end

  def status
    "(CASE WHEN MO.os_ref IS NOT NULL THEN 'EM OS' WHEN LEFT(MC.contrato_ref, 1) = '1' THEN 'LOCADA' " \
      "WHEN MC.contrato_ref IS NOT NULL THEN 'EM CONTRATO' WHEN #{own} THEN 'DISPONÍVEL' ELSE 'DO CLIENTE' END)"
  end

  # frota da Somos (1) ou do cliente (0)
  def own = "(IFNULL(O.`Propriedade`, 1) = 0 OR IFNULL(O.`Proprietario`, '') LIKE 'SOMOS EMPILHADEIRAS%')"

  # onde a máquina está: o cliente do contrato ativo (quando o contrato é da unidade do cadastro); senão, o do cadastro
  def client = 'IFNULL(MC.cliente, O.`CodClientes`)'

  # colunas calculadas: frota própria, contrato ativo (número e unidade), OS aberta (número e unidade), horímetro da OS
  # mais nova que o tem, data da última OS e quantas OS
  def fields
    ["#{own} AS propria", 'CAST(SUBSTRING(MC.contrato_ref, 2, 10) AS UNSIGNED) AS contrato',
     "SUBSTRING_INDEX(MC.contrato_ref, ':', -1) AS contrato_banco", 'CAST(LEFT(MO.os_ref, 10) AS UNSIGNED) AS os_aberta',
     "SUBSTRING_INDEX(MO.os_ref, ':', -1) AS os_banco", 'MO.horimetro AS horimetro', 'MO.ultima_os AS ultima_os',
     'IFNULL(MO.total_os, 0) AS total_os']
  end

  # item de contrato ativo e não devolvido (D = detalhecontrato, C = contrato)
  def active_item
    "UPPER(TRIM(IFNULL(C.`Status`, ''))) = 'ATIVO' AND (D.`DataRetorno` IS NULL OR D.`DataRetorno` > NOW())"
  end

  # contrato de locação pelo texto do tipo (tipocontratos: CONTRATO DE LOCAÇÃO, PRESTAÇÃO DE SERVIÇO, CONTRATO DE MANUTENÇÃO)
  def rental_sql = "UPPER(IFNULL(C.`TipoContratos`, '')) LIKE '%LOCA%'"

  # OS aberta = situação fora das travadas (a mesma regra da lista de OS)
  def open_sql(table_alias)
    "(NULLIF(TRIM(#{table_alias}.`Situacao`), '') IS NULL OR UPPER(TRIM(#{table_alias}.`Situacao`)) NOT IN (#{locked}))"
  end

  def self.rental?(type) = type.to_s.upcase.include?('LOCA')

  private

  def order_join(members, schema)
    selects = members.filter_map do |company|
      next unless schema.pick(company, 'os', %w[CodigoMaquina])

      meter = schema.pick(company, 'os', %w[Horimetro])
      "SELECT #{S.str(company)} AS banco, S.`CodigoMaquina` AS maquina, S.`CodigoOS` AS numero, S.`DataEntrada` AS data, " \
        "#{open_sql('S')} AS aberta, #{meter ? "NULLIF(TRIM(S.#{S.column(meter)}), '')" : 'NULL'} AS horimetro " \
        "FROM #{S.ident(company)}.os S WHERE S.`CodigoMaquina` > 0"
    end
    return ' LEFT JOIN (SELECT NULL AS maquina, NULL AS os_ref, NULL AS ultima_os, NULL AS horimetro, 0 AS total_os) MO ON 1 = 0' if selects.empty?

    " LEFT JOIN (SELECT U.maquina, MAX(CASE WHEN U.aberta THEN CONCAT(LPAD(U.numero, 10, '0'), ':', U.banco) END) AS os_ref, " \
      "MAX(U.data) AS ultima_os, SUBSTRING_INDEX(GROUP_CONCAT(U.horimetro ORDER BY U.data DESC, U.numero DESC SEPARATOR '|'), '|', 1) " \
      "AS horimetro, COUNT(*) AS total_os FROM (#{selects.join(' UNION ALL ')}) U GROUP BY U.maquina) MO ON MO.maquina = O.`Seq`"
  end

  def contract_join(base, members, schema)
    selects = members.filter_map do |company|
      next unless schema.pick(company, 'detalhecontrato', %w[CodigoEquipto]) && schema.pick(company, 'contrato', %w[TipoContratos])

      bank = S.ident(company)
      "SELECT #{S.str(company)} AS banco, D.`CodigoEquipto` AS maquina, D.`CodigoContrato` AS contrato, " \
        "IF(#{rental_sql}, 1, 0) AS locacao, C.`CodigoCliente` AS cliente FROM #{bank}.detalhecontrato D " \
        "JOIN #{bank}.contrato C ON C.`CodigoContrato` = D.`CodigoContrato` WHERE #{active_item}"
    end
    return ' LEFT JOIN (SELECT NULL AS maquina, NULL AS contrato_ref, NULL AS cliente) MC ON 1 = 0' if selects.empty?

    " LEFT JOIN (SELECT U.maquina, MAX(CONCAT(U.locacao, LPAD(U.contrato, 10, '0'), ':', U.banco)) AS contrato_ref, " \
      "SUBSTRING_INDEX(GROUP_CONCAT(CASE WHEN U.banco = #{S.str(base)} THEN U.cliente END ORDER BY U.contrato DESC), ',', 1) AS cliente " \
      "FROM (#{selects.join(' UNION ALL ')}) U GROUP BY U.maquina) MC ON MC.maquina = O.`Seq`"
  end

  def locked
    list = @settings.locked_statuses
    (list.empty? ? %w[FECHADA CANCELADA PERDIDA] : list).map { |item| S.str(item) }.join(', ')
  end
end
