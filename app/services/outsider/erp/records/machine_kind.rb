# OUTSIDER: lista de máquinas do ERP (tabela equipamentos): a frota da Somos e as máquinas dos clientes, só para ver. A
# situação (EM OS, LOCADA, EM CONTRATO, DISPONÍVEL, DO CLIENTE) e o cliente de agora (o do contrato, quando locada) saem
# dos contratos e das OS (Outsider::Erp::Rentals::MachineStatus).
# Só as unidades com cadastro próprio (Rentals::Fleet).
# Sem pessoa; a busca olha série, patrimônio, descrição e modelo. A aba "Frota própria" usa o lugar do "atrasada" das
# outras listas (late_sql), que as contagens já sabem contar.
class Outsider::Erp::Records::MachineKind < Outsider::Erp::Records::Kind
  def table = 'equipamentos'
  def person = :pessoa_codigo
  def required = %i[numero cliente_codigo]
  def date_keys = %i[data ultima_os]
  def search_keys = %i[serie patrimonio descricao modelo]
  def digit_keys = %i[serie patrimonio]
  def extra_sorts = { 'serie' => 'X.serie', 'ultima_os' => 'X.ultima_os' }
  def late_sql = '(X.propria = 1)'

  # status: Seq só para a coluna existir; a situação vem de status_sql
  def columns
    {
      numero: %w[Seq], data: %w[Cadastro], status: %w[Seq], total: %w[VrLocacao], cliente_codigo: %w[CodClientes],
      pessoa_codigo: [], descricao: %w[Descricao], modelo: %w[Modelo], serie: %w[NSerie], patrimonio: %w[NPatrimonio],
      tipo: %w[Tipo], capacidade: %w[CapacidadeCarga], ano: %w[AnoFabricacao Ano]
    }
  end

  def views
    status = ->(key, value) { { key: key, status_in: [value] } }
    [{ key: 'all' }, { key: 'own', late: true }, status.call('rented', 'LOCADA'), status.call('contract', 'EM CONTRATO'),
     status.call('available', 'DISPONÍVEL'), status.call('in_order', 'EM OS'), status.call('client', 'DO CLIENTE')]
  end

  def status_sql(_picked) = machine_status.status
  def client_sql(_picked) = machine_status.client
  def joins(company, schema) = machine_status.joins(company, schema)
  def computed(_company, _schema) = machine_status.fields
  def companies(list) = list & fleet.bases

  private

  def fleet = @fleet ||= Outsider::Erp::Rentals::Fleet.new(@settings.account, client: @client)
  def machine_status = @machine_status ||= Outsider::Erp::Rentals::MachineStatus.new(@settings, fleet)
end
