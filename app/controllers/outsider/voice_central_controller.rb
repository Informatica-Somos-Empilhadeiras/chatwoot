# OUTSIDER: o que a central de telefonia (Asterisk) chama no Chatwoot (Entrega 22). Ela busca a configuração a
# cada 30 s e pergunta o caminho de cada ligação; avisa atendimento, fim e o próprio estado. Sem sessão de
# usuário: entra só com o token OUTSIDER_VOICE_TOKEN (o mesmo no Chatwoot e na central), no cabeçalho
# X-Voice-Token ou no parâmetro token. As respostas são texto simples, lido pelo plano de discagem.
#
# Entrega 26: URA (ivr: o próximo passo; prompts e prompt: os áudios; voicemail: o recado gravado) e monitoria
# (monitor: se a pessoa pode ouvir ou sussurrar na ligação de um ramal).
class Outsider::VoiceCentralController < ActionController::API
  MIN_TOKEN = 32
  MAX_VOICEMAIL = 20.megabytes

  # a configuração tem a senha da operadora e muda a cada salvamento: nenhum proxy (Cloudflare...) pode guardar
  before_action { response.headers['Cache-Control'] = 'no-store' }
  before_action :authenticate_central
  before_action :load_settings

  def pjsip
    render plain: Outsider::Voice::CentralConfig.new(@settings).pjsip
  end

  def extensions
    Outsider::Voice::CentralStatus.new(@settings.account).dialplan_seen!
    render plain: Outsider::Voice::CentralConfig.new(@settings).extensions
  end

  def inbound
    render plain: router.inbound(linkedid: params.require(:linkedid), did: params[:did], to: params[:to], from: params[:from])
  end

  def outbound
    render plain: router.outbound(linkedid: params.require(:linkedid), extension: params[:extension], number: params[:number],
                                  deal: params[:deal])
  end

  def internal
    router.internal(linkedid: params.require(:linkedid), extension: params[:extension], target: params[:target])
    render plain: ''
  end

  def answered
    events.answered(linkedid: params.require(:linkedid), endpoint: params[:endpoint])
    render plain: ''
  end

  def hangup
    linkedid = params.require(:linkedid)
    events.hangup(linkedid: linkedid, dialstatus: params[:dialstatus], cause: params[:cause])
    monitor_access.finish(linkedid)
    render plain: ''
  end

  def ivr
    call = ::Outsider::Voice::Call.find_by(account_id: @settings.account.id, linkedid: params.require(:linkedid))
    return render plain: '' unless call

    render plain: ::Outsider::Voice::IvrRunner.new(@settings, call).step(node_id: params[:node], input: params[:input],
                                                                         dialstatus: params[:dialstatus])
  end

  # só a central da Entrega 26 em diante busca a lista: é o sinal de que ela já conhece a URA
  def prompts
    Outsider::Voice::CentralStatus.new(@settings.account).prompts_seen!
    render plain: ivr_prompts.manifest
  end

  def prompt
    audio = ivr_prompts.fetch(params[:name])
    audio ? send_data(audio.first, type: audio.last, disposition: 'inline') : head(:not_found)
  end

  # recado da URA, enviado pela central depois que a ligação acaba de gravar
  def voicemail
    call = ::Outsider::Voice::Call.find_by(account_id: @settings.account.id, linkedid: params.require(:linkedid))
    file = params[:file]
    return head :unprocessable_entity unless call && file.respond_to?(:size) && file.size.between?(1, MAX_VOICEMAIL)

    call.voicemail.attach(io: file, filename: "recado-#{call.id}.wav", content_type: 'audio/wav')
    ::Outsider::Crm::LiveUpdates.broadcast(@settings.account.id, 'call', id: call.id, user_id: call.user_id, contact_id: call.contact_id)
    head :ok
  end

  def monitor
    render plain: monitor_access.authorize(linkedid: params.require(:linkedid), extension: params[:extension], target: params[:target],
                                           mode: params[:mode].to_s)
  end

  def status
    Outsider::Voice::CentralStatus.new(@settings.account)
                                  .report(registration: params[:registration].to_s.first(40), extensions: params[:extensions].to_s.split(','),
                                          version: params[:version].to_i.nonzero?, audio: params[:audio] == 'yes')
    render plain: ''
  end

  private

  def authenticate_central
    token = ENV.fetch('OUTSIDER_VOICE_TOKEN', '')
    given = request.headers['X-Voice-Token'].presence || params[:token].to_s
    head :not_found unless token.length >= MIN_TOKEN && ActiveSupport::SecurityUtils.secure_compare(given, token)
  end

  def load_settings
    @settings = Outsider::Voice::Settings.new(Account.find(params[:account_id]))
  end

  def router
    Outsider::Voice::Router.new(@settings)
  end

  def events
    Outsider::Voice::CallEvents.new(@settings)
  end

  def monitor_access
    Outsider::Voice::MonitorAccess.new(@settings)
  end

  def ivr_prompts
    Outsider::Voice::IvrPrompts.new(@settings.account)
  end
end
