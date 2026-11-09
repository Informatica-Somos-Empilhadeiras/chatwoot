# OUTSIDER: o texto do aviso: a mensagem, ou "📷 Foto", "🎤 Áudio", "📄 nome do arquivo" quando vem só o anexo.
module Outsider::Push::Text
  module_function

  def of_message(message)
    text = message.content.to_s.squish
    return text if text.present?

    attachment = message.attachments.first
    return '' unless attachment

    of_file(attachment.file_type.to_s, attachment.file&.filename&.to_s)
  end

  def of_file(type, name = nil)
    case type.to_s
    when 'image' then '📷 Foto'
    when 'audio' then '🎤 Áudio'
    when 'video' then '🎬 Vídeo'
    when 'location' then '📍 Localização'
    when 'contact' then '👤 Contato'
    else "📄 #{name.presence || 'Arquivo'}"
    end
  end

  def of_teams(message)
    text = message.content.to_s.squish
    return text if text.present?

    attachment = Array(message.attachments).first
    return '' unless attachment

    return '📷 Foto' if attachment['kind'] == 'image'
    return '🎤 Áudio' if Outsider::Teams::Graph::Files.audio?(attachment['name'])

    "📄 #{attachment['name'].presence || 'Arquivo'}"
  end
end
