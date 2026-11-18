# OUTSIDER (técnicos): Atender e Recusar no aviso de ligação que acorda o celular (Outsider::Voice::Wake). O service
# worker não tem a sessão da pessoa: manda o token assinado que veio no aviso (3 minutos, só aquela ligação e ramal).
# accept: a pessoa tocou para atender (a central espera mais o app abrir); decline: quem ligou ouve ocupado.
class Outsider::PushCallController < ActionController::API
  def create
    data = Outsider::Voice::Wake.token_data(params[:token])
    return head :unauthorized unless data.is_a?(Hash)

    account = Account.find_by(id: data['a'])
    return head :not_found unless account

    wake = Outsider::Voice::Wake.new(Outsider::Voice::Settings.new(account))
    entry = wake.entry(data['l'], data['t'])
    return head :gone unless entry && entry['user_id'] == data['u'] && !entry['done']

    wake.respond(linkedid: data['l'], target: data['t'], action: params[:call_action].to_s) ? head(:no_content) : head(:unprocessable_entity)
  end
end
