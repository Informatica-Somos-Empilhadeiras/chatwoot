# OUTSIDER: encaminhar mensagens da área Teams para outros chats/canais da mesma pessoa (até 5 de uma vez).
# O Teams não tem "encaminhar" no Graph, então cada mensagem vira uma mensagem nova no destino, com
# "↪ Encaminhada de Fulano" em cima do texto. Os arquivos são copiados (baixados da Microsoft com o token da pessoa e
# enviados de novo para o OneDrive/canal de destino, como no envio normal): quem está no destino sempre consegue abrir,
# mesmo sem acesso ao arquivo original. Fotos pequenas vão dentro da mensagem (como colar no Teams).
#   prepare: cria as mensagens "enviando" nos destinos (aparecem na hora) e devolve os ids para o ForwardJob.
#   deliver: copia os arquivos e manda uma mensagem (o job chama em ordem, uma por vez, para manter a sequência).
class Outsider::Teams::Graph::Forward
  MAX_MESSAGES = 30
  MAX_TARGETS = 5
  MAX_COPY = 250.megabytes
  MAX_INLINE = 3.megabytes
  MAX_INLINE_TOTAL = 3.5.megabytes
  MARK = '↪'.freeze

  def self.prepare(link, sources, targets, comment: nil)
    sender = link.display_name.presence || link.user&.name
    targets.flat_map do |target|
      created = []
      created << build(target, link, sender, comment.to_s.strip.first(5000), []) if comment.present?
      sources.each { |source| created << build(target, link, sender, header(source) + source.content.to_s, copies(source)) }
      created
    end
  end

  def self.header(source)
    who = source.mine ? 'Você' : source.sender_name.presence || 'Teams'
    text = source.content.present? ? "\n" : ''
    "#{MARK} Encaminhada de #{who}#{text}"
  end

  # anexos do destino ainda sem arquivo: só o necessário para copiar depois (de onde vem e como se chama)
  def self.copies(source)
    Array(source.attachments).each_with_index.filter_map do |attachment, index|
      next if attachment['pending']

      { 'kind' => attachment['kind'], 'name' => attachment['name'], 'size' => attachment['size'], 'pending' => true,
        'forward_from' => { 'm' => source.id, 'i' => index } }
    end
  end

  def self.build(target, link, sender, content, attachments)
    target.messages.create!(mine: true, sender_name: sender, sender_ms_id: link.ms_user_id, content: content.first(20_000).presence,
                            attachments: attachments, status: 'sending', sent_at: Time.current)
  end

  def initialize(message)
    @message = message
    @thread = message.thread
    @link = @thread.link
    @files = Outsider::Teams::Graph::Files.new(@link)
  end

  def deliver
    return unless @message.status == 'sending'

    inline = []
    uploads = []
    missing = []
    Array(@message.attachments).each do |attachment|
      next uploads << attachment unless attachment['forward_from']

      copy(attachment, inline, uploads, missing)
    end
    @message.update!(attachments: uploads + inline.pluck(:attachment), content: with_missing(missing))
    Outsider::Teams::Graph::Outbound.new(@message).perform(inline: inline.map { |image| image.slice(:body, :content_type) })
  end

  private

  def copy(attachment, inline, uploads, missing)
    source = Outsider::TeamsMessage.joins(:thread).where(outsider_teams_threads: { link_id: @link.id })
                                   .find_by(id: attachment.dig('forward_from', 'm'))
    index = attachment.dig('forward_from', 'i').to_i
    original = source && Array(source.attachments)[index]
    return missing << attachment['name'] unless original

    original = @files.resolve!(source, index) if original['hosted'].blank?
    with_file(original) do |file|
      if small_image?(original, file, inline)
        file.rewind
        inline << { body: file.read, content_type: file.content_type,
                    attachment: { 'kind' => 'image', 'name' => original['name'], 'size' => file.size, 'pending' => true } }
      else
        uploads << @files.upload(@thread, file)
      end
    end
  rescue Outsider::Teams::Graph::Client::Error, ArgumentError => e
    Rails.logger.warn("[outsider_teams_forward] message=#{@message.id} #{attachment['name']}: #{e.message}")
    missing << attachment['name']
  end

  # cópia temporária no disco do servidor, apagada logo depois do envio
  def with_file(original)
    name = original['name'].presence || 'arquivo'
    temp = Tempfile.new(['outsider-teams', File.extname(name)], binmode: true)
    size = 0
    @files.stream(original) do |chunk|
      size += chunk.bytesize
      raise ArgumentError, 'too_big' if size > MAX_COPY

      temp.write(chunk)
    end
    temp.flush
    temp.rewind
    type = original['mime'].presence || Marcel::MimeType.for(temp, name: name) || 'application/octet-stream'
    yield ActionDispatch::Http::UploadedFile.new(tempfile: temp, filename: name, type: type)
  ensure
    temp&.close!
  end

  def small_image?(original, file, inline)
    return false unless Outsider::Teams::Graph::Files.image?(original['name']) || original['kind'] == 'image'
    return false unless file.content_type.to_s.start_with?('image/') && file.size <= MAX_INLINE

    inline.sum { |image| image[:body].bytesize } + file.size <= MAX_INLINE_TOTAL
  end

  def with_missing(missing)
    return @message.content if missing.empty?

    [@message.content, "(Não deu para copiar: #{missing.compact.join(', ')})"].compact.join("\n")
  end
end
