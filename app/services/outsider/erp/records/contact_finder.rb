# OUTSIDER: qual contato do chat está ligado a cada cliente do ERP (Outsider::Erp::ContactLink) e a conversa mais recente
# dele, para o "Abrir no chat" das listas e do detalhe. Uma consulta para todos os clientes da página. Um cliente do ERP
# pode estar ligado a vários contatos (comprador, financeiro, gerente...): for_client devolve todos, para a tela escolher.
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

  # o detalhe: o contato com a conversa mais recente (contact_id, conversation_id) e todos os ligados ao cliente (contacts)
  def for_client(company, code)
    pair = [company.to_s, code.to_i]
    return { 'contacts' => [] } if valid([pair]).empty?

    contacts = matching_contacts([pair]).select { |item| linked?(item, pair) }
    conversations = latest_conversations(contacts.map(&:id))
    rows = contacts.map { |item| contact_row(item, conversations[item.id]) }.sort_by { |row| -row['conversation_id'].to_i }
    first = rows.first || {}
    { 'contact_id' => first['id'], 'conversation_id' => first['conversation_id'], 'contacts' => rows }.compact
  end

  private

  def contact_row(contact, conversation_id)
    { 'id' => contact.id, 'name' => contact.name, 'phone' => contact.phone_number, 'email' => contact.email,
      'conversation_id' => conversation_id }
  end

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
