# OUTSIDER: enviar a proposta ao cliente por WhatsApp ou e-mail (Outsider::Crm::ProposalSender).
# new: contatos sugeridos (ou a busca, com q), caixas, textos padrão e os valores das variáveis.
class Api::V1::Accounts::Outsider::Crm::ProposalSendsController < Api::V1::Accounts::Outsider::Crm::ProposalBaseController
  before_action :fetch_proposal

  def new
    return render json: { contacts: recipients.contacts(params[:q]) } if params.key?(:q)

    render json: {
      contacts: recipients.contacts,
      inboxes: inboxes,
      system_email: recipients.system_email?,
      texts: ::Outsider::Crm::ProposalConfig.new(Current.account).effective_send_texts,
      variables: variables
    }
  end

  def create
    sender.deliver(@proposal, params.permit(:channel, :contact_id, :inbox_id, :message, :subject))
    render json: ::Outsider::Crm::ProposalSerializer.proposal(@proposal.reload, access: proposal_access), status: :created
  rescue ::Outsider::Crm::ProposalSender::Blocked => e
    # aqui dentro, e não num rescue_from, para a mensagem sair no idioma da conta
    render json: { error: e.message, message: I18n.t("outsider_crm.proposals.send.errors.#{e.message}") }, status: :unprocessable_entity
  end

  private

  def fetch_proposal
    @proposal = proposal_access.proposals.find_by(id: params[:proposal_id])
    return head :not_found if @proposal.nil?

    render_forbidden unless proposal_access.send?(@proposal)
  end

  def recipients
    @recipients ||= ::Outsider::Crm::ProposalRecipients.new(Current.account_user, @proposal)
  end

  def sender
    ::Outsider::Crm::ProposalSender.new(Current.account_user)
  end

  def inboxes
    { whatsapp: recipients.whatsapp_inboxes.map { |inbox| recipients.inbox_row(inbox) },
      email: recipients.email_inboxes.map { |inbox| recipients.inbox_row(inbox) } }
  end

  # {contato} é trocado na tela, pelo contato escolhido
  def variables
    company = ::Outsider::Crm::ProposalConfig.new(Current.account).company(@proposal.business_unit_id)
    { numero: @proposal.number.to_s, titulo: @proposal.title, vendedor: (@proposal.owner || Current.user).name,
      empresa: company['trade_name'].presence || company['legal_name'].to_s }
  end
end
