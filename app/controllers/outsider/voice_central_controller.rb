# OUTSIDER: o que a central de telefonia (Asterisk) chama no Chatwoot (Entrega 22). Ela busca a configuração a
# cada 30 s e pergunta o caminho de cada ligação; avisa atendimento, fim e o próprio estado. Sem sessão de
# usuário: entra só com o token OUTSIDER_VOICE_TOKEN (o mesmo no Chatwoot e na central), no cabeçalho
# X-Voice-Token ou no parâmetro token. As respostas são texto simples, lido pelo plano de discagem.
class Outsider::VoiceCentralController < ActionController::API
  MIN_TOKEN = 32

  before_action :authenticate_central
  before_action :load_settings

  def pjsip
    render plain: Outsider::Voice::CentralConfig.new(@settings).pjsip
  end

  def extensions
    render plain: Outsider::Voice::CentralConfig.new(@settings).extensions
  end

  def inbound
    render plain: router.inbound(linkedid: params.require(:linkedid), did: params[:did], to: params[:to], from: params[:from])
  end

  def outbound
    render plain: router.outbound(linkedid: params.require(:linkedid), extension: params[:extension], number: params[:number])
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
    events.hangup(linkedid: params.require(:linkedid), dialstatus: params[:dialstatus], cause: params[:cause])
    render plain: ''
  end

  def status
    Outsider::Voice::CentralStatus.new(@settings.account)
                                  .report(registration: params[:registration].to_s.first(40), extensions: params[:extensions].to_s.split(','))
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
end
