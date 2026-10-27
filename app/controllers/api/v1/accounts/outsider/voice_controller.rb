# OUTSIDER: o telefone dentro do Chatwoot (Entrega 22). me: dados para o navegador entrar na central com o
# ramal da pessoa (vazio se a telefonia ou o ramal estão desligados). lookup: quem é o número que está
# ligando, para a tela mostrar o nome e o negócio aberto antes de atender. recording: a gravação feita pelo
# telefone do navegador (Entrega 24).
class Api::V1::Accounts::Outsider::VoiceController < Api::V1::Accounts::BaseController
  def me
    agent = settings.enabled? && settings.agent_for(Current.user.id)
    return render json: { enabled: false } unless agent && settings.data['ws_url'].present?

    render json: {
      enabled: true, ws_url: settings.data['ws_url'], extension: agent['extension'], name: Current.user.name,
      password: settings.sip_password(Current.user.id, agent['extension']), echo_extension: ::Outsider::Voice::Settings::ECHO_EXTENSION,
      recording: settings.recording?
    }
  end

  def lookup
    contact = ::Outsider::Voice::PhoneNumber.find_contact(Current.account, params[:number])
    return render json: { contact: nil } unless contact

    render json: { contact: contact.slice(:id, :name, :phone_number).merge(thumbnail: contact.avatar_url), deal: deal_json(contact),
                   conversation_id: contact.conversations.order(last_activity_at: :desc).pick(:display_id) }
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

  private

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

  # só o negócio que a pessoa pode ver no CRM
  def deal_json(contact)
    access = ::Outsider::Crm::Access.new(Current.account_user)
    return unless access.enabled?

    deal = ::Outsider::Crm::Opportunity.where(account_id: Current.account.id, contact_id: contact.id).open
                                       .includes(:stage, :owner).order(updated_at: :desc).find { |item| access.view_opportunity?(item) }
    deal && { id: deal.id, title: deal.title, value_cents: deal.value_cents, stage: deal.stage.name, owner: deal.owner&.name }
  end
end
