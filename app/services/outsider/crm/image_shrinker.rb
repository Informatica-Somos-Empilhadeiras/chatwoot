# OUTSIDER: reduz a imagem enviada (foto da máquina, cabeçalho e rodapé do modelo) antes de guardar, para
# o PDF da proposta não ficar pesado. Guarda só a versão reduzida: um arquivo por imagem. Usa o vips (o
# mesmo das miniaturas do Chatwoot) e, sem ele, o ImageMagick; se nenhum funcionar, guarda o original.
class Outsider::Crm::ImageShrinker
  TYPES = { 'image/png' => 'png', 'image/jpeg' => 'jpg' }.freeze

  class Invalid < StandardError; end

  def initialize(upload, max_size:)
    @upload = upload
    @max_size = max_size
  end

  # { io:, filename:, content_type: } para o attach do Active Storage
  def attachable
    content_type = Marcel::MimeType.for(@upload.tempfile, name: @upload.original_filename)
    raise Invalid unless TYPES.key?(content_type)

    extension = TYPES.fetch(content_type)
    base = File.basename(@upload.original_filename.to_s, '.*').parameterize.presence || 'imagem'
    { io: shrink(extension) || File.open(@upload.tempfile.path), filename: "#{base}.#{extension}", content_type: content_type }
  end

  private

  def shrink(extension)
    [ImageProcessing::Vips, ImageProcessing::MiniMagick].each do |processor|
      return processor.source(@upload.tempfile.path).resize_to_limit(@max_size, @max_size).convert(extension).call
    rescue StandardError, LoadError
      next
    end
    nil
  end
end
