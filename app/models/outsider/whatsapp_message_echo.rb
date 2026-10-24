# OUTSIDER: reações e edições do WhatsApp, que a Evolution manda ao Chatwoot como mensagem nova (Entrega 21).
#
# Reação: a Evolution cria uma mensagem só com o emoji, respondendo (in_reply_to) a mensagem reagida. Ela
# ganha content_attributes.outsider_reaction e a tela mostra o emoji no balão reagido, não como mensagem.
# Nos grupos, quem reagiu vem da Evolution logo depois (Outsider::WhatsappReactorJob).
#
# Edição: a Evolution cria "`Mensagem editada:` <texto>" respondendo a original. O texto novo vai para a
# original (marcada outsider_edited_at) e a mensagem da Evolution fica escondida (outsider_edit_of).
#
# Encaixado no Message por config/initializers/outsider_whatsapp_messages.rb.
module Outsider::WhatsappMessageEcho
  extend ActiveSupport::Concern

  REACTION = 'outsider_reaction'.freeze
  EDIT_OF = 'outsider_edit_of'.freeze
  EDITED_AT = 'outsider_edited_at'.freeze
  # texto que a edição feita no Chatwoot mandou ao WhatsApp (pode ter a assinatura de quem enviou na frente)
  EDIT_SENT = 'outsider_edit_sent'.freeze
  # "Mensagem editada" nas línguas da Evolution (LANGUAGE)
  EDIT_PATTERN = /\A\s*`(?:Mensagem editada|Edited Message|Mensaje editado):`\s*/
  EMOJI_PATTERN = /\A(?:\p{Extended_Pictographic}|\p{Emoji_Modifier}|\p{Regional_Indicator}|[\u200d\ufe0f\u20e3#*0-9])+\z/
  EMOJI_SYMBOL = /\p{Extended_Pictographic}|\p{Regional_Indicator}|\u20e3/
  # quem enviou, que a Evolution põe no começo das mensagens de grupo ("**+55 62 ... - Nome:**")
  SENDER_HEADER = /\A\*\*[^*\n]+:\*\*\s*/

  included do
    before_create :outsider_mark_echo
    after_create_commit :outsider_find_reactor
  end

  # um emoji só, como o WhatsApp manda na reação
  def self.emoji?(text)
    text.match?(EMOJI_PATTERN) && text.match?(EMOJI_SYMBOL) && text.grapheme_clusters.size == 1
  end

  private

  def outsider_mark_echo
    return unless outsider_evolution_echo?

    if content.match?(EDIT_PATTERN)
      outsider_apply_edit
    elsif attachments.empty? && Outsider::WhatsappMessageEcho.emoji?(content.strip)
      content_attributes[REACTION] = { 'emoji' => content.strip }
    end
  end

  def outsider_evolution_echo?
    (incoming? || outgoing?) && !private? && content.present? && content_attributes[:in_reply_to].present? &&
      source_id.to_s.start_with?('WAID:') && Outsider::EvolutionApi.evolution_inbox?(inbox)
  end

  def outsider_apply_edit
    target = conversation.messages.find_by(id: content_attributes[:in_reply_to])
    return unless target

    content_attributes[EDIT_OF] = target.id
    outsider_edit_target(target, content.sub(EDIT_PATTERN, '').strip)
  end

  # A edição feita aqui no Chatwoot volta da Evolution: a original já está com o texto novo
  def outsider_edit_target(target, text)
    header = target.content.to_s[SENDER_HEADER].to_s
    return if [target.content_attributes[EDIT_SENT].to_s.strip, target.content.to_s.delete_prefix(header)].include?(text)

    target.update!(content: "#{header}#{text}", content_attributes: target.content_attributes.merge(EDITED_AT => Time.current.iso8601))
  end

  def outsider_find_reactor
    return unless content_attributes[REACTION] && incoming? && conversation.contact&.identifier.to_s.end_with?('@g.us')

    Outsider::WhatsappReactorJob.set(wait: Outsider::WhatsappReactorJob::WAIT).perform_later(id)
  end
end
