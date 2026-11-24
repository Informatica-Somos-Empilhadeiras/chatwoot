# OUTSIDER: volta do login do Google (bloco Google dos Aplicativos), sem sessão do Chatwoot. Só repassa o código para a
# tela Configurações > Google, que termina o login com a sessão da pessoa (o state assinado diz a conta e a pessoa).
class Outsider::GoogleOauthController < ActionController::API
  def callback
    state = Outsider::Apps::Google::Login.read_state(params[:state])
    site = Outsider::Apps::Google::Login.site
    return redirect_to("#{site}/app", allow_other_host: true) unless state

    query = params.permit(:code, :state, :error).to_h
    redirect_to("#{site}/app/accounts/#{state['a'].to_i}/settings/outsider/google?#{{ google_oauth: query }.to_query}",
                allow_other_host: true)
  end
end
