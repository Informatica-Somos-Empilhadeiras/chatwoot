# OUTSIDER: acha o contato do Chatwoot de cada número (ou LID) que aparece nos status.
class Outsider::WhatsappStatusPeople
  def self.details(contact)
    { name: contact.name.presence || contact.phone_number, phone: contact.phone_number.presence,
      avatar_url: contact.avatar_url.presence, contact_id: contact.id }
  end

  def initialize(account, jids)
    jids = jids.uniq
    contacts = account.contacts.with_attached_avatar
    phones = jids.filter_map { |jid| Outsider::WhatsappStatusRecord.phone_from(jid) }
    @contacts = contacts.where(identifier: jids).or(contacts.where(phone_number: phones)).each_with_object({}) do |contact, by_jid|
      by_jid[contact.identifier] = contact if contact.identifier.present?
      by_jid["#{contact.phone_number.delete('^0-9')}@s.whatsapp.net"] = contact if contact.phone_number.present?
    end
  end

  def find(jids, push_name)
    jid = Outsider::WhatsappStatusRecord.preferred_jid(jids)
    contact = jids.filter_map { |candidate| @contacts[candidate] }.first
    return self.class.details(contact).merge(jid: jid) if contact

    phone = Outsider::WhatsappStatusRecord.phone_from(jid)
    # quando não acha o pushName, a Evolution usa o número do jid; aí vale mais o telefone
    name = push_name.presence unless push_name.to_s.match?(/\A\d+\z/)
    { jid: jid, name: name || phone || jid, phone: phone, avatar_url: nil, contact_id: nil }
  end
end
