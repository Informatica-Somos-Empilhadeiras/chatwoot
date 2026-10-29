# OUTSIDER: gravação feita pelo telefone do navegador (Entrega 24). O navegador manda o arquivo no fim da
# ligação, com quem estava nela (o número e a hora em que cada um começou lá, o cliente primeiro); ela vai
# para a primeira ligação da pessoa que combina: com esse número, a que começou mais perto dessa hora
# (Active Storage, sem coluna nova).
class Outsider::Voice::Recording
  MAX_SIZE = 60.megabytes
  # a central grava o começo quando a ligação chega nela; no navegador, quando toca (pode ser depois de várias
  # etapas de toque) ou quando ele disca
  BEFORE = 4.minutes
  AFTER = 1.minute

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
    call = parties.lazy.map { |party| find(party['number'].to_s.delete('^0-9'), started(party['started_at'])) }.find(&:itself)
    return unless call

    type = file.content_type.split(';').first
    call.recording.attach(io: file, filename: "ligacao-#{call.id}.#{type.include?('ogg') ? 'ogg' : 'webm'}", content_type: type)
    call
  end

  private

  def started(value)
    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def find(number, started)
    return if started.nil? || number.blank?

    extension = @settings.agent_for(@user.id)['extension']
    Outsider::Voice::Call.where(account_id: @account.id, started_at: (started - BEFORE)..(started + AFTER))
                         .select { |call| mine?(call, extension) && same_party?(call, number) }
                         .min_by { |call| (call.started_at - started).abs }
  end

  # ligação da pessoa; entre ramais, a central guarda quem atendeu, então vale também o ramal dela de um dos lados
  def mine?(call, extension)
    call.user_id == @user.id || (call.internal? && [call.from_number, call.to_number].include?(extension))
  end

  def same_party?(call, number)
    return call.internal? && [call.from_number, call.to_number].include?(number) if number.length <= 4

    Outsider::Voice::PhoneNumber.same?(call.customer_number, number)
  end
end
