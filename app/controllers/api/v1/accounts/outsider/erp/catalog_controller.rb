# OUTSIDER: peças e serviços do ERP (Outsider::Erp::Catalog): a lista do orçamento (abre pronta e filtra por código ou
# nome), a descrição técnica, o produto inteiro da aba Produtos (Outsider::Erp::ProductDetail) com as fotos que estão no
# Nextcloud (Outsider::Erp::ProductPhotos) e o envio de uma foto ao cliente numa conversa que já existe
# (Outsider::Erp::PhotoSender). Só leitura no ERP, escopada numa unidade da Somos. Consulta pede a aba Produtos do perfil
# ou o uso do ERP (o orçamento); mandar foto pede o uso do ERP.
class Api::V1::Accounts::Outsider::Erp::CatalogController < Api::V1::Accounts::Outsider::Erp::BaseController
  include ::Outsider::Erp::DocumentSending

  before_action :ensure_catalog_access, except: :send_photo
  before_action :ensure_erp_use, only: :send_photo
  before_action :ensure_photos, only: %i[photos photo thumbnail send_photo photo_counts_for]

  rescue_from(ArgumentError) { |error| render json: { error: 'invalid', field: error.message }, status: :unprocessable_entity }
  rescue_from(::Outsider::Erp::ProductDetail::NotFound, ::Outsider::Erp::ProductPhotos::NotFound) do
    render json: { error: 'not_found' }, status: :not_found
  end
  rescue_from(::Outsider::Erp::NextcloudClient::Error) do |error|
    render json: { error: 'nextcloud_unavailable', message: error.message }, status: :service_unavailable
  end

  # com fotos ligadas, cada produto diz quantas tem ('fotos'; nil se o Nextcloud não respondeu: a busca segue sem isso)
  def index
    products = catalog.search(params.require(:company), params[:q])
    counts = photo_counts
    products = products.map { |product| product.merge(fotos: counts&.fetch(product[:codigo], 0)) } if settings.product_photos_enabled?
    render json: { products: products }
  end

  # quantas fotos têm os produtos já escolhidos no orçamento (codes=1022,59)
  def photo_counts_for
    counts = product_photos.counts
    codes = params.require(:codes).to_s.split(',').filter_map { |code| Integer(code, 10, exception: false) }.first(200)
    render json: { counts: codes.index_with { |code| counts.fetch(code, 0) } }
  end

  def technical
    render json: { technical: catalog.technical(params.require(:company), Integer(params.require(:code).to_s)) }
  end

  # o produto inteiro e a lista das fotos dele (as imagens vêm uma a uma, em photo)
  def show
    company = params.require(:company).to_s
    detail = ::Outsider::Erp::ProductDetail.new(Current.account).build(company, params[:id])
    render json: detail.merge('fotos' => settings.product_photos_enabled? ? product_photos.list(company, params[:id]) : [])
  end

  # só a lista das fotos (o botão de fotos na busca de produtos do orçamento)
  def photos
    render json: { fotos: product_photos.list(params.require(:company).to_s, params[:id]) }
  end

  # a primeira foto em miniatura (lista da busca e itens do orçamento)
  def thumbnail
    file = product_photos.thumbnail(params.require(:company).to_s, params[:id])
    expires_in 1.hour, public: false
    send_data file['content'], type: file['content_type'], disposition: 'inline'
  end

  def photo
    file = product_photos.fetch(params.require(:company).to_s, params[:id], params[:photo_id])
    send_data file['content'], filename: file['filename'], type: file['content_type'], disposition: 'inline'
  end

  # conversation_id (a do chat) ou contact_id (a conversa aberta dele no WhatsApp); message vai junto da foto
  def send_photo
    company = params.require(:company).to_s
    ::Outsider::Erp::PhotoSender.new(Current.account_user).deliver(
      -> { product_photos.fetch(company, params[:id], params[:photo_id]) },
      conversation: conversation, contact_id: params[:contact_id], message: params[:message]
    )
    render json: { ok: true }
  end

  private

  def catalog
    @catalog ||= ::Outsider::Erp::Catalog.new(Current.account)
  end

  def product_photos
    @product_photos ||= ::Outsider::Erp::ProductPhotos.new(Current.account)
  end

  def photo_counts
    return unless settings.product_photos_enabled?

    product_photos.counts
  rescue ::Outsider::Erp::NextcloudClient::Error
    nil
  end

  def ensure_catalog_access
    render json: { error: 'erp_forbidden' }, status: :forbidden unless can_use_erp? || allows_screen?('erp_products')
  end

  def ensure_erp_use
    render json: { error: 'erp_forbidden' }, status: :forbidden unless can_use_erp?
  end

  def ensure_photos
    render json: { error: 'not_found' }, status: :not_found unless settings.product_photos_enabled?
  end
end
