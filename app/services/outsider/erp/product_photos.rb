# OUTSIDER: as fotos de um produto do ERP. O Mais Prático guarda as fotos em G:\Anexos\Produto, no servidor dele, com o
# nome "<código do produto>_<posição>.<extensão>" ("1022_1.jpg", "1022_2.jpg", "1166_1.BMP"); um script que roda lá copia
# essa pasta para o Nextcloud da Somos (Configurações: pasta das fotos), e o chat acha as fotos de um produto pelo nome,
# com a busca do próprio Nextcloud. Não consulta o ERP. Só imagens; só leitura.
class Outsider::Erp::ProductPhotos
  class NotFound < StandardError; end

  TYPES = { 'jpg' => 'image/jpeg', 'jpeg' => 'image/jpeg', 'png' => 'image/png', 'gif' => 'image/gif', 'bmp' => 'image/bmp',
            'webp' => 'image/webp' }.freeze

  COUNTS_TTL = 10.minutes
  THUMB_TTL = 1.day
  THUMB_SIZE = 160

  def initialize(account)
    @account = account
    @settings = Outsider::Erp::Settings.new(account)
    @nextcloud = Outsider::Erp::NextcloudClient.new(@settings)
  end

  # [{ 'id' (a posição), 'nome' }] na ordem das posições
  def list(company, code)
    files(company, code).map { |file| { 'id' => file[:position], 'nome' => file[:name] } }
  end

  # { código => quantas fotos } de todos os produtos, para a lista mostrar quem tem foto sem abrir um por um: uma listagem
  # da pasta, guardada por COUNTS_TTL (foto nova aparece na contagem em até 10 minutos)
  def counts
    Rails.cache.fetch(['outsider-erp-photo-counts', @account.id, @settings.nextcloud_photos_folder], expires_in: COUNTS_TTL) do
      @nextcloud.list(@settings.nextcloud_photos_folder).filter_map do |name|
        match = name.match(/\A(\d+)_\d+\.([a-z]+)\z/i)
        match[1].to_i if match && TYPES.key?(match[2].downcase)
      end.tally
    end
  end

  # { 'filename', 'content', 'content_type' } da foto nessa posição
  def fetch(company, code, position)
    file = files(company, code).find { |item| item[:position] == position.to_i } || raise(NotFound)
    { 'filename' => file[:name], 'content' => @nextcloud.download(file[:href]), 'content_type' => file[:type] }
  end

  # a primeira foto do produto, pequena (JPG de até 160 px), para a lista mostrar a foto no lugar do ícone; guardada por
  # um dia. { 'content', 'content_type' }
  def thumbnail(company, code)
    first = files(company, code).first || raise(NotFound)
    key = ['outsider-erp-photo-thumb', @account.id, @settings.nextcloud_photos_folder, first[:name]]
    { 'content' => Rails.cache.fetch(key, expires_in: THUMB_TTL) { shrink(@nextcloud.download(first[:href])) }, 'content_type' => 'image/jpeg' }
  end

  private

  def shrink(content)
    Tempfile.create(['foto', '.img'], binmode: true) do |source|
      source.write(content)
      source.flush
      small = ImageProcessing::MiniMagick.source(source.path).resize_to_limit(THUMB_SIZE, THUMB_SIZE).convert('jpg').saver(quality: 75).call
      File.binread(small.path)
    ensure
      small&.close!
    end
  end

  # os arquivos "<código>_<posição>.<imagem>" direto na pasta das fotos ("10220_1.jpg" e as subpastas ficam de fora)
  def files(company, code)
    raise ArgumentError, 'company' unless @settings.companies.include?(company)

    code = Integer(code.to_s, 10)
    folder = "#{@nextcloud.files_root}#{@nextcloud.encoded(@settings.nextcloud_photos_folder)}/"
    found = @nextcloud.search(@settings.nextcloud_photos_folder, "#{code}_%").filter_map do |href, _modified|
      photo_file(href, code) if href.start_with?(folder) && href.delete_prefix(folder).exclude?('/')
    end
    found.sort_by { |file| file[:position] }.uniq { |file| file[:position] }
  end

  def photo_file(href, code)
    name = URI.decode_uri_component(File.basename(href))
    match = name.match(/\A#{code}_(\d+)\.([a-z]+)\z/i)
    type = match && TYPES[match[2].downcase]
    { href: href, name: name, position: match[1].to_i, type: type } if type
  end
end
