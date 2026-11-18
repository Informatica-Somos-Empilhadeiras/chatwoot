# OUTSIDER: o telefone dentro do Chatwoot (Entrega 22). me: dados para o navegador entrar na central com o
# ramal da pessoa (vazio se a telefonia ou o ramal estão desligados). lookup: quem é o número que está
# ligando, para a tela mostrar o nome e o negócio aberto antes de atender. recording: a gravação feita pelo
# telefone do navegador (Entrega 24).
#
# Entrega 26: lookup traz também os negócios abertos do cliente e por onde ele passou na URA; call liga a
# ligação em andamento a um contato (cadastro criado na hora) ou a um negócio; signal leva os avisos do sussurro
# entre os telefones (Outsider::Voice::Signals); supervisor diz se a pessoa pode monitorar ligações.
#
# OUTSIDER (técnicos): o telefone segue o perfil de acesso (Configurações > Perfis de acesso): sem "Telefone", me volta
# desligado e o resto recusa; me traz também os números de saída ("Sair com") e o tipo da pessoa; team diz a filial,
# quem está em ligação e quem atende pelo aviso no celular; recent são as ligações da própria pessoa (aba Recentes).
class Api::V1::Accounts::Outsider::VoiceController < Api::V1::Accounts::BaseController
  DEALS_LIMIT = 10
  IVR_RECENT = 15.minutes
  RECENT_LIMIT = 60

  before_action :check_phone_access, except: [:me]

  def me
    agent = settings.enabled? && phone_access? && settings.agent_for(Current.user.id)
    return render json: { enabled: false } unless agent && settings.data['ws_url'].present?

    render json: {
      enabled: true, ws_url: settings.data['ws_url'], extension: agent['extension'], name: Current.user.name, user_id: Current.user.id,
      password: settings.sip_password(Current.user.id, agent['extension']), echo_extension: ::Outsider::Voice::Settings::ECHO_EXTENSION,
      supervisor: crm_access.enabled? && crm_access.manager? && access.allows?('voice_monitor', 'use')
    }.merge(recording_flags).merge(line_info(agent))
  end

  def lookup
    contact = ::Outsider::Voice::PhoneNumber.find_contact(Current.account, params[:number])
    ivr = recent_ivr(params[:number])
    return render json: { contact: nil, ivr: ivr } unless contact

    deals = visible_deals(contact)
    render json: { contact: contact.slice(:id, :name, :phone_number).merge(thumbnail: contact.avatar_url), deal: deals.first, deals: deals,
                   conversation_id: contact.conversations.order(last_activity_at: :desc).pick(:display_id), ivr: ivr }
  end

  # colegas com ramal ligado, para ligar ou transferir (Entrega 23): online = telefone conectado na central
  def team
    agents = settings.enabled? ? settings.enabled_agents : {}
    online = ::Outsider::Voice::CentralStatus.new(Current.account).to_h[:extensions]
    busy = busy_user_ids
    wakeable = NotificationSubscription.browser_push.where(user_id: agents.keys).distinct.pluck(:user_id)
    render json: User.where(id: agents.keys).order(:name).map { |user|
      agent = agents[user.id]
      { id: user.id, name: user.name, thumbnail: user.avatar_url, extension: agent['extension'], state: agent['state'],
        online: online.include?(agent['extension']), branch: settings.branch_for(user.id)&.dig('name'), in_call: busy.include?(user.id),
        wakeable: wakeable.include?(user.id), availability: user.account_users.find { |au| au.account_id == Current.account.id }&.availability }
    }
  end

  # ligações da pessoa: as que ela fez ou atendeu com cliente e as internas de e para o ramal dela (perdidas inclusive)
  def recent
    extension = settings.agent_for(Current.user.id)&.dig('extension')
    scope = ::Outsider::Voice::Call.where(account_id: Current.account.id, started_at: 30.days.ago..)
    mine = scope.external.where(user_id: Current.user.id)
    mine = mine.or(scope.internal.where(to_number: extension)).or(scope.internal.where(from_number: extension)) if extension
    calls = mine.includes(:contact).order(started_at: :desc).limit(RECENT_LIMIT).to_a
    render json: calls.map { |call| recent_row(call, extension) }
  end

  # gravação do telefone, no fim da ligação (Outsider::Voice::Recording)
  def recording
    file = params.require(:file)
    recording = ::Outsider::Voice::Recording.new(settings, Current.user)
    return head :forbidden unless recording.allowed?
    return head :unprocessable_entity unless recording.valid_file?(file)

    call = recording.attach(file: file, parties: recording_parties)
    call ? render(json: { id: call.id }) : head(:not_found)
  end

  # a ligação em andamento (ou que acabou de acabar), achada pelo número e pela hora em que começou no telefone:
  # contact_id liga ao cadastro do cliente; opportunity_id (vazio desliga) ao negócio
  def update_call
    call = current_call
    return head :not_found unless call

    call.update!(contact: contact_param) if params.key?(:contact_id)
    if params.key?(:opportunity_id)
      deal = params[:opportunity_id].present? ? deal_link.deal(params[:opportunity_id]) : nil
      return head :not_found if params[:opportunity_id].present? && deal.nil?

      deal_link.link(call, deal)
    end
    render json: { id: call.id, contact_id: call.contact_id, opportunity: call.opportunity && deal_row(call.opportunity) }
  end

  def signal
    ::Outsider::Voice::Signals.new(settings, Current.user)
                              .deliver(type: params.require(:type), to_user_id: params.require(:to_user_id), data: params[:data]&.permit!.to_h || {})
    head :no_content
  rescue ::Outsider::Voice::Signals::Refused => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def access
    @access ||= ::Outsider::Access.for(Current.account_user)
  end

  def phone_access?
    access.allows?('phone', 'use')
  end

  def check_phone_access
    render json: { error: 'forbidden', outsider_access: 'phone' }, status: :forbidden unless phone_access?
  end

  # "Sair com": o número de saída de hoje e os que a pessoa pode escolher (todos os da empresa); sem "Sair com número
  # da empresa" no perfil, o telefone só liga para ramais
  def line_info(agent)
    line = settings.line_for(agent)
    outbound = access.allows?('phone_outbound', 'use')
    { outbound: outbound, line: outbound ? line&.slice('number', 'state', 'label') : nil,
      lines: outbound ? settings.numbers.map { |row| row.slice('number', 'state', 'label') } : [],
      kind: access.kind, branch: settings.branch_for(Current.user.id)&.dig('name') }
  end

  # quem está numa ligação agora (tocando ou falando, começou nas últimas 4 horas)
  def busy_user_ids
    ::Outsider::Voice::Call.where(account_id: Current.account.id, ended_at: nil, started_at: 4.hours.ago..)
                           .where.not(answered_at: nil).distinct.pluck(:user_id).compact
  end

  def recent_row(call, extension)
    incoming = call.internal? ? call.to_number == extension : call.inbound?
    number = incoming ? call.from_number : call.to_number
    colleague = call.internal? ? colleague_for(number) : nil
    { id: call.id, direction: incoming ? 'in' : 'out', internal: call.internal?, status: call.status, number: number,
      name: colleague&.name || call.contact&.name, thumbnail: colleague&.avatar_url || call.contact&.avatar_url,
      started_at: call.started_at, talk_seconds: call.talk_seconds,
      missed: incoming && call.answered_at.nil? && call.ended_at.present? && !call.busy? }
  end

  def colleague_for(extension)
    user_id = settings.user_id_for_extension(extension)
    @colleagues ||= {}
    @colleagues[user_id] ||= user_id && Current.account.users.find_by(id: user_id)
  end

  # botão Gravar e gravação automática (Entregas 24 e 25)
  def recording_flags
    { recording: settings.recording?, auto_record: settings.auto_record? }
  end

  # [{ "number", "started_at" }], vindo do navegador como JSON
  def recording_parties
    parties = JSON.parse(params[:parties].to_s)
    parties.is_a?(Array) ? parties.select { |party| party.is_a?(Hash) }.first(10) : []
  rescue JSON::ParserError
    []
  end

  def settings
    @settings ||= ::Outsider::Voice::Settings.new(Current.account)
  end

  def crm_access
    @crm_access ||= ::Outsider::Crm::Access.new(Current.account_user)
  end

  def deal_link
    @deal_link ||= ::Outsider::Voice::DealLink.new(Current.account_user)
  end

  def current_call
    ::Outsider::Voice::CallMatch.new(settings, Current.user)
                                .find(params[:number].to_s.delete('^0-9'), ::Outsider::Voice::CallMatch.time(params[:started_at]))
  end

  def contact_param
    params[:contact_id].present? ? Current.account.contacts.find(params[:contact_id]) : nil
  end

  # os negócios abertos do cliente que a pessoa pode ver no CRM, o mais mexido primeiro
  def visible_deals(contact)
    return [] unless crm_access.enabled?

    ::Outsider::Crm::Opportunity.where(account_id: Current.account.id, contact_id: contact.id).open
                                .includes(:stage, :owner).order(updated_at: :desc)
                                .select { |item| crm_access.view_opportunity?(item) }.first(DEALS_LIMIT).map { |deal| deal_row(deal) }
  end

  def deal_row(deal)
    { id: deal.id, title: deal.title, code: deal.code, value_cents: deal.value_cents, stage: deal.stage&.name, owner: deal.owner&.name }
  end

  # o que o cliente escolheu e digitou na URA nesta ligação (a recebida mais recente desse número)
  def recent_ivr(number)
    ::Outsider::Voice::Call.where(account_id: Current.account.id, direction: :inbound, started_at: IVR_RECENT.ago..)
                           .where.not(ivr_flow_id: nil).order(started_at: :desc).limit(20)
                           .find { |call| ::Outsider::Voice::PhoneNumber.same?(call.from_number, number) }&.ivr_summary
  end
end
