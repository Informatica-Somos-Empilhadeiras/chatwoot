# OUTSIDER: perfis de acesso por tela, no estilo dos ERPs (Configurações > Perfis de acesso).
#
# - Cada pessoa tem um perfil (Outsider::AccessProfile); sem perfil escolhido, vale o perfil padrão do tipo dela.
# - Os perfis prontos são Administrador (tudo), Agente e Técnico (só o telefone, para mecânicos e colaboradores de
#   outras unidades); o administrador duplica e cria outros.
# - Tela por tela: Não vê (some do menu, a rota volta para o início e a API recusa), Vê (abre, mas a API recusa
#   gravar), Usa (como o papel do Chatwoot permite) e Gerencia (só onde há algo a mais, ex.: ouvir qualquer ligação).
# - O perfil só tira: administrador do Chatwoot continua com tudo, agente nunca vira administrador.
# - O superadministrador escolhe, por conta, telas que só administradores abrem (Outsider::Access::AccountCeiling).
# Peças: Catalog (as telas), Resolver (o acesso de uma pessoa), ApiGuard (a API recusa), Defaults (perfis prontos),
# People (cadastro de técnico com ramal).
module Outsider::Access
  ADMIN_ONLY_KEY = 'outsider_access_admin_only'.freeze

  module_function

  def for(account_user)
    Outsider::Access::Resolver.new(account_user)
  end
end
