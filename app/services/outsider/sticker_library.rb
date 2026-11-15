# OUTSIDER: a coleção de figurinhas de um atendente (Outsider::Sticker / Outsider::StickerPack), por conta.
#
# - Entrada: uma imagem subida (PNG, JPG, WEBP, GIF) ou um anexo de imagem de uma conversa (a figurinha
#   que o cliente mandou). Tudo vira webp 512x512 com fundo transparente, que é o formato das figurinhas
#   do WhatsApp (a API oficial só aceita assim; a Evolution converte sozinha, mas mandamos pronto).
#   Um webp que já vier até 512x512 fica como está, para não perder animação.
# - A mesma imagem não entra duas vezes na coleção (digest do arquivo final).
# - Favoritar, mover de grupo, apagar, e os grupos em si.
# - "Recentes" = últimas usadas (uses_count / last_used_at, marcados pelo Outsider::StickerSender).
require 'image_processing/vips'

class Outsider::StickerLibrary
  class Invalid < StandardError; end

  SIZE = 512
  MAX_INPUT = 8.megabytes
  MAX_STICKERS = 1000
  MAX_PACKS = 40
  ACCEPTED_TYPES = %w[image/png image/jpeg image/webp image/gif].freeze
  WEBP_QUALITY = 85

  pattr_initialize [:user!, :account!]

  def list
    { stickers: stickers.map(&:picker_data), packs: packs.map(&:picker_data), limits: { stickers: MAX_STICKERS, packs: MAX_PACKS } }
  end

  def find(id)
    stickers.find(id)
  end

  # imagem subida pelo atendente (ActionDispatch::Http::UploadedFile)
  def add_upload(uploaded)
    raise Invalid, 'no_file' if uploaded.blank? || !uploaded.respond_to?(:tempfile)
    raise Invalid, 'file_too_big' if uploaded.size.to_i > MAX_INPUT

    content_type = detect_type(uploaded.tempfile.path, uploaded.content_type)
    raise Invalid, 'file_type' unless ACCEPTED_TYPES.include?(content_type)

    add_bytes(convert(uploaded.tempfile.path, content_type), source: 'upload')
  end

  # anexo de imagem de uma mensagem (figurinha ou foto recebida); quem chama já conferiu a permissão
  def add_attachment(attachment)
    raise Invalid, 'not_image' unless attachment.file_type == 'image' && attachment.file.attached?

    blob = attachment.file.blob
    raise Invalid, 'file_too_big' if blob.byte_size > MAX_INPUT

    bytes = blob.open { |tempfile| convert(tempfile.path, detect_type(tempfile.path, blob.content_type)) }
    add_bytes(bytes, source: 'received')
  end

  def update(id, attributes)
    sticker = find(id)
    changes = {}
    changes[:favorite] = ActiveModel::Type::Boolean.new.cast(attributes[:favorite]) == true if attributes.key?(:favorite)
    changes[:emoji] = attributes[:emoji].to_s.strip.presence if attributes.key?(:emoji)
    changes[:pack_id] = pack_id_for(attributes[:pack_id]) if attributes.key?(:pack_id)
    sticker.update!(changes)
    sticker
  end

  def destroy(id)
    find(id).destroy!
  end

  def mark_used(sticker)
    sticker.update_columns(uses_count: sticker.uses_count + 1, last_used_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def create_pack(name)
    raise Invalid, 'too_many_packs' if packs.count >= MAX_PACKS

    pack = packs.new(name: clean_name(name), position: (packs.maximum(:position) || 0) + 1)
    pack.save!
    pack
  end

  def update_pack(id, attributes)
    pack = packs.find(id)
    changes = {}
    changes[:name] = clean_name(attributes[:name]) if attributes.key?(:name)
    changes[:position] = attributes[:position].to_i if attributes.key?(:position)
    pack.update!(changes)
    pack
  end

  def destroy_pack(id)
    packs.find(id).destroy!
  end

  private

  def stickers
    Outsider::Sticker.where(account_id: account.id, user_id: user.id).with_attached_file.order(:position, :id)
  end

  def packs
    Outsider::StickerPack.where(account_id: account.id, user_id: user.id).order(:position, :id)
  end

  def pack_id_for(value)
    return nil if value.blank?

    packs.find(value).id
  end

  def clean_name(name)
    cleaned = name.to_s.squish.first(Outsider::StickerPack::MAX_NAME)
    raise Invalid, 'invalid_name' if cleaned.blank?

    cleaned
  end

  def add_bytes(bytes, source:)
    digest = Digest::SHA256.hexdigest(bytes)
    existing = stickers.find_by(digest: digest)
    return [existing, true] if existing
    raise Invalid, 'too_many' if stickers.count >= MAX_STICKERS

    sticker = Outsider::Sticker.new(account_id: account.id, user_id: user.id, digest: digest, source: source,
                                    animated: animated?(bytes), position: (stickers.maximum(:position) || 0) + 1)
    sticker.file.attach(io: StringIO.new(bytes), filename: "figurinha-#{digest.first(12)}.webp", content_type: 'image/webp')
    sticker.save!
    [sticker, false]
  end

  # o tipo real do arquivo, não só o que o navegador disse
  def detect_type(path, declared)
    File.open(path, 'rb') { |io| Marcel::MimeType.for(io, declared_type: declared) }
  end

  # webp pronto (até 512x512) fica igual; o resto vira webp quadrado com fundo transparente
  def convert(path, content_type)
    return File.binread(path) if content_type == 'image/webp' && ready?(path)

    result = ImageProcessing::Vips.source(path).resize_and_pad(SIZE, SIZE, alpha: true).convert('webp').saver(quality: WEBP_QUALITY).call
    File.binread(result.path)
  rescue Vips::Error, ImageProcessing::Error => e
    raise Invalid, "image_error: #{e.message.to_s.first(120)}"
  ensure
    result&.close!
  end

  def ready?(path)
    image = Vips::Image.new_from_file(path)
    image.width <= SIZE && image.height <= SIZE && File.size(path) <= 1.megabyte
  rescue Vips::Error
    false
  end

  def animated?(bytes)
    bytes.byteslice(0, 64).to_s.include?('ANIM')
  end
end
