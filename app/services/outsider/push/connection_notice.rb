# OUTSIDER: avisos (push) do vigia da Evolution (Outsider::EvolutionWatchdog) para quem atende na caixa e para os
# administradores da conta: o WhatsApp da caixa caiu, foi desconectado no celular (precisa do QR code) ou voltou.
# Sem o celular na mão, era só reparando que as mensagens pararam que alguém percebia.
class Outsider::Push::ConnectionNotice
  # 403: o WhatsApp recusa a conexão do número (o que o Baileys chama de "forbidden")
  BLOCKED_CODE = 403

  def initialize(inboxes)
    @inboxes = inboxes
  end

  def down(minutes)
    deliver('⚠️ WhatsApp fora do ar', "Sem conexão há #{minutes} min. O Chatwoot está tentando reconectar; o que for enviado agora pode não sair.")
  end

  def logged_out(code)
    if code == BLOCKED_CODE
      deliver('🚨 WhatsApp recusou a conexão',
              "O WhatsApp recusou a conexão deste número (código #{code}), o que costuma ser bloqueio. Abra o WhatsApp no celular para ver o aviso.")
    else
      deliver('🚨 WhatsApp desconectado', "O aparelho foi desconectado (código #{code}). É preciso ler o QR code de novo na Evolution.")
    end
  end

  def back(minutes)
    deliver('✅ WhatsApp voltou', "Ficou #{minutes} min fora do ar. Confira as mensagens que ficaram com falha.")
  end

  private

  def deliver(title, body)
    return 0 unless Outsider::Push.enabled?

    @inboxes.sum do |inbox|
      payload = Outsider::Push.payload(kind: 'whatsapp', title: "#{title} · #{inbox.name}", body: body, tag: "evolution-#{inbox.id}",
                                       url: "#{Outsider::Push.site}/app/accounts/#{inbox.account_id}/inbox/#{inbox.id}",
                                       open_label: 'Abrir caixa')
      recipients(inbox).sum { |user| Outsider::Push::Sender.new(user).deliver(payload) }
    end
  end

  def recipients(inbox)
    (inbox.members + inbox.account.administrators).uniq.select { |user| Outsider::PushSetting.wants?(user, inbox.account, 'chatwoot') }
  end
end
