# OUTSIDER: Configurações > Perfis de acesso > Pessoas (só administradores): quem está na conta com tipo, perfil e
# ramal; cadastro novo já com perfil, ramal e número de saída (Outsider::Access::People).
class Api::V1::Accounts::Outsider::AccessPeopleController < Api::V1::Accounts::BaseController
  before_action :check_administrator

  def index
    people = ::Outsider::Access::People.new(Current.account)
    settings = ::Outsider::Voice::Settings.new(Current.account)
    render json: {
      people: people.list, suggested_extension: people.suggested_extension,
      voice: { enabled: settings.enabled?, numbers: settings.numbers.map { |row| row.slice('number', 'state', 'label') },
               branches: settings.branches.map { |row| row.slice('id', 'name') } }
    }
  end

  def create
    unless Current.account.account_users.count < Current.account.usage_limits[:agents]
      return render json: { error: 'limit' }, status: :payment_required
    end

    user = ::Outsider::Access::People.new(Current.account, Current.user).create(person_params)
    ::Outsider::Crm::LiveUpdates.broadcast(Current.account.id, 'voice')
    render json: { id: user.id }
  rescue ::Outsider::Access::People::Invalid => e
    render json: { error: e.code }, status: :unprocessable_entity
  end

  def update
    ::Outsider::Access::People.new(Current.account, Current.user).update(params[:id], person_params)
    ::Outsider::Crm::LiveUpdates.broadcast(Current.account.id, 'access')
    ::Outsider::Crm::LiveUpdates.broadcast(Current.account.id, 'voice')
    head :no_content
  rescue ::Outsider::Access::People::Invalid => e
    render json: { error: e.code }, status: :unprocessable_entity
  end

  private

  def person_params
    params.permit(:name, :email, :type, :profile_id, :branch, :extension, :number, :inbound).to_h
  end

  def check_administrator
    return if Current.account_user&.administrator?

    render json: { error: 'forbidden' }, status: :forbidden
  end
end
