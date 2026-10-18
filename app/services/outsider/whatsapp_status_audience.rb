# OUTSIDER: quem pode receber um status: os contatos do WhatsApp da caixa (sem grupos e
# bloqueados), com o DDD de cada um, para escolher por lista, busca, estado e região.
# O estado e a região de cada DDD ficam no navegador (ver whatsappStatus/areas.js).
class Outsider::WhatsappStatusAudience
  PER_PAGE = 50
  BRAZIL = /\A55(?<ddd>[1-9]\d)\d{8,9}\z/
  FOREIGN = 'foreign'.freeze
  UNKNOWN = 'unknown'.freeze

  def self.jid_for(identifier, phone_number)
    return identifier if identifier.to_s.match?(Outsider::WhatsappStatusRecord::PERSON_JID)
    return if identifier.to_s.end_with?('@g.us')

    digits = phone_number.to_s.delete('^0-9')
    "#{digits}@s.whatsapp.net" if digits.present?
  end

  def initialize(inbox, api)
    @inbox = inbox
    @api = api
  end

  def jids
    entries.pluck(:jid)
  end

  # { count, areas: { '62' => 120, 'foreign' => 3, 'unknown' => 8 } }
  def summary
    { count: entries.size, areas: entries.group_by { |entry| entry[:area] }.transform_values(&:size) }
  end

  def search(query:, areas:, page:)
    found = filter(query, areas)
    contacts = found.slice((page - 1) * PER_PAGE, PER_PAGE) || []
    avatars = Contact.with_attached_avatar.where(id: contacts.pluck(:id)).index_by(&:id)
    {
      total: found.size, page: page, per_page: PER_PAGE,
      contacts: contacts.map do |entry|
        entry.slice(:id, :name, :phone, :area).merge(avatar_url: avatars[entry[:id]]&.avatar_url.presence)
      end
    }
  end

  def ids(query:, areas:)
    filter(query, areas).pluck(:id)
  end

  def jids_for(contact_ids)
    wanted = contact_ids.to_set(&:to_i)
    entries.select { |entry| wanted.include?(entry[:id]) }.pluck(:jid)
  end

  # Números digitados. A Evolution diz o jid certo de cada um: no Brasil, muitos números
  # antigos estão no WhatsApp sem o 9, e um status mandado para o jid errado não chega.
  def resolve_numbers(numbers)
    digits = numbers.map { |number| national_to_full(number.to_s.delete('^0-9')) }.select { |number| number.length >= 12 }.uniq
    return [] if digits.empty?

    found = @api.whatsapp_numbers(digits).select { |result| result['exists'] }
    missing = digits - found.pluck('number')
    raise Outsider::EvolutionApi::Error.new('numbers_not_found', missing.join(', ')) if missing.any?

    found.pluck('jid').uniq
  end

  private

  # sem o 55: 10 ou 11 dígitos são DDD + número
  def national_to_full(digits)
    digits.length.between?(10, 11) ? "55#{digits}" : digits
  end

  def filter(query, areas)
    words = I18n.transliterate(query.to_s).downcase.split
    digits = query.to_s.delete('^0-9')
    entries.select do |entry|
      (areas.empty? || areas.include?(entry[:area])) && matches?(entry, words, digits)
    end
  end

  # todas as palavras no nome ou no número, ou um pedaço do número com pontos e traços
  def matches?(entry, words, digits)
    words.all? { |word| entry[:search].include?(word) } || (digits.length >= 3 && entry[:phone].to_s.include?(digits))
  end

  def entries
    @entries ||= @inbox.contacts.where(blocked: false).pluck(:id, :name, :identifier, :phone_number)
                       .filter_map { |row| entry(*row) }.uniq { |entry| entry[:jid] }
                       .sort_by { |entry| [entry[:name].present? ? 0 : 1, entry[:search]] }
  end

  def entry(id, name, identifier, phone_number)
    jid = self.class.jid_for(identifier, phone_number)
    return if jid.nil?

    digits = phone_number.to_s.delete('^0-9').presence || (jid.split('@').first if jid.end_with?('@s.whatsapp.net'))
    phone = "+#{digits}" if digits
    { id: id, name: name.presence, phone: phone, area: area(digits), jid: jid,
      search: "#{I18n.transliterate(name.to_s).downcase} #{digits}" }
  end

  def area(digits)
    return UNKNOWN if digits.blank?

    digits.match(BRAZIL)&.[](:ddd) || FOREIGN
  end
end
