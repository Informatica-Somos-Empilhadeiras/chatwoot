# OUTSIDER: o observador do Gmail de uma pessoa (Outsider::Apps::Google::WatchJob, a cada 5 minutos). O Google não avisa
# o Chatwoot sozinho sem um serviço pago a mais (Pub/Sub), então o Chatwoot pergunta: "o que mudou na Caixa de entrada
# desde a última vez?" (histórico do Gmail, um pedido pequeno por pessoa). Não grava e-mail: guarda só o número do ponto
# do histórico (history_id). E-mail novo na Principal vira aviso ao vivo na tela e push "E-mail novo" (no máximo 5 por
# vez); propaganda (Promoções, Social...) e o que a própria pessoa mandou não avisam.
class Outsider::Apps::Google::Watcher
  MAX_NOTICES = 5
  MAX_PAGES = 3

  def initialize(link)
    @link = link
    @client = Outsider::Apps::Google::Client.new(link)
  end

  def perform
    return start! if @link.history_id.blank?

    changed, added, latest = history
    save!(latest)
    return unless changed

    mail = Outsider::Apps::Google::Mail.new(@link)
    mail.forget_unread
    unread = mail.unread_count
    items = fresh(mail, added)
    return broadcast(unread: unread, action: 'unread') if items.empty?

    items.each do |item|
      broadcast(item: item, unread: unread, action: 'created')
      Outsider::Apps::MailPush.new(@link.user, @link.account, provider: 'google', item: item).perform
    end
  rescue Outsider::Apps::Google::Client::Error => e
    raise unless e.status == 404 && !e.is_a?(Outsider::Apps::Google::Client::Reconnect)

    start! # o ponto do histórico ficou velho demais (o Google guarda cerca de uma semana): recomeça de agora
  end

  # o ponto de partida: daqui para frente (o que já estava na caixa não avisa)
  def start!
    profile = @client.get("#{Outsider::Apps::Google::Client::GMAIL}/profile")
    save!(profile['historyId'])
  end

  private

  # [mudou algo na Caixa de entrada?, mensagens que entraram, ponto mais novo]
  def history
    added = []
    changed = false
    latest = nil
    query = { startHistoryId: @link.history_id, labelId: 'INBOX', maxResults: 100,
              historyTypes: %w[messageAdded labelAdded labelRemoved] }
    MAX_PAGES.times do
      data = @client.get("#{Outsider::Apps::Google::Client::GMAIL}/history", query: query)
      latest = data['historyId'].presence || latest
      Array(data['history']).each do |entry|
        changed = true
        Array(entry['messagesAdded']).each { |item| added << item['message'] if item['message'].is_a?(Hash) }
      end
      break if data['nextPageToken'].blank?

      query[:pageToken] = data['nextPageToken']
    end
    [changed, added, latest]
  end

  # só o que entrou na Principal e continua não lido agora (os detalhes vêm num pedido só)
  def fresh(mail, added)
    ids = added.select { |message| Outsider::Apps::Google::Mail.primary?(message['labelIds']) }.pluck('id').uniq.last(MAX_NOTICES)
    return [] if ids.empty?

    mail.metadata(ids).compact.select { |item| Outsider::Apps::Google::Mail.primary?(item['labelIds']) }
        .map { |item| mail.summary(item) }.sort_by { |item| item[:date].to_s }
  end

  def save!(history_id)
    attributes = { checked_at: Time.current, updated_at: Time.current }
    attributes[:history_id] = history_id.to_s if history_id.present?
    @link.update_columns(attributes) # rubocop:disable Rails/SkipsModelValidations
  end

  def broadcast(data)
    Outsider::Apps::Notifier.broadcast(@link.user, @link.account_id, { provider: 'google', app: 'mail' }.merge(data))
  end
end
