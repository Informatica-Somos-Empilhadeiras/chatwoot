# OUTSIDER: as listas do formulário da OS feita no chat, só leitura: tipos de atendimento e técnicos (os mesmos do quadro
# de OS, Outsider::Erp::Lists), classes da OS (tabela classeos da unidade), se a unidade exige máquina, quem vai gravar
# (o código de funcionário do ERP da pessoa) e as máquinas do cliente: as do cadastro dele, as que estão nos contratos
# ativos dele e, na busca, qualquer máquina da unidade (como desmarcar "só máquinas do cliente" no desktop). O último
# horímetro de cada máquina vem da OS mais recente dela.
class Outsider::Erp::Orders::Options
  S = Outsider::Erp::Sql
  MACHINES = 80
  SEARCH = 30
  CLASSES = [{ codigo: 1, descricao: '1' }, { codigo: 2, descricao: '2' }].freeze

  def initialize(account, user)
    @account = account
    @user = user
    @settings = Outsider::Erp::Settings.new(account)
    @client = Outsider::Erp::Client.new(@settings)
  end

  def form(company)
    check!(company)
    {
      attendance_types: optional { lists.attendance_types }, technicians: optional { lists.technicians },
      classes: classes(company), machine_required: machine_required?(company), erp_user: erp_user(company),
      companies: @settings.order_companies
    }
  end

  # máquinas do cliente (cadastro dele + contratos ativos); com q, busca em todas as máquinas da unidade
  def machines(company, customer, query = nil)
    check!(company)
    customer = Integer(customer.to_s, exception: false).to_i
    text = query.to_s.squish.first(40)
    sql = text.present? ? search_sql(company, customer, text) : customer_sql(company, customer, with_contracts: true)
    run(sql)
  rescue Outsider::Erp::Client::Error
    raise if text.present?

    run(customer_sql(company, customer, with_contracts: false))
  end

  private

  def check!(company)
    raise ArgumentError, 'company' unless @settings.order_company?(company)
  end

  def lists = @lists ||= Outsider::Erp::Lists.new(@account)

  def bank(company) = S.ident(company)

  def fields(company, customer)
    'E.`Seq` AS codigo, E.`Descricao` AS descricao, E.`Modelo` AS modelo, E.`NSerie` AS serie, E.`NPatrimonio` AS patrimonio, ' \
      "CASE WHEN E.`CodClientes` = #{S.int(customer)} THEN 1 ELSE 0 END AS do_cliente, " \
      "(SELECT O.`Horimetro` FROM #{bank(company)}.os O WHERE O.`CodigoMaquina` = E.`Seq` AND IFNULL(O.`Horimetro`, '') <> '' " \
      'ORDER BY O.`CodigoOS` DESC LIMIT 1) AS horimetro'
  end

  def customer_sql(company, customer, with_contracts:)
    contracts = if with_contracts
                  " OR E.`Seq` IN (SELECT D.`CodigoEquipto` FROM #{bank(company)}.detalhecontrato D JOIN #{bank(company)}.contrato C " \
                    "ON C.`CodigoContrato` = D.`CodigoContrato` WHERE C.`CodigoCliente` = #{S.int(customer)} AND C.`Status` = 'ATIVO')"
                end
    "SELECT #{fields(company, customer)} FROM #{bank(company)}.equipamentos E WHERE (E.`CodClientes` = #{S.int(customer)}#{contracts}) " \
      "ORDER BY do_cliente DESC, E.`Descricao`, E.`Seq` LIMIT #{MACHINES}"
  end

  def search_sql(company, customer, text)
    like = S.str("%#{text.gsub(/[\\%_]/) { |char| "\\#{char}" }}%")
    number = Integer(text, exception: false)
    exact = number ? " OR E.`Seq` = #{S.int(number)}" : ''
    "SELECT #{fields(company, customer)} FROM #{bank(company)}.equipamentos E WHERE (E.`NSerie` LIKE #{like} OR E.`NPatrimonio` LIKE #{like} " \
      "OR E.`Descricao` LIKE #{like} OR E.`Modelo` LIKE #{like}#{exact}) ORDER BY do_cliente DESC, E.`Seq` DESC LIMIT #{SEARCH}"
  end

  # classes da OS da unidade (classeos): o código e o primeiro texto da linha; sem a tabela, 1 e 2 como no desktop
  def classes(company)
    rows = run("SELECT * FROM #{bank(company)}.classeos LIMIT 20")
    list = rows.filter_map do |row|
      code = row.values.find { |value| value.is_a?(Integer) }
      label = row.values.find { |value| value.is_a?(String) && value.strip.present? && value.strip !~ /\A\d+\z/ }
      { codigo: code, descricao: [code, label&.squish].compact.join(' - ') } if code&.positive?
    end
    list.presence || CLASSES
  rescue Outsider::Erp::Client::Error
    CLASSES
  end

  def machine_required?(company)
    run("SELECT IFNULL(MAX(`ckObrigaPreencherMaquinaOS`), 1) AS obriga FROM #{bank(company)}.empresa").first.to_h['obriga'].to_i == 1
  rescue Outsider::Erp::Client::Error
    true
  end

  # o código de funcionário do ERP ligado à pessoa nas Configurações (só ele assina a OS) e o nome dele no ERP
  def erp_user(company)
    code = @settings.data['user_erp_ids'].to_h[@user.id.to_s].to_i
    return unless code.positive?

    { codigo: code, nome: Outsider::Erp::SellerName.new(@account, client: @client).for_code(company, code) }
  end

  def run(sql)
    Array.wrap(@client.query_execute(sql)).grep(Hash).map { |row| row.transform_values { |value| value.is_a?(String) ? value.strip : value } }
  end

  def optional
    yield
  rescue Outsider::Erp::Client::Error
    []
  end
end
