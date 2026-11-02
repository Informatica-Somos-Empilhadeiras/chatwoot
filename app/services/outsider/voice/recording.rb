# OUTSIDER: gravação feita pelo telefone do navegador (Entrega 24). O navegador manda o arquivo no fim da
# ligação, com quem estava nela (o número e a hora em que cada um começou lá, o cliente primeiro); ela vai
# para a primeira ligação da pessoa que combina: com esse número, a que começou mais perto dessa hora
# (Active Storage, sem coluna nova). A ligação certa sai de Outsider::Voice::CallMatch.
class Outsider::Voice::Recording
  MAX_SIZE = 60.megabytes

  # tira a gravação da ligação (prazo vencido ou apagada pelo administrador). Se ela foi encaminhada para um
  # contato, a mensagem da conversa usa o mesmo arquivo: aí só solta da ligação e o arquivo fica para a conversa
  def self.discard(call)
    attachment = call.recording_attachment
    return unless attachment

    shared = ActiveStorage::Attachment.where(blob_id: attachment.blob_id).where.not(id: attachment.id).exists?
    shared ? attachment.destroy! : call.recording.purge
  end

  def initialize(settings, user)
    @settings = settings
    @account = settings.account
    @user = user
  end

  def allowed?
    (@settings.recording? || @settings.auto_record?) && @settings.agent_for(@user.id).present?
  end

  def valid_file?(file)
    file.size <= MAX_SIZE && file.content_type.to_s.start_with?('audio/')
  end

  # devolve a ligação, ou nil sem ligação que combine
  def attach(file:, parties:)
    match = Outsider::Voice::CallMatch.new(@settings, @user)
    call = parties.lazy.map { |party| match.find(party['number'].to_s.delete('^0-9'), Outsider::Voice::CallMatch.time(party['started_at'])) }
                  .find(&:itself)
    return unless call

    type = file.content_type.split(';').first
    call.recording.attach(io: file, filename: "ligacao-#{call.id}.#{type.include?('ogg') ? 'ogg' : 'webm'}", content_type: type)
    call
  end
end
