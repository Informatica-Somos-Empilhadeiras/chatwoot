# OUTSIDER: para quem a gravação de uma ligação pode ser encaminhada (Entrega 25; Outsider::Voice::RecordingForward).
# O mesmo da proposta (Outsider::Crm::ProposalRecipients: busca, contatos travados sem telefone ou e-mail, caixas
# que a pessoa atende), mas a lista começa pelo cliente da ligação.
class Outsider::Voice::RecordingRecipients < Outsider::Crm::ProposalRecipients
  def initialize(account_user, call)
    super(account_user, nil)
    @call = call
  end

  private

  def suggested
    [@call.contact].compact
  end
end
