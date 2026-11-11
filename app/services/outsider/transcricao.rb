# OUTSIDER: guarda a transcrição que o navegador do agente fez (Whisper local) para que todo mundo veja e ninguém
# precise transcrever o mesmo áudio de novo.
#   WhatsApp: attachments.meta['transcribed_text'], o mesmo campo que o Chatwoot preenche quando transcreve pelo Captain,
#     então a bolha de áudio, a busca e a prévia "[Voice Message]" já funcionam. Em meta['outsider_transcricao'] fica
#     quem transcreveu, com que motor e modelo. A mensagem é avisada ao vivo (message.updated).
#   Teams: o anexo da mensagem (jsonb) ganha 'transcript' e 'transcript_meta'; o dono da área é avisado ao vivo.
module Outsider::Transcricao
  MAX_TEXT = 30_000
  ENGINES = %w[navegador api].freeze
  Invalid = Class.new(StandardError)

  module_function

  def limpar(text)
    text.to_s.unicode_normalize(:nfc).gsub(/[ \t]+/, ' ').gsub(/ ?\n ?/, "\n").gsub(/\n{3,}/, "\n\n").strip.first(MAX_TEXT)
  end

  def meta_de(user, params)
    engine = ENGINES.include?(params[:engine].to_s) ? params[:engine].to_s : 'navegador'
    {
      'by' => user&.id, 'name' => user&.name.to_s.first(80), 'engine' => engine, 'model' => params[:model].to_s.first(60),
      'language' => params[:language].to_s.first(10).presence, 'duration' => params[:duration].to_f.round(1),
      'at' => Time.current.iso8601
    }.compact
  end

  def gravar_anexo(attachment, text:, user:, params: {})
    text = limpar(text)
    raise Invalid, 'empty' if text.blank?
    raise Invalid, 'not_audio' unless %w[audio video].include?(attachment.file_type.to_s)

    attachment.update!(meta: (attachment.meta || {}).merge('transcribed_text' => text, 'outsider_transcricao' => meta_de(user, params)))
    attachment.message&.reload&.send_update_event
    text
  end

  def apagar_anexo(attachment)
    attachment.update!(meta: (attachment.meta || {}).except('transcribed_text', 'outsider_transcricao'))
    attachment.message&.reload&.send_update_event
  end

  def gravar_teams(message, index, text:, user:, params: {})
    text = limpar(text)
    raise Invalid, 'empty' if text.blank?

    list = Array(message.attachments).map(&:dup)
    item = list[index]
    raise Invalid, 'not_audio' unless item && Outsider::Teams::Graph::Files.kind_of(item) == 'audio'

    list[index] = item.merge('transcript' => text, 'transcript_meta' => meta_de(user, params))
    message.update!(attachments: list)
    Outsider::Teams::Graph::Notifier.message(message.thread.link, message.thread, message, action: 'updated')
    text
  end
end
