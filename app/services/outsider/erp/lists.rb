# OUTSIDER: listas de apoio do Kanban do ERP (situações, técnicos, tipos de atendimento) para os seletores da tela de
# edição da OS. São curtas e mudam pouco, então ficam em cache por conta por alguns minutos (não pesa no ERP). Só leitura.
class Outsider::Erp::Lists
  CACHE = 10.minutes

  def initialize(account)
    @account = account
    @settings = Outsider::Erp::Settings.new(account)
  end

  def statuses
    cached('statuses') { client.kanban_list('ListaStatusOS').filter_map { |row| row['Descricao'].presence }.uniq }
  end

  def technicians
    cached('technicians') do
      client.kanban_list('ListaTecnicos').filter_map { |row| { codigo: row['Codigo'], nome: row['Nome'].to_s } if row['Codigo'] }
    end
  end

  def attendance_types
    cached('attendance') { client.kanban_list('ListaTipoAtendimento').filter_map { |row| row['TipoAtendimento'].presence }.uniq }
  end

  private

  def client = @client ||= Outsider::Erp::Client.new(@settings)

  def cached(name, &)
    Rails.cache.fetch("outsider_erp:lists:#{@account.id}:#{name}", expires_in: CACHE, &)
  end
end
