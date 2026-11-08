# OUTSIDER: endereços públicos do "Conectar meu Teams" (sem sessão do Chatwoot).
#   POST /outsider/teams/graph/notifications: avisos de mensagem nova da Microsoft. Na criação da assinatura a Microsoft
#     manda validationToken e espera o mesmo texto de volta. Cada aviso só vale se o clientState for o da assinatura;
#     a mensagem em si é buscada depois no Graph com o token do colaborador (Outsider::Teams::Graph::ReceiveJob).
#   POST /outsider/teams/graph/lifecycle: avisos de ciclo de vida (renovar, assinatura removida).
#   GET  /outsider/teams/oauth/callback: volta do login da Microsoft; só repassa o código para a tela do Chatwoot, que
#     termina o login com a sessão da pessoa (o state assinado diz a conta).
class Outsider::TeamsGraphWebhooksController < ActionController::API
  def notifications
    return validation if params[:validationToken].present?

    each_notification do |subscription, item|
      Outsider::Teams::Graph::ReceiveJob.set(wait: 3.seconds).perform_later(subscription.id, item['resource'].to_s,
                                                                            item['changeType'].to_s)
    end
    head :accepted
  end

  def lifecycle
    return validation if params[:validationToken].present?

    each_notification do |subscription, item|
      Outsider::Teams::Graph::LifecycleJob.perform_later(subscription.id, item['lifecycleEvent'].to_s)
    end
    head :accepted
  end

  def callback
    state = Outsider::Teams::Graph::Login.read_state(params[:state])
    site = Outsider::Teams::Graph::Login.site
    return redirect_to("#{site}/app", allow_other_host: true) unless state

    query = params.permit(:code, :state, :error, :error_description, :admin_consent).to_h
    redirect_to("#{site}/app/accounts/#{state['a'].to_i}/settings/outsider/teams?#{{ teams_oauth: query }.to_query}",
                allow_other_host: true)
  end

  private

  def validation
    render plain: params[:validationToken].to_s.first(1024), content_type: 'text/plain'
  end

  def each_notification
    payload = JSON.parse(request.raw_post.presence || '{}')
    Array(payload.is_a?(Hash) ? payload['value'] : nil).first(200).each do |item|
      next unless item.is_a?(Hash)

      subscription = Outsider::TeamsSubscription.find_by(subscription_id: item['subscriptionId'].to_s)
      next unless subscription && ActiveSupport::SecurityUtils.secure_compare(subscription.client_state, item['clientState'].to_s)

      yield subscription, item
    end
  rescue JSON::ParserError
    nil
  end
end
