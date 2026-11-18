# OUTSIDER: Configurações > Perfis de acesso > Pessoas. Lista quem está na conta com o tipo, o perfil e o ramal, e
# cadastra gente nova já com tudo: tipo (Administrador, Agente ou Técnico), perfil (o padrão do tipo vem marcado),
# filial, ramal e número de saída. O usuário nasce pelo AgentBuilder do Chatwoot (mesmo convite por e-mail) e o ramal
# vai para Telefonia > Configurações (técnico não toca nas ligações da empresa, só nas feitas para o ramal dele).
class Outsider::Access::People
  TYPES = %w[administrator agent technician].freeze
  EXTENSIONS = (201..599)

  class Invalid < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super(code)
    end
  end

  def initialize(account, inviter = nil)
    @account = account
    @inviter = inviter
    @settings = Outsider::Voice::Settings.new(account)
  end

  def list
    Outsider::Access::Defaults.new(@account).ensure!
    members = Outsider::AccessMember.where(account_id: @account.id).index_by(&:user_id)
    profiles = Outsider::AccessProfile.where(account_id: @account.id).index_by(&:id)
    devices = NotificationSubscription.browser_push.where(user_id: account_users.map(&:user_id)).group(:user_id).count
    account_users.map { |account_user| row(account_user, members, profiles, devices) }
  end

  def suggested_extension
    taken = @settings.data['agents'].values.pluck('extension').compact
    EXTENSIONS.map(&:to_s).find { |extension| taken.exclude?(extension) }
  end

  def create(params)
    params = params.to_h.stringify_keys
    type = params['type'].to_s
    raise Invalid, 'type' unless TYPES.include?(type)

    profile = pick_profile(type, params['profile_id'])
    check_extension!(params['extension'])
    user = nil
    ActiveRecord::Base.transaction do
      user = AgentBuilder.new(email: params['email'].to_s.strip.downcase, name: params['name'].to_s.strip, inviter: @inviter,
                              account: @account, role: type == 'administrator' ? :administrator : :agent).perform
      assign(user.id, profile) unless type == 'administrator'
    end
    put_line(user.id, params, type, creating: true) if params['extension'].present?
    user
  rescue ActiveRecord::RecordInvalid => e
    raise Invalid, e.record.errors.attribute_names.include?(:email) ? 'email' : 'invalid'
  end

  # muda o perfil e o ramal de quem já está na conta
  def update(user_id, params)
    params = params.to_h.stringify_keys
    account_user = @account.account_users.find_by!(user_id: user_id)
    if params.key?('profile_id') && !account_user.administrator?
      profile = Outsider::AccessProfile.find_by(account_id: @account.id, id: params['profile_id'])
      raise Invalid, 'profile' unless profile && !profile.administrator?

      assign(user_id, profile)
    end
    put_line(user_id, params, type_of(account_user)) if params.keys.intersect?(%w[extension branch number inbound])
    account_user
  end

  private

  def account_users
    @account_users ||= @account.account_users.includes(:user).order('users.name').references(:users).to_a
  end

  def row(account_user, members, profiles, devices)
    user = account_user.user
    profile = account_user.administrator? ? nil : profiles[members[user.id]&.profile_id] || default_profile
    agent = @settings.data['agents'][user.id.to_s].to_h
    {
      id: user.id, name: user.name, email: user.email, thumbnail: user.avatar_url, role: account_user.role,
      confirmed: user.confirmed?, type: type_for(account_user, profile), profile_id: profile&.id, profile_name: profile&.name,
      chosen: members.key?(user.id), push_devices: devices[user.id].to_i,
      voice: { extension: agent['extension'].presence, enabled: agent['enabled'] == true, branch: agent['branch'],
               number: agent['number'], inbound: agent.fetch('inbound', true) }
    }
  end

  def default_profile
    @default_profile ||= Outsider::Access::Defaults.new(@account).default_for('agent')
  end

  def type_of(account_user)
    return 'administrator' if account_user.administrator?

    Outsider::Access.for(account_user).technician? ? 'technician' : 'agent'
  end

  def type_for(account_user, profile)
    return 'administrator' if account_user.administrator?

    profile&.technician? ? 'technician' : 'agent'
  end

  def pick_profile(type, profile_id)
    return nil if type == 'administrator'

    profile = profile_id.present? && Outsider::AccessProfile.find_by(account_id: @account.id, id: profile_id)
    raise Invalid, 'profile' if profile_id.present? && (!profile || profile.administrator?)

    profile || Outsider::Access::Defaults.new(@account).default_for(type)
  end

  def assign(user_id, profile)
    member = Outsider::AccessMember.find_or_initialize_by(account_id: @account.id, user_id: user_id)
    member.update!(profile: profile)
  end

  # antes de criar o usuário: ramal de 201 a 599 e livre (o cadastro não fica pela metade)
  def check_extension!(extension)
    return if extension.blank?

    taken = @settings.data['agents'].values.pluck('extension')
    raise Invalid, 'extension' unless extension.to_s.match?(Outsider::Voice::Settings::EXTENSION) && taken.exclude?(extension.to_s)
  end

  # ramal: técnico não toca nas ligações da empresa; o estado vem do número de saída. Só mexe no que veio
  def put_line(user_id, params, type, creating: false)
    attributes = params.slice('branch')
    if params.key?('extension')
      attributes['extension'] = params['extension'].to_s.strip
      attributes['enabled'] = attributes['extension'].present?
    end
    if params.key?('number')
      number = @settings.number_for(params['number'])
      attributes['number'] = number&.dig('number')
      attributes['state'] = number['state'] if number
    end
    if params.key?('inbound') then attributes['inbound'] = ActiveModel::Type::Boolean.new.cast(params['inbound'])
    elsif creating then attributes['inbound'] = type != 'technician'
    end
    @settings.put_agent(user_id, attributes)
  rescue Outsider::Voice::Settings::Invalid => e
    raise Invalid, e.errors.first.to_s.split('.').last == 'extension' ? 'extension' : 'line'
  end
end
