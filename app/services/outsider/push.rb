# OUTSIDER: aviso novo no navegador e no celular (push), no lugar do push do Chatwoot no navegador.
#   Foto de quem mandou, "Nome · de onde veio" (caixa do WhatsApp, chat ou canal do Teams) e o texto; várias mensagens
#   da mesma conversa viram um aviso só; botões "Abrir conversa" e "Marcar como lida" (public/outsider-push-sw.js).
#   Visual do Teams: foto redonda (ou as iniciais numa cor) com o símbolo do canal no canto, desenhada no próprio
#   service worker, e "Envie uma resposta rápida" dentro do aviso (Outsider::PushReplyController).
#   Regras: app/services/outsider/push/customer_message.rb, teams_message.rb e chatwoot_notice.rb.
#   Desligar tudo e voltar ao push do Chatwoot: OUTSIDER_PUSH=off no .env (nos testes automáticos já vem desligado, para
#   os testes do Chatwoot continuarem valendo; os do aviso novo ligam com OUTSIDER_PUSH=on).
module Outsider::Push
  READ_PURPOSE = 'outsider_push_read'.freeze
  REPLY_PURPOSE = 'outsider_push_reply'.freeze
  READ_EXPIRES = 7.days
  ICONS = {
    'whatsapp' => '/outsider/push/whatsapp.png', 'teams' => '/outsider/push/teams.png',
    'chatwoot' => '/outsider/push/chatwoot.png', 'phone' => '/outsider/push/phone.png'
  }.freeze
  BADGES = {
    'whatsapp' => '/outsider/push/whatsapp-badge.png', 'teams' => '/outsider/push/teams-badge.png',
    'chatwoot' => '/outsider/push/chatwoot-badge.png', 'phone' => '/outsider/push/phone-badge.png'
  }.freeze

  module_function

  def enabled?
    ENV.fetch('OUTSIDER_PUSH', Rails.env.test? ? 'off' : 'on').to_s.downcase != 'off'
  end

  def site
    ENV.fetch('FRONTEND_URL', '').to_s.chomp('/')
  end

  def verifier(purpose = READ_PURPOSE)
    ActiveSupport::MessageVerifier.new(Rails.application.key_generator.generate_key(purpose), url_safe: true, digest: 'SHA256',
                                                                                              serializer: JSON)
  end

  # "Marcar como lida" no próprio aviso: o service worker não tem a sessão da pessoa, então leva um token assinado
  def read_token(data)
    verifier.generate(data, expires_in: READ_EXPIRES, purpose: READ_PURPOSE)
  end

  def read_data(token)
    verifier.verified(token.to_s, purpose: READ_PURPOSE)
  end

  # "Envie uma resposta rápida": outro token (o de "marcar como lida" não serve para mandar mensagem)
  def reply_token(data)
    verifier(REPLY_PURPOSE).generate(data, expires_in: READ_EXPIRES, purpose: REPLY_PURPOSE)
  end

  def reply_data(token)
    verifier(REPLY_PURPOSE).verified(token.to_s, purpose: REPLY_PURPOSE)
  end

  # o aviso no formato que o public/outsider-push-sw.js entende
  # test: aviso do botão "Enviar push de teste", que aparece mesmo com a pessoa olhando a tela de notificações
  # person: nome de quem mandou (as iniciais da foto redonda quando não tem foto); photo: foto dela
  # reply: token de resposta rápida (sem ele, o aviso não tem a caixa de resposta)
  def payload(kind:, title:, body:, url:, tag:, **extra)
    path = url.to_s.sub(site, '')
    {
      outsider: 1, kind: kind, title: title.to_s.truncate(90), body: body.to_s.squish.truncate(180),
      icon: "#{site}#{ICONS.fetch(kind, ICONS['chatwoot'])}", badge: "#{site}#{BADGES.fetch(kind, BADGES['chatwoot'])}",
      person: extra[:person].to_s.first(60).presence, photo: absolute(extra[:photo] || extra[:icon]),
      tag: tag, url: url, path: path, read: extra[:read], reply: extra[:reply], more: '%<n>s mensagens novas',
      open_label: extra[:open_label] || 'Abrir conversa', read_label: 'Marcar como lida', reply_label: 'Responder',
      reply_placeholder: 'Envie uma resposta rápida', test: extra[:test] || false
    }.merge(extra.slice(:call_label, :number))
  end

  def absolute(url)
    return nil if url.blank?

    url.to_s.start_with?('/') ? "#{site}#{url}" : url.to_s
  end
end
