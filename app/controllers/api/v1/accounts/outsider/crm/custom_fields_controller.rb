# OUTSIDER: campos personalizados das oportunidades. Todos do CRM leem; administradores alteram.
# A chave (key) não muda depois de criada, porque os valores já gravados usam essa chave.
class Api::V1::Accounts::Outsider::Crm::CustomFieldsController < Api::V1::Accounts::Outsider::Crm::BaseController
  before_action :ensure_crm_admin, except: [:index]
  before_action :fetch_field, only: [:update, :destroy]

  def index
    render json: crm_scope(::Outsider::Crm::CustomFieldDefinition).ordered.map { |field| ::Outsider::Crm::Serializer.custom_field(field) }
  end

  def create
    field = crm_scope(::Outsider::Crm::CustomFieldDefinition).create!(field_params)
    render json: ::Outsider::Crm::Serializer.custom_field(field), status: :created
  end

  def update
    @field.update!(field_params.except(:key))
    render json: ::Outsider::Crm::Serializer.custom_field(@field)
  end

  # Apagar só esconde o campo; os valores continuam gravados nas oportunidades
  def destroy
    @field.update!(active: false)
    head :no_content
  end

  private

  def fetch_field
    @field = crm_scope(::Outsider::Crm::CustomFieldDefinition).find(params[:id])
  end

  def field_params
    params.require(:custom_field).permit(:key, :label, :field_type, :required, :active, :position, options: [])
  end
end
