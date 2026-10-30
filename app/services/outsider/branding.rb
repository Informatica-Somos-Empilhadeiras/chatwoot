# OUTSIDER: aparência da conta, só o administrador muda e vale para todos os agentes da conta.
#   - title: nome na aba do navegador (no lugar de "Chatwoot")
#   - favicon, logo (canto do menu) e papel de parede das conversas, guardados uma vez cada, já
#     reduzidos (o disco da VPS é pequeno)
#   - wallpaper_fit: cover (preenche) ou tile (repete, como o fundo do WhatsApp)
#   - wallpaper_dim: quanto o fundo fica clareado (tema claro) ou escurecido (tema escuro), de 0 a 90%
# Ao salvar, quem está com o painel aberto recebe o aviso 'branding' e aplica na hora.
class Outsider::Branding
  KEY = 'outsider_branding'.freeze
  FITS = %w[cover tile].freeze
  DEFAULT_DIM = 60
  TITLE_LIMIT = 60
  IMAGES = {
    favicon: { size: 256, max_bytes: 2.megabytes, format: 'png' },
    logo: { size: 512, max_bytes: 3.megabytes, format: 'png' },
    wallpaper: { size: 2400, max_bytes: 8.megabytes, format: 'jpg' }
  }.freeze
  TYPES = %w[image/png image/jpeg image/webp image/gif].freeze
  CONTENT_TYPES = { 'png' => 'image/png', 'jpg' => 'image/jpeg' }.freeze

  class Invalid < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super(code.to_s)
    end
  end

  def initialize(account)
    @account = account
  end

  def as_json(*)
    settings = stored
    {
      title: settings['title'].presence,
      favicon_url: url_for(:favicon),
      logo_url: url_for(:logo),
      wallpaper_url: url_for(:wallpaper),
      wallpaper_fit: FITS.include?(settings['wallpaper_fit']) ? settings['wallpaper_fit'] : 'cover',
      wallpaper_dim: settings.key?('wallpaper_dim') ? settings['wallpaper_dim'].to_i : DEFAULT_DIM
    }
  end

  def update(params)
    files = IMAGES.keys.index_with { |kind| params[kind] }.compact_blank
    files.each { |kind, upload| validate!(kind, upload) }

    files.each { |kind, upload| attachment(kind).attach(prepare(kind, upload)) }
    IMAGES.each_key { |kind| attachment(kind).purge_later if truthy?(params["remove_#{kind}"]) && files[kind].blank? }
    save_settings(params)
    broadcast
    as_json
  end

  private

  def stored
    @account.reload.internal_attributes.to_h[KEY].to_h
  end

  def attachment(kind)
    @account.public_send("outsider_#{kind}")
  end

  def url_for(kind)
    file = attachment(kind)
    return unless file.attached?

    Rails.application.routes.url_helpers.rails_blob_path(file, only_path: true)
  end

  def validate!(kind, upload)
    raise Invalid, :invalid_file unless upload.respond_to?(:tempfile)
    raise Invalid, :too_big if upload.size > IMAGES.dig(kind, :max_bytes)

    @types ||= {}
    @types[kind] = Marcel::MimeType.for(upload.tempfile, name: upload.original_filename)
    raise Invalid, :invalid_type unless TYPES.include?(@types[kind])
  end

  # reduz e converte (o favicon e o logo em PNG, o fundo em JPG); sem vips nem ImageMagick, guarda o
  # original se já for PNG ou JPG
  def prepare(kind, upload)
    config = IMAGES.fetch(kind)
    format = config[:format]
    io = shrink(upload, config[:size], format)
    return { io: io, filename: "#{kind}.#{format}", content_type: CONTENT_TYPES[format] } if io

    original = @types[kind]
    raise Invalid, :invalid_type unless CONTENT_TYPES.value?(original)

    { io: File.open(upload.tempfile.path), filename: "#{kind}.#{CONTENT_TYPES.key(original)}", content_type: original }
  end

  def shrink(upload, size, format)
    [ImageProcessing::Vips, ImageProcessing::MiniMagick].each do |processor|
      pipeline = processor.source(upload.tempfile.path).resize_to_limit(size, size)
      pipeline = pipeline.saver(quality: 82) if format == 'jpg'
      return pipeline.convert(format).call
    rescue StandardError, LoadError
      next
    end
    nil
  end

  def save_settings(params)
    @account.with_lock do
      settings = @account.internal_attributes.to_h[KEY].to_h
      settings['title'] = params[:title].to_s.strip.first(TITLE_LIMIT) if params.key?(:title)
      settings['wallpaper_fit'] = params[:wallpaper_fit].to_s if FITS.include?(params[:wallpaper_fit].to_s)
      settings['wallpaper_dim'] = params[:wallpaper_dim].to_i.clamp(0, 90) if params[:wallpaper_dim].present?
      # update_columns para não esbarrar nas validações de outros campos da conta
      @account.update_columns(internal_attributes: @account.internal_attributes.to_h.merge(KEY => settings)) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def truthy?(value)
    ActiveModel::Type::Boolean.new.cast(value) == true
  end

  def broadcast
    ActionCable.server.broadcast("account_#{@account.id}", { event: 'outsider.notice', data: { account_id: @account.id, kind: 'branding' } })
  end
end
