# OUTSIDER: aparência da conta (ver app/services/outsider/branding.rb). Todos da conta leem; só o
# administrador muda.
class Api::V1::Accounts::Outsider::BrandingsController < Api::V1::Accounts::BaseController
  before_action :check_administrator, only: [:update]

  def show
    render json: branding.as_json
  end

  def update
    render json: branding.update(params)
  rescue ::Outsider::Branding::Invalid => e
    render json: { error: e.code }, status: :unprocessable_entity
  end

  private

  def branding
    @branding ||= ::Outsider::Branding.new(Current.account)
  end

  def check_administrator
    return if Current.account_user&.administrator?

    render json: { error: 'forbidden' }, status: :forbidden
  end
end
