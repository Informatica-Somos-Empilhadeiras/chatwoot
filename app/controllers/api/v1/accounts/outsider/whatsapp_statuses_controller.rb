# OUTSIDER: página Status do WhatsApp (ver app/services/outsider/whatsapp_status_service.rb).
# Ver e listar: quem tem acesso à caixa. Publicar e republicar: administradores e os agentes
# que eles liberarem (ver app/services/outsider/whatsapp_status_permissions.rb).
class Api::V1::Accounts::Outsider::WhatsappStatusesController < Api::V1::Accounts::BaseController
  PERIODS = [1, 7, 30].freeze
  FONTS = [1, 2].freeze
  DEFAULT_BACKGROUND = '#128C7E'.freeze
  # A Evolution só responde depois de enviar o status para todos. Com muitos contatos isso
  # passa do limite de tempo da requisição, então depois de SEND_TIMEOUT respondemos
  # "pending" e a Evolution continua o envio sozinha.
  SEND_TIMEOUT = 8

  before_action :fetch_inbox, except: [:inboxes, :permissions, :update_permission]
  before_action :check_admin_authorization?, only: [:permissions, :update_permission]
  before_action :check_create_permission, only: [:create]
  before_action -> { check_status_permission('republish') }, only: [:republish]

  rescue_from ::Outsider::EvolutionApi::Error do |error|
    render json: { error: error.code, message: error.message }, status: :unprocessable_entity
  end

  def inboxes
    inboxes = Current.user.assigned_inboxes.where(channel_type: 'Channel::Api').includes(:channel)
                     .select { |inbox| ::Outsider::EvolutionApi.evolution_inbox?(inbox) }
    render json: {
      configured: ::Outsider::EvolutionApi.configured?,
      administrator: Current.account_user.administrator?,
      permissions: status_permissions.for_user(Current.account_user),
      payload: inboxes.map { |inbox| { id: inbox.id, name: inbox.name } }
    }
  end

  def index
    render json: service.contacts
  end

  def mine
    period = PERIODS.include?(params[:period].to_i) ? params[:period].to_i : 7
    render json: service.mine(since: period.days.ago)
  end

  def media
    media = service.media(params.require(:id))
    expires_in 1.day
    send_data Base64.decode64(media['base64']), type: media['mimetype'], disposition: 'inline'
  end

  # a resposta a um status chega na conversa só com o id do status (ver app/models/outsider/message_reply_link.rb)
  def replied_status
    render json: service.replied_status(params.require(:id))
  end

  # quem viu um dos meus status (só com a Evolution ajustada, ver whatsapp_status_service.rb)
  def viewers
    render json: { payload: service.viewers(params.require(:id)) }
  end

  def audience
    render json: service.audience.summary
  end

  # contatos para escolher quem vê: busca e DDDs; com all_ids, só os ids de todos os achados
  def audience_contacts
    query = params[:q].to_s
    areas = Array(params[:areas]).map(&:to_s)
    return render json: { ids: service.audience.ids(query: query, areas: areas) } if params[:all_ids].present?

    render json: service.audience.search(query: query, areas: areas, page: [params[:page].to_i, 1].max)
  end

  def create
    type = params.require(:type)
    payload = case type
              when 'text'
                service.text_payload(params.require(:text), background_color, FONTS.include?(params[:font].to_i) ? params[:font].to_i : 1)
              when 'image', 'video'
                file = params.require(:file)
                service.media_payload(type, file.content_type, file.read, params[:caption])
              end
    return head :unprocessable_entity if payload.nil?

    publish(payload)
  end

  def republish
    publish(service.republish_payload(params.require(:id), background_color))
  end

  def permissions
    render json: Current.account.account_users.includes(:user).map { |account_user|
      user = account_user.user
      { id: user.id, name: user.available_name, email: user.email, avatar_url: user.avatar_url,
        administrator: account_user.administrator?, permissions: status_permissions.for_user(account_user) }
    }
  end

  def update_permission
    permission = params.require(:permission)
    return head :unprocessable_entity unless ::Outsider::WhatsappStatusPermissions::ALL.include?(permission)

    # administradores sempre podem tudo, então só agentes mudam
    account_user = Current.account.account_users.agent.find_by!(user_id: params.require(:user_id))
    status_permissions.update(account_user.user_id, permission, ActiveModel::Type::Boolean.new.cast(params[:allowed]))
    head :no_content
  end

  private

  def status_permissions
    @status_permissions ||= ::Outsider::WhatsappStatusPermissions.new(Current.account)
  end

  def check_status_permission(permission)
    raise Pundit::NotAuthorizedError unless status_permissions.allowed?(Current.account_user, permission)
  end

  # "Editar e publicar de novo" manda edit_of com o id do status antigo
  def check_create_permission
    return if status_permissions.allowed?(Current.account_user, 'publish')

    check_status_permission(params[:edit_of].present? ? 'edit' : 'publish')
  end

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params.require(:inbox_id))
    authorize @inbox, :show?
    raise ActiveRecord::RecordNotFound unless ::Outsider::EvolutionApi.evolution_inbox?(@inbox)
  end

  def service
    @service ||= ::Outsider::WhatsappStatusService.new(@inbox)
  end

  def background_color
    params[:background_color].to_s.match?(/\A#\h{6}\z/) ? params[:background_color] : DEFAULT_BACKGROUND
  end

  # sem audience vai para todos os contatos da caixa; "selected" para os contatos escolhidos
  # na lista; "numbers" para números digitados
  def audience_jids
    case params[:audience]
    when 'selected' then service.audience.jids_for(Array(params[:contact_ids]))
    when 'numbers' then service.audience.resolve_numbers(Array(params[:numbers]))
    else service.audience.jids
    end
  end

  def publish(payload)
    jids = audience_jids
    return render json: { error: 'empty_audience' }, status: :unprocessable_entity if jids.empty?

    # o próprio número entra na lista para o status aparecer também no celular da empresa
    response = service.publish(payload.merge(statusJidList: (jids + [service.owner_jid]).compact.uniq), timeout: SEND_TIMEOUT)
    render json: { id: response.dig('key', 'id'), pending: false }, status: :created
  rescue ::Outsider::EvolutionApi::Error => e
    raise unless e.code == 'evolution_timeout'

    render json: { pending: true }, status: :accepted
  end
end
