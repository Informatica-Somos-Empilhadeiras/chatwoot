# OUTSIDER: a cópia que a Evolution grava das mensagens do bot (ver Outsider::Bot::Echo) entra como
# mensagem do bot: sem remetente, com o texto e a marcação outsider_bot que o bot guardou. Se o bot já
# criou a mensagem porque a cópia demorou, devolve a que existe em vez de duplicar.
# Incluído no Messages::MessageBuilder pelo config/initializers/outsider_bot_echo.rb.
module Outsider::Bot::EchoBuilder
  def perform
    return super unless bot_echo

    existing = @conversation.messages.find_by(source_id: @params[:source_id])
    existing ? (@message = existing) : super
  end

  private

  # documento do bot: a conversa mostra o nome e o link do Nextcloud, sem guardar outra cópia do arquivo
  def process_attachments
    return if bot_echo && bot_echo.dig('attributes', 'kind') == 'document'

    super
  end

  def message_params
    params = super
    return params unless bot_echo

    params.merge(sender: nil, content: bot_echo['content'].presence || params[:content],
                 content_attributes: params[:content_attributes].to_h.merge('outsider_bot' => bot_echo['attributes']))
  end

  def bot_echo
    return @bot_echo if defined?(@bot_echo)

    @bot_echo = (Outsider::Bot::Echo.record(@conversation, @params[:source_id], wait: true) if @message_type.to_s == 'outgoing')
  end
end
