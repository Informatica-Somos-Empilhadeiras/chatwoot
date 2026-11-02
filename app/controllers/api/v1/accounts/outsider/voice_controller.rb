# OUTSIDER: o telefone dentro do Chatwoot (Entrega 22). me: dados para o navegador entrar na central com o
# ramal da pessoa (vazio se a telefonia ou o ramal estão desligados). lookup: quem é o número que está
# ligando, para a tela mostrar o nome e o negócio aberto antes de atender. recording: a gravação feita pelo
# telefone do navegador (Entrega 24).
#
# Entrega 26: lookup traz também os negócios abertos do cliente e por onde ele passou na URA; call liga a
# ligação em andamento a um contato (cadastro criado na hora) ou a um negócio; signal leva os avisos do sussurro
# entre os telefones (Outsider::Voice::Signals); supervisor diz se a pessoa pode monitorar ligações.
class Api::V1::Accounts::Outsider::VoiceController < Api::V1::Accounts::BaseController
  DEALS_LIMIT = 10
  IVR_RECENT = 15.minutes

  def me
    agent = settings.enabled? && settings.agent_for(Current.user.id)
    return render json: { enabled: false } unless agent && settings.data['ws_url'].present?

    render json: {
      enabled: true, ws_url: settings.data['ws_url'], extension: agent['extension'], name: Current.user.name, user_id: Current.user.id,
      password: settings.sip_password(Current.user.id, agent['extension']), echo_extension: ::Outsider::Voice::Settings::ECHO_EXTENSION,
      supervisor: crm_access.enabled? && crm_access.manager?
    }.merge(recording_flags)
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
    render json: User.where(id: agents.keys).order(:name).map { |user|
      extension = agents[user.id]['extension']
      { id: user.id, name: user.name, thumbnail: user.avatar_url, extension: extension, state: agents[user.id]['state'],
        online: online.include?(extension) }
    }
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
