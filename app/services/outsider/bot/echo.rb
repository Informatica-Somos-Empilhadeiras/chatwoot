# OUTSIDER: o que o bot manda direto pela Evolution (texto, lista e botões, para chegar ao cliente na
# ordem do fluxo). A Evolution grava cada mensagem de volta na conversa (source_id WAID:<id>) pela API do
# Chatwoot, em nome do dono do token dela. Sem este registro a cópia pareceria resposta de agente: o bot
# pararia, ela contaria como primeira resposta nos relatórios e tiraria a conversa de "esperando".
#
# O Outsider::Bot::Sender marca a conversa enquanto manda (sending) e guarda o id que a Evolution devolve
# (remember); o Outsider::Bot::EchoBuilder consulta aqui (record) e grava a cópia como mensagem do bot.
module Outsider::Bot::Echo
  KEY = 'OUTSIDER::BOT::ECHO::%<source_id>s'.freeze
  SENDING_KEY = 'OUTSIDER::BOT::SENDING::%<conversation_id>d'.freeze
  TTL = 1.hour
  SENDING_TTL = 30.seconds
  # a cópia pode chegar antes da resposta da Evolution com o id: espera o id até esse tempo
  WAIT = 3.seconds
  INTERVAL = 0.2

  module_function

  def sending(conversation)
    key = format(SENDING_KEY, conversation_id: conversation.id)
    Redis::Alfred.setex(key, 1, SENDING_TTL.to_i)
    yield
  ensure
    Redis::Alfred.delete(key) if key
  end

  def remember(source_id, content:, attributes:)
    Redis::Alfred.setex(format(KEY, source_id: source_id), { 'content' => content, 'attributes' => attributes }.to_json, TTL.to_i)
  end

  # { 'content', 'attributes' } que o bot guardou para a cópia, ou nil quando a mensagem não é do bot.
  # wait: enquanto o bot está mandando nessa conversa, espera o id chegar
  def record(conversation, source_id, wait: false)
    return unless source_id.to_s.start_with?('WAID:')

    found = read(source_id)
    return found if found || !wait || !Redis::Alfred.exists?(format(SENDING_KEY, conversation_id: conversation.id))

    deadline = WAIT.from_now
    while Time.current < deadline
      sleep INTERVAL
      found = read(source_id)
      return found if found
    end
    nil
  end

  def read(source_id)
    value = Redis::Alfred.get(format(KEY, source_id: source_id))
    JSON.parse(value) if value
  end
end
