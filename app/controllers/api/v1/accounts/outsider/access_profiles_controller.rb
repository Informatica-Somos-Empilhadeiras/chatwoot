# OUTSIDER: Configurações > Perfis de acesso (só administradores). Os perfis prontos não são apagados; Administrador
# não muda (vale para quem é administrador da conta). Apagar um perfil criado devolve as pessoas dele ao perfil padrão.
class Api::V1::Accounts::Outsider::AccessProfilesController < Api::V1::Accounts::BaseController
  before_action :check_administrator
  before_action :fetch_profile, only: [:update, :destroy]

  def index
    profiles = ::Outsider::Access::Defaults.new(Current.account).ensure!.ordered.to_a
    counts = ::Outsider::AccessMember.where(account_id: Current.account.id).group(:profile_id).count
    defaults = %w[agent technician].index_with { |type| ::Outsider::Access::Defaults.new(Current.account).default_for(type)&.id }
    implicit = Current.account.account_users.where.not(role: :administrator)
                      .where.not(user_id: ::Outsider::AccessMember.where(account_id: Current.account.id).select(:user_id)).count
    admins = Current.account.account_users.where(role: :administrator).count
    render json: {
      catalog: ::Outsider::Access::Catalog.as_json, locked: Array(Current.account.internal_attributes.to_h[::Outsider::Access::ADMIN_ONLY_KEY]),
      profiles: profiles.map { |profile| row(profile, counts, defaults, implicit, admins) }
    }
  end

  def create
    return render json: { error: 'limit' }, status: :unprocessable_entity if profiles_scope.count >= ::Outsider::AccessProfile::MAX_PER_ACCOUNT

    source = params[:copy_from].present? ? profiles_scope.find(params[:copy_from]) : nil
    profile = profiles_scope.create!(name: params[:name], description: params[:description], kind: 'custom', created_by: Current.user,
                                     permissions: permissions_param || source&.permissions || ::Outsider::Access::Catalog.defaults('agent'))
    broadcast
    render json: { id: profile.id }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.attribute_names.first }, status: :unprocessable_entity
  end

  def update
    return render json: { error: 'administrator' }, status: :unprocessable_entity if @profile.administrator?

    ActiveRecord::Base.transaction do
      @profile.assign_attributes(params.permit(:name, :description).to_h)
      @profile.permissions = @profile.permissions.merge(permissions_param) if permissions_param
      @profile.save!
      update_default_for if params.key?(:default_for)
    end
    broadcast
    render json: { id: @profile.id }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.attribute_names.first }, status: :unprocessable_entity
  end

  def destroy
    return render json: { error: 'system' }, status: :unprocessable_entity if @profile.system?

    slot = @profile.default_for
    @profile.destroy!
    # era o padrão: volta para o pronto do mesmo tipo
    profiles_scope.find_by(kind: slot)&.update!(default_for: slot) if slot
    broadcast
    head :no_content
  end

  private

  def profiles_scope
    ::Outsider::AccessProfile.where(account_id: Current.account.id)
  end

  def fetch_profile
    @profile = profiles_scope.find(params[:id])
  end

  def permissions_param
    return unless params[:permissions].respond_to?(:permit)

    params[:permissions].permit(*::Outsider::Access::Catalog::KEYS).to_h.transform_values(&:to_s)
  end

  # padrão para agentes ou técnicos: só um perfil por tipo; tirar o padrão devolve ao pronto
  def update_default_for
    slot = params[:default_for].presence
    if slot
      raise ActiveRecord::RecordInvalid, @profile unless ::Outsider::AccessProfile::DEFAULT_FOR.include?(slot)

      profiles_scope.where(default_for: slot).where.not(id: @profile.id).update_all(default_for: nil) # rubocop:disable Rails/SkipsModelValidations
      @profile.update!(default_for: slot)
    elsif @profile.default_for
      old = @profile.default_for
      @profile.update!(default_for: nil)
      profiles_scope.find_by(kind: old)&.update!(default_for: old)
    end
  end

  def row(profile, counts, defaults, implicit, admins)
    count = counts[profile.id].to_i
    count += implicit if defaults['agent'] == profile.id
    count = admins if profile.administrator?
    profile.slice(:id, :name, :description, :kind, :default_for, :created_at)
           .merge(permissions: ::Outsider::Access::Catalog::KEYS.index_with { |key| profile.level(key) },
                  members_count: count, created_by: profile.created_by&.name, technician: profile.technician?)
  end

  # telas abertas conferem o acesso de novo (menu e rotas)
  def broadcast
    ::Outsider::Crm::LiveUpdates.broadcast(Current.account.id, 'access')
  end

  def check_administrator
    return if Current.account_user&.administrator?

    render json: { error: 'forbidden' }, status: :forbidden
  end
end
