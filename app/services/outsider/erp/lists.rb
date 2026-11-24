# OUTSIDER: listas de apoio do Kanban do ERP (situações, técnicos, tipos de atendimento) para os seletores da tela de
# edição da OS. São curtas e mudam pouco, então ficam em cache por conta por alguns minutos (não pesa no ERP). Só leitura.
class Outsider::Erp::Lists
  CACHE = 10.minutes
  # nomes que a lista ListaTipoAtendimento já usou para o tipo (muda entre versões do ERP)
  TYPE_KEYS = %w[TipoAtendimento tipoAtendimento tipoatendimento TIPOATENDIMENTO Descricao descricao Tipo tipo Nome nome].freeze

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

  # os tipos da lista do kanban mais os que as OS das unidades já usam (a lista do kanban muda de formato entre versões
  # do ERP; o banco garante que todo tipo em uso aparece). Falha de um lado não derruba o outro.
  def attendance_types
    cached('attendance:v2') do
      found = kanban_attendance_types + used_attendance_types
      found.uniq { |name| Outsider::Erp::Prints::Bindings.normalize_type(name) }.sort
    end
  end

  private

  def kanban_attendance_types
    client.kanban_list('ListaTipoAtendimento').filter_map { |row| type_name(row) }
  rescue Outsider::Erp::Client::Error
    []
  end

  def type_name(row)
    value = row.is_a?(Hash) ? hash_type(row) : row
    value.to_s.squish.presence
  end

  def hash_type(row)
    TYPE_KEYS.lazy.map { |key| row[key] }.find(&:present?) || row.values.find { |item| item.is_a?(String) && item.present? }
  end

  # SELECT DISTINCT do tipo nas OS de cada unidade das Configurações (só leitura, banco na frente)
  def used_attendance_types
    selects = @settings.companies.map do |company|
      "SELECT DISTINCT TRIM(O.`TipoAtendimento`) AS tipo FROM #{Outsider::Erp::Sql.ident(company)}.`os` O " \
        "WHERE O.`TipoAtendimento` IS NOT NULL AND TRIM(O.`TipoAtendimento`) <> ''"
    end
    return [] if selects.empty?

    client.query_execute("SELECT DISTINCT X.tipo FROM (#{selects.join(' UNION ')}) X LIMIT 200", read_timeout: 20)
          .grep(Hash).filter_map { |row| row['tipo'].to_s.squish.presence }
  rescue Outsider::Erp::Client::Error
    []
  end

  def client = @client ||= Outsider::Erp::Client.new(@settings)

  def cached(name, &)
    Rails.cache.fetch("outsider_erp:lists:#{@account.id}:#{name}", expires_in: CACHE, &)
  end
end
