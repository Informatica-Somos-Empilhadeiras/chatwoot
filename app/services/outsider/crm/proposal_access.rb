# OUTSIDER: quem vê e quem mexe em quais propostas. Administrador vê e edita todas. Os demais veem as
# próprias (responsável ou quem criou) e, se o administrador liberou em Configurações > Propostas, as de
# outros agentes escolhidos ou todas. Editar é do responsável, de quem criou e do administrador.
class Outsider::Crm::ProposalAccess
  attr_reader :account_user

  def initialize(account_user)
    @account_user = account_user
  end

  def administrator?
    account_user.administrator?
  end

  def view_all?
    administrator? || rule['view'] == 'all'
  end

  # Catálogo: todos do CRM consultam; cadastrar e alterar é do administrador e de quem ele liberou
  def manage_catalog?
    administrator? || rule['catalog']
  end

  def proposals(scope = Outsider::Crm::Proposal.where(account_id: account_user.account_id))
    return scope if view_all?

    scope.where('outsider_crm_proposals.owner_id IN (:owners) OR outsider_crm_proposals.created_by_id = :user',
                owners: visible_owner_ids, user: user_id)
  end

  def view?(proposal)
    view_all? || visible_owner_ids.include?(proposal.owner_id) || proposal.created_by_id == user_id
  end

  def edit?(proposal)
    administrator? || [proposal.owner_id, proposal.created_by_id].include?(user_id)
  end

  # Conteúdo (cliente, itens, condições) muda enquanto a proposta está em aberto; aceita, recusada ou
  # cancelada fica como está (dá para voltar para rascunho)
  def edit_content?(proposal)
    edit?(proposal) && (proposal.draft? || proposal.sent?)
  end

  # Enviar ao cliente (Entrega 15): quem edita, enquanto a proposta está em aberto ou já foi aceita (reenviar)
  def send?(proposal)
    edit?(proposal) && (proposal.draft? || proposal.sent? || proposal.accepted?)
  end

  # Só rascunho nunca enviado se apaga; o resto se cancela, para não sumir do histórico
  def delete?(proposal)
    edit?(proposal) && proposal.draft? && proposal.sends.empty?
  end

  # Responsável pela proposta: o administrador escolhe qualquer pessoa da conta; os demais, só a si mesmos
  def assign_owner?
    administrator?
  end

  def as_json(*)
    { view_all: view_all?, manage_catalog: manage_catalog?, assign_owner: assign_owner? }
  end

  private

  def user_id
    account_user.user_id
  end

  def rule
    @rule ||= Outsider::Crm::ProposalConfig.new(account_user.account).access(user_id)
  end

  def visible_owner_ids
    @visible_owner_ids ||= [user_id] + (rule['view'] == 'users' ? rule['user_ids'] : [])
  end
end
