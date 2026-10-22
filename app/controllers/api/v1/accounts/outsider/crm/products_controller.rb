# OUTSIDER: catálogo de máquinas e acessórios das propostas. Todos do CRM consultam (para montar proposta);
# cadastrar, alterar, trocar a imagem e apagar é do administrador e de quem ele liberou.
class Api::V1::Accounts::Outsider::Crm::ProductsController < Api::V1::Accounts::Outsider::Crm::ProposalBaseController
  IMAGE_MAX_SIZE = 1200

  before_action :ensure_catalog_manager, except: [:index, :show]
  before_action :fetch_product, except: [:index, :create]

  def index
    products = crm_scope(::Outsider::Crm::Product).with_attached_image.ordered
    products = products.active unless params[:all].present? && proposal_access.manage_catalog?
    render json: search(by_kind(products), params[:q].to_s.strip).map { |product| serializer.product(product) }
  end

  def show
    render json: serializer.product(@product)
  end

  def create
    product = crm_scope(::Outsider::Crm::Product).create!(product_params.merge(created_by_id: Current.user.id))
    render json: serializer.product(product), status: :created
  end

  def update
    @product.update!(product_params)
    render json: serializer.product(@product)
  end

  # Guarda a foto já reduzida; a anterior sai (as propostas apontam para o produto, não para a foto)
  def upload_image
    @product.image.attach(::Outsider::Crm::ImageShrinker.new(image_upload, max_size: IMAGE_MAX_SIZE).attachable)
    @product.save!
    render json: serializer.product(@product.reload)
  end

  def remove_image
    @product.image.purge_later if @product.image.attached?
    render json: serializer.product(@product.reload)
  end

  # Produto que já está numa proposta não se apaga: desative (active: false)
  def destroy
    raise ::Outsider::Crm::Remover::Blocked.new('used_in_proposals', count: @product.proposal_items.count) if @product.proposal_items.exists?

    @product.destroy!
    head :no_content
  end

  private

  def serializer
    ::Outsider::Crm::ProposalSerializer
  end

  def by_kind(products)
    ::Outsider::Crm::Product.kinds.key?(params[:kind].to_s) ? products.where(kind: params[:kind]) : products
  end

  def search(products, query)
    return products if query.blank?

    products.where('name ILIKE :q OR code ILIKE :q OR brand ILIKE :q', q: "%#{::Outsider::Crm::Product.sanitize_sql_like(query)}%")
  end

  def fetch_product
    @product = crm_scope(::Outsider::Crm::Product).find(params[:id])
  end

  def product_params
    params.require(:product).permit(:kind, :name, :code, :brand, :description, :sale_price_cents, :rental_price_cents, :active,
                                    specs: [:label, :value, :bold], features: [])
  end
end
