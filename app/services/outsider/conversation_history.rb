# OUTSIDER: busca dentro de uma conversa e navegação por data.
#
# Busca sem diferença de acento nem de maiúsculas, palavra por palavra (todas as palavras
# precisam aparecer, em qualquer ordem). Cada palavra vira uma expressão regular com as
# letras acentuadas possíveis ("acao" -> "[aá...]..."), que o índice trigram de
# messages.content (pg_trgm) consegue usar junto com o índice da conversa, então mesmo
# conversas e bancos enormes não são lidos inteiros.
# As ordenações usam "+ 0"/"+ interval" de propósito: impedem o Postgres de varrer o
# índice da tabela toda (todas as contas) atrás das poucas linhas desta conversa.
class Outsider::ConversationHistory
  PER_PAGE = 30
  MAX_COUNT = 1000
  MIN_TERM_LENGTH = 2
  MAX_TERMS = 8
  CONTENT_LIMIT = 1500
  ACCENTS = 'áàâãäåéèêëíìîïóòôõöúùûüýÿçñÁÀÂÃÄÅÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÝÇÑ'.freeze
  PLAIN = 'aaaaaaeeeeiiiiooooouuuuyycnaaaaaaeeeeiiiiooooouuuuycn'.freeze
  # letra sem acento -> todas as formas dela ("a" -> "aáàâãäåÁÀÂÃÄÅ")
  VARIANTS = ACCENTS.each_char.with_index.each_with_object({}) do |(accented, index), variants|
    plain = PLAIN[index]
    variants[plain] = (variants[plain] || plain.dup) << accented
  end.transform_values(&:freeze).freeze
  # content_attributes guarda {"deleted": true} (às vezes como texto JSON dentro do JSON)
  DELETED_PATTERN = 'deleted\\\\?"\\s*:\\s*true'.freeze
  GROUP_HEADER = /\A\*\*[^*\n]+?:?\*\*:?\s*/

  pattr_initialize :conversation

  def search(query, since: nil, before: nil, before_id: nil)
    terms = terms_of(query)
    return { total: 0, total_more: false, has_more: false, payload: [] } if terms.empty?

    scope = matching(terms, since, before)
    page = scope.where(before_id.present? ? ['messages.id < ?', before_id.to_i] : nil)
                .reorder(Arel.sql('messages.id + 0 DESC')).limit(PER_PAGE + 1)
                .includes(:sender, :attachments).to_a
    has_more = page.size > PER_PAGE
    total = total_for(scope, page.size, has_more) if before_id.blank?

    {
      total: total && [total, MAX_COUNT].min,
      total_more: total.to_i > MAX_COUNT,
      has_more: has_more,
      payload: page.first(PER_PAGE).map { |message| serialize(message, terms) }
    }
  end

  # { 'AAAA-MM-DD' => quantidade } no fuso de quem está olhando, para o calendário
  def days(time_zone)
    zone = ActiveSupport::TimeZone[time_zone.to_s] || Time.zone
    local_day = "(messages.created_at AT TIME ZONE 'UTC' AT TIME ZONE #{connection.quote(zone.tzinfo.name)})::date"
    real_messages.reorder(nil).group(Arel.sql(local_day)).count.transform_keys(&:to_s)
  end

  # primeira mensagem a partir do horário pedido; se não houver depois, a última antes dele
  def locate(at)
    time = Time.zone.at(at.to_i)
    real_messages.where('messages.created_at >= ?', time)
                 .reorder(Arel.sql("messages.created_at + interval '0 second' ASC, messages.id + 0 ASC")).pick(:id) ||
      real_messages.reorder(Arel.sql("messages.created_at + interval '0 second' DESC, messages.id + 0 DESC")).pick(:id)
  end

  private

  def terms_of(query)
    normalize(query).split.select { |term| term.length >= MIN_TERM_LENGTH }.uniq.first(MAX_TERMS)
  end

  def normalize(text)
    text.to_s.tr(ACCENTS, PLAIN).downcase
  end

  def pattern_for(term)
    term.each_char.map do |char|
      if VARIANTS[char] then "[#{VARIANTS[char]}]"
      elsif char.match?(/[[:alnum:]]/) then char
      else
        "\\#{char}"
      end
    end.join
  end

  def real_messages
    conversation.messages.where.not(message_type: :activity)
  end

  def matching(terms, since, before)
    scope = real_messages.where.not(content: [nil, ''])
                         .where("COALESCE(messages.content_attributes::text, '') !~ ?", DELETED_PATTERN)
    terms.each { |term| scope = scope.where('messages.content ~* ?', pattern_for(term)) }
    scope = scope.where('messages.created_at >= ?', Time.zone.at(since.to_i)) if since.present?
    scope = scope.where('messages.created_at < ?', Time.zone.at(before.to_i)) if before.present?
    scope
  end

  # poucos resultados: a própria página já diz o total; muitos: conta até MAX_COUNT + 1
  def total_for(scope, page_size, has_more)
    return page_size unless has_more

    Message.unscoped.from(scope.reorder(nil).select(:id).limit(MAX_COUNT + 1), :messages).count
  end

  def serialize(message, terms)
    {
      id: message.id,
      created_at: message.created_at.to_i,
      message_type: message.message_type_before_type_cast,
      private: message.private,
      content: excerpt(message.content.to_s, terms),
      sender: { id: message.sender_id, type: message.sender_type, name: message.sender&.try(:name) },
      attachment_type: message.attachments.first&.file_type
    }
  end

  # mensagem longa: manda o pedaço onde a palavra aparece (e o "**Nome:**" dos grupos)
  def excerpt(text, terms)
    return text if text.length <= CONTENT_LIMIT

    folded = normalize(text)
    first = terms.filter_map { |term| folded.index(term) }.min.to_i
    start = [first - (CONTENT_LIMIT / 3), 0].max
    return text.first(CONTENT_LIMIT) if start.zero?

    "#{text[GROUP_HEADER]}…#{text[start, CONTENT_LIMIT]}"
  end

  def connection
    ActiveRecord::Base.connection
  end
end
