# OUTSIDER: chegou e-mail na Caixa de entrada do Outlook (aviso da Microsoft, assinatura kind 'mail'). Não grava nada:
# zera o número de não lidas do cache, avisa a tela da pessoa ao vivo (evento outsider.notice, kind 'apps') e manda o
# push "E-mail novo" se ela quiser (Minhas notificações > Aplicativos). Só lê assunto, remetente e o começo do texto.
class Outsider::Apps::Microsoft::MailNotice
  RESOURCE = %r{\AUsers/[^/]+/Messages/(?<id>[^/?]+)}i

  def initialize(link, resource)
    @link = link
    @resource = resource.to_s
  end

  def perform
    match = RESOURCE.match(@resource)
    return if match.nil?

    mail = Outsider::Apps::Microsoft::Mail.new(@link)
    mail.forget_unread
    path = "/me/messages/#{Outsider::Teams::Graph::Client.enc(match[:id])}?$select=#{Outsider::Apps::Microsoft::Mail::SUMMARY_FIELDS}"
    data = Outsider::Teams::Graph::Client.new(@link).get(path)
    return if data['isDraft'] == true || data['isRead'] == true

    item = mail.summary(data)
    Outsider::Apps::Notifier.broadcast(@link.user, @link.account_id, provider: 'microsoft', app: 'mail', action: 'created',
                                                                     item: item, unread: mail.unread_count)
    Outsider::Apps::MailPush.new(@link.user, @link.account, provider: 'microsoft', item: item).perform
  rescue Outsider::Teams::Graph::Client::Error => e
    Rails.logger.info("[outsider_apps] mail notice: #{e.message}")
  end
end
