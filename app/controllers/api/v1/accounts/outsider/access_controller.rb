# OUTSIDER: o acesso da pessoa logada, tela por tela (Outsider::Access): o menu, as rotas e a tela inicial do painel
# seguem isto. Todos da conta leem o próprio.
class Api::V1::Accounts::Outsider::AccessController < Api::V1::Accounts::BaseController
  def show
    render json: ::Outsider::Access.for(Current.account_user).as_json.merge(catalog: ::Outsider::Access::Catalog.as_json)
  end
end
