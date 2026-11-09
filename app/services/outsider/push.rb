# OUTSIDER: aviso novo no navegador e no celular (push), no lugar do push do Chatwoot no navegador.
#   Foto de quem mandou, "Nome · de onde veio" (caixa do WhatsApp, chat ou canal do Teams) e o texto; várias mensagens
#   da mesma conversa viram um aviso só; botões "Abrir conversa" e "Marcar como lida" (public/outsider-push-sw.js).
#   Regras: app/services/outsider/push/customer_message.rb, teams_message.rb e chatwoot_notice.rb.
#   Desligar tudo e voltar ao push do Chatwoot: OUTSIDER_PUSH=off no .env (nos testes automáticos já vem desligado, para
#   os testes do Chatwoot continuarem valendo; os do aviso novo ligam com OUTSIDER_PUSH=on).
module Outsider::Push
  READ_PURPOSE = 'outsider_push_read'.freeze
  READ_EXPIRES = 7.days
  ICONS = {
    'whatsapp' => '/outsider/push/whatsapp.png', 'teams' => '/outsider/push/teams.png',
    'chatwoot' => '/outsider/push/chatwoot.png'
  }.freeze
  BADGES = {
    'whatsapp' => '/outsider/push/whatsapp-badge.png', 'teams' => '/outsider/push/teams-badge.png',
    'chatwoot' => '/outsider/push/chatwoot-badge.png'
  }.freeze

  module_function

  def enabled?
    ENV.fetch('OUTSIDER_PUSH', Rails.env.test? ? 'off' : 'on').to_s.downcase != 'off'
  end

  def site
    ENV.fetch('FRONTEND_URL', '').to_s.chomp('/')
  end

  def verifier
    ActiveSupport::MessageVerifier.new(Rails.application.key_generator.generate_key(READ_PURPOSE), url_safe: true, digest: 'SHA256',
                                                                                                   serializer: JSON)
  end

  # "Marcar como lida" no próprio aviso: o service worker não tem a sessão da pessoa, então leva um token assinado
  def read_token(data)
    verifier.generate(data, expires_in: READ_EXPIRES, purpose: READ_PURPOSE)
  end

  def read_data(token)
    verifier.verified(token.to_s, purpose: READ_PURPOSE)
  end

  # o aviso no formato que o public/outsider-push-sw.js entende
  # test: aviso do botão "Enviar push de teste", que aparece mesmo com a pessoa olhando a tela de notificações
  def payload(kind:, title:, body:, url:, tag:, icon: nil, read: nil, test: false)
    path = url.to_s.sub(site, '')
    {
      outsider: 1, kind: kind, title: title.to_s.truncate(90), body: body.to_s.squish.truncate(180),
      icon: icon.presence || "#{site}#{ICONS.fetch(kind, ICONS['chatwoot'])}", badge: "#{site}#{BADGES.fetch(kind, BADGES['chatwoot'])}",
      tag: tag, url: url, path: path, read: read, more: '%<n>s mensagens novas', open_label: 'Abrir conversa',
      read_label: 'Marcar como lida', test: test
    }
  end
end
