# OUTSIDER: reações das mensagens da área Teams (👍 ❤️ 😂 ...), as mesmas do Teams.
#   Entrada: Outsider::Teams::Graph::Inbound guarda as reações que vêm com a mensagem (o Teams avisa como mensagem
#   alterada quando alguém reage). Saída: toggle! reage ou tira a reação em nome da pessoa (setReaction/unsetReaction).
# As reações antigas do Teams vêm com nome (like, heart...): aqui viram o emoji.
class Outsider::Teams::Graph::Reactions
  LEGACY = { 'like' => '👍', 'heart' => '❤️', 'laugh' => '😆', 'surprised' => '😮', 'sad' => '😢', 'angry' => '😡' }.freeze
  MAX = 100

  def self.emoji(type)
    LEGACY.fetch(type.to_s, type.to_s)
  end

  # reações do Graph -> [{ type, user_id, name }]; o nome vem da lista de pessoas do chat/canal quando o Graph não manda
  def self.parse(list, thread)
    names = Array(thread.members).to_h { |member| [member['id'], member['name']] }
    Array(list).filter_map do |reaction|
      next if reaction['reactionType'].to_s == 'custom'

      user_id = reaction.dig('user', 'user', 'id').to_s
      name = reaction.dig('user', 'user', 'displayName').presence || names[user_id]
      { 'type' => emoji(reaction['reactionType']), 'user_id' => user_id.presence, 'name' => name }.compact
    end.first(MAX)
  end

  def initialize(link, message)
    @link = link
    @message = message
    @thread = message.thread
  end

  # reage (on) ou tira a reação (off) com o emoji; devolve a lista nova
  def apply!(emoji, on:)
    action = on ? 'setReaction' : 'unsetReaction'
    Outsider::Teams::Graph::Client.new(@link).post("#{message_path}/#{action}", { reactionType: emoji })
    mine = ->(item) { item['user_id'] == @link.ms_user_id && item['type'] == emoji }
    list = Array(@message.reactions).reject(&mine)
    list << { 'type' => emoji, 'user_id' => @link.ms_user_id, 'name' => @link.display_name } if on
    @message.update!(reactions: list.first(MAX))
    Outsider::Teams::Graph::Notifier.message(@link, @thread, @message, action: 'updated')
    @message.reactions
  end

  private

  def enc(value)
    Outsider::Teams::Graph::Client.enc(value)
  end

  def message_path
    return "/chats/#{enc(@thread.chat_id)}/messages/#{enc(@message.graph_id)}" if @thread.kind == 'chat'

    base = "/teams/#{enc(@thread.team_id)}/channels/#{enc(@thread.channel_id)}/messages"
    return "#{base}/#{enc(@message.reply_to_graph_id)}/replies/#{enc(@message.graph_id)}" if @message.reply_to_graph_id.present?

    "#{base}/#{enc(@message.graph_id)}"
  end
end
