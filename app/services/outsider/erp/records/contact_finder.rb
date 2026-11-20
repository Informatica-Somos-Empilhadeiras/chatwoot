# OUTSIDER: qual contato do chat está ligado a cada cliente do ERP (Outsider::Erp::ContactLink) e a conversa mais recente
# dele, para o "Abrir no chat" das listas e do detalhe. Uma consulta para todos os clientes da página.
class Outsider::Erp::Records::ContactFinder
  KEY = Outsider::Erp::ContactLink::KEY

  def initialize(account)
    @account = account
  end

  # [[empresa, código], ...] => { [empresa, código] => { 'contact_id' =>, 'conversation_id' => } }
  def for_clients(pairs)
    pairs = valid(pairs)
    return {} if pairs.empty?

    contacts = matching_contacts(pairs)
    conversations = latest_conversations(contacts.map(&:id))
    pairs.each_with_object({}) do |pair, map|
      contact = contacts.find { |item| linked?(item, pair) }
      map[pair] = { 'contact_id' => contact.id, 'conversation_id' => conversations[contact.id] } if contact
    end
  end

  private

  def valid(pairs) = pairs.select { |company, code| company.present? && code.to_i.positive? }.uniq

  def matching_contacts(pairs)
    conditions = pairs.map { "additional_attributes -> '#{KEY}' @> ?::jsonb" }
    values = pairs.map { |company, code| [{ 'empresa' => company, 'codigo' => code.to_i }].to_json }
    @account.contacts.where(conditions.join(' OR '), *values).order(:id).limit(200).to_a
  end

  def latest_conversations(contact_ids)
    return {} if contact_ids.empty?

    @account.conversations.where(contact_id: contact_ids).group(:contact_id).maximum(:display_id)
  end

  def linked?(contact, pair)
    Outsider::Erp::ContactLink.new(contact).links.any? { |link| link['empresa'] == pair.first && link['codigo'].to_i == pair.last.to_i }
  end
end
