# OUTSIDER: push "E-mail novo" dos aplicativos (Outlook e Gmail), com o remetente e o assunto. Desliga em
# Minhas notificações (chave 'apps_mail'); "Esconder o texto" mostra só o remetente.
class Outsider::Apps::MailPush
  APPS = { 'microsoft' => %w[Outlook outlook], 'google' => %w[Gmail gmail] }.freeze

  def initialize(user, account, provider:, item:)
    @user = user
    @account = account
    @provider = provider
    @item = item
  end

  def perform
    return 0 if @user.nil? || !Outsider::PushSetting.wants?(@user, @account, 'apps_mail')

    name, path = APPS.fetch(@provider)
    sender = @item.dig(:from, :name).presence || @item.dig(:from, :email).presence || name
    text = if Outsider::PushSetting.wants?(@user, @account,
                                           'hide_content')
             'E-mail novo'
           else
             [@item[:subject], @item[:preview]].compact_blank.join(' · ')
           end
    url = "#{Outsider::Push.site}/app/accounts/#{@account.id}/apps/#{@provider}/#{path}?message=#{ERB::Util.url_encode(@item[:id])}"
    payload = Outsider::Push.payload(kind: 'mail', title: "#{sender} · #{name}", body: text.presence || 'E-mail novo', url: url,
                                     tag: "mail-#{@provider}", person: sender, open_label: 'Abrir e-mail')
    Outsider::Push::Sender.new(@user).deliver(payload)
  end
end
