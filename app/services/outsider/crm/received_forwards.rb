# OUTSIDER: negócios que chegaram por encaminhamento para o usuário, para o aviso na tela (janela
# que só fecha no botão e bolinha vermelha no menu do CRM). Recebe quem é o responsável do negócio
# no destino; sem responsável, todos da unidade destino, vendedores e gestores, para um deles pegar
# (unidade sem ninguém: os administradores). Quando alguém pega, o aviso some para os outros.
# Quem encaminhou não recebe o aviso do próprio encaminhamento.
#
# Sem tabela nova: quem já fechou o aviso (notified) e quem já abriu o negócio (opened) fica no
# metadata da atividade "recebido" do negócio. Só entram negócios ainda abertos, dos últimos dias.
class Outsider::Crm::ReceivedForwards
  DAYS = 14
  LIMIT = 30
  MARKS = %w[notified opened].freeze

  def initialize(access, user)
    @access = access
    @user = user
    @account_id = access.account_user.account_id
  end

  # Só o que a pessoa ainda não abriu; notified diz se a janela já foi fechada
  def items
    activities.reject { |activity| marked?(activity, 'opened') }.map { |activity| item(activity) }
  end

  # opened também conta como notified: abriu o negócio, não precisa mais da janela
  def mark(opportunity_ids, opened:)
    fields = opened ? MARKS : ['notified']
    activities.select { |activity| opportunity_ids.map(&:to_i).include?(activity.opportunity_id) }.each do |activity|
      activity.with_lock do
        metadata = activity.metadata.to_h
        fields.each { |field| metadata[field] = (Array(metadata[field]) | [@user.id]) }
        activity.update!(metadata: metadata)
      end
    end
  end

  private

  def activities
    @activities ||= Outsider::Crm::Activity.received.joins(:opportunity)
                                           .where(account_id: @account_id, created_at: DAYS.days.ago..)
                                           .where(outsider_crm_opportunities: { status: Outsider::Crm::Opportunity.statuses[:open] })
                                           .where(recipient_sql)
                                           .where('outsider_crm_activities.user_id IS NULL OR outsider_crm_activities.user_id <> ?', @user.id)
                                           .includes(opportunity: [:contact, :business_unit, :conversation]).includes(:user)
                                           .order(created_at: :desc).limit(LIMIT).to_a
  end

  def recipient_sql
    owned = Outsider::Crm::Activity.sanitize_sql(['outsider_crm_opportunities.owner_id = ?', @user.id])
    units = pool_unit_ids
    return owned if units.empty?

    unowned = Outsider::Crm::Activity.sanitize_sql(['(outsider_crm_opportunities.owner_id IS NULL AND ' \
                                                    'outsider_crm_opportunities.business_unit_id IN (?))', units])
    "(#{owned} OR #{unowned})"
  end

  def pool_unit_ids
    ids = @access.member_unit_ids
    return ids unless @access.administrator?

    # quem saiu da conta não conta: a unidade dele também cai no administrador
    in_account = AccountUser.where(account_id: @account_id).select(:user_id)
    with_members = Outsider::Crm::BusinessUnitMember.where(account_id: @account_id, user_id: in_account).select(:business_unit_id)
    ids + Outsider::Crm::BusinessUnit.where(account_id: @account_id).where.not(id: with_members).pluck(:id)
  end

  def marked?(activity, field)
    Array(activity.metadata.to_h[field]).include?(@user.id)
  end

  def item(activity)
    opportunity = activity.opportunity
    metadata = activity.metadata.to_h
    {
      opportunity_id: opportunity.id, code: opportunity.code, title: opportunity.title, value_cents: opportunity.value_cents,
      contact_name: opportunity.contact&.name, to_unit: opportunity.business_unit.name, owner_id: opportunity.owner_id,
      conversation_display_id: opportunity.conversation&.display_id,
      from_unit: metadata['from_unit'], from_owner: metadata['from_owner'], reason: metadata['reason'], rule: metadata['rule'],
      notes: activity.body, by: activity.user&.name, received_at: activity.created_at, notified: marked?(activity, 'notified'),
      can_claim: @access.claim_opportunity?(opportunity)
    }
  end
end
