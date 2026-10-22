# OUTSIDER: proposta de exemplo para a pré-visualização do editor de modelos. Fica só na memória (nada é
# gravado) e usa dados fictícios de cliente, para a prévia não mostrar cliente de verdade. A máquina é a
# primeira ativa do catálogo, para aparecerem a imagem e as características; sem catálogo, um item livre.
class Outsider::Crm::ProposalSample
  CUSTOMER = {
    'company' => 'CLIENTE EXEMPLO LTDA', 'document' => '00.000.000/0001-00', 'address' => 'Rua Exemplo, 100',
    'district' => 'Centro', 'city' => 'Goiânia', 'state' => 'GO', 'zip' => '74000-000', 'phone' => '(62) 0000-0000',
    'email' => 'compras@cliente-exemplo.com.br', 'attention' => 'Fulano de Tal'
  }.freeze
  MACHINE_NAME = 'Empilhadeira 2,5t'.freeze

  def initialize(account_user, template)
    @account = account_user.account
    @user = account_user.user
    @template = template
  end

  def build
    config = Outsider::Crm::ProposalConfig.new(@account)
    proposal = Outsider::Crm::Proposal.new(
      account: @account, kind: @template.kind, template: @template, number: config.next_number, status: :draft,
      title: machine&.name || MACHINE_NAME, customer: CUSTOMER.dup, conditions: @template.conditions,
      issued_on: Time.zone.today, valid_until: Time.zone.today + @template.validity_days.days, signer: signer(config),
      notes: 'Observações da proposta aparecem aqui.'
    )
    build_items(proposal)
    proposal.recalculate_total
    proposal
  end

  private

  def machine
    return @machine if defined?(@machine)

    @machine = Outsider::Crm::Product.where(account_id: @account.id, kind: :machine, active: true).order(:id).first
  end

  def build_items(proposal)
    proposal.items.build(account: @account, product: machine, description: machine&.name || MACHINE_NAME, quantity: 1,
                         unit_price_cents: machine_price, discount_cents: 0, show_details: machine.present?,
                         details: machine&.details || {}, position: 0)
    proposal.items.build(account: @account, description: 'Frete', quantity: 1, unit_price_cents: 150_000, discount_cents: 0, position: 1)
  end

  def machine_price
    price = @template.rental? ? machine&.rental_price_cents : machine&.sale_price_cents
    price.to_i.positive? ? price : 10_000_000
  end

  def signer(config)
    signature = config.signature(@user.id)
    { 'name' => @user.name.to_s, 'title' => signature['title'], 'phone' => signature['phone'], 'email' => @user.email.to_s }
  end
end
