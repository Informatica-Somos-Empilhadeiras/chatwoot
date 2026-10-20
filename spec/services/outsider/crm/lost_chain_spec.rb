require 'rails_helper'

RSpec.describe Outsider::Crm::LostChain do
  # repasse em sequência: perdido numa unidade segue para a próxima da ordem, até acabar
  let(:account) { create(:account) }
  let(:matriz) { crm_unit(account, name: 'Matriz') }
  let(:df) { crm_unit(account, name: 'Filial DF') }
  let(:go) { crm_unit(account, name: 'Filial GO') }
  let(:pipelines) { [matriz, df, go].index_with { |unit| crm_pipeline(account, unit, name: 'Vendas Diretas') } }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:ana) { create(:user, account: account, role: :agent) }
  let(:bia) { create(:user, account: account, role: :agent) }
  let(:settings) { Outsider::Crm::Settings.new(account) }
  let(:no_stock) { Outsider::Crm::LostReason.create!(account: account, name: 'Sem estoque', kind: :lost) }
  let(:gave_up) { Outsider::Crm::LostReason.create!(account: account, name: 'Cliente desistiu', kind: :lost) }

  before do
    pipelines
    matriz.members.create!(account: account, user: seller, role: :seller)
    df.members.create!(account: account, user: ana, role: :seller)
    df.members.create!(account: account, user: bia, role: :seller)
  end

  def chain(**options)
    settings.update({ chain_enabled: true, chain_unit_ids: [matriz.id, df.id, go.id] }.merge(options))
  end

  def deal(unit = matriz, **attrs)
    crm_opportunity(account, unit, pipeline: pipelines[unit], owner: seller, value_cents: 90_000, **attrs)
  end

  def lose(opportunity, reason = no_stock)
    opportunity.update!(status: :lost, lost_reason: reason)
    opportunity.reload
  end

  def next_deal(opportunity)
    opportunity.reload.outgoing_forward&.to_opportunity
  end

  def summary(opportunity)
    opportunity.activities.automation.order(:id).last&.metadata
  end

  it 'does nothing while it is off' do
    expect(lose(deal).status).to eq('lost')
  end

  it 'passes the lost deal to the next unit, without an owner, and keeps the origin lost and locked' do
    chain
    origin = lose(deal)

    target = next_deal(origin)
    expect(origin).to have_attributes(status: 'lost', lost_reason_id: no_stock.id, handed_off?: true)
    expect(Outsider::Crm::Access.new(account.account_users.first).edit_opportunity?(origin)).to be(false)
    expect(Outsider::Crm::Serializer.opportunity(origin)[:forwarded_to]).to include(code: target.code)
    expect(target).to have_attributes(business_unit_id: df.id, owner_id: nil, status: 'open', value_cents: 90_000,
                                      journey_id: origin.journey_id)
    expect(target.tasks).to be_empty
    expect(target.activities.received.last.metadata).to include('rule' => I18n.t('outsider_crm.chain.rule_name'), 'from_unit' => 'Matriz')
    expect(summary(origin)).to include('rule' => 'chain', 'forwarded' => include('unit' => 'Filial DF', 'code' => target.code))
  end

  it 'keeps going unit by unit until every unit was tried, wrapping around the order' do
    chain(max_forward_attempts: 5)
    first = lose(deal(df))
    second = lose(next_deal(first))
    third = lose(next_deal(second))

    expect([first, second, third].map(&:business_unit_id)).to eq([df.id, go.id, matriz.id])
    expect(third.status).to eq('lost')
    expect(summary(third)).to include('exhausted' => true)
  end

  it 'skips units the customer already visited, has an open deal in, or that have no active pipeline' do
    chain
    origin = deal
    crm_opportunity(account, df, pipeline: pipelines[df], contact: origin.contact)
    pipelines[go].update!(active: false)

    lost = lose(origin)

    expect(lost.status).to eq('lost')
    expect(summary(lost)).to include('exhausted' => true)
  end

  it 'starts from the first unit when the lost deal is outside the order' do
    chain(chain_unit_ids: [go.id, df.id])
    expect(next_deal(lose(deal)).business_unit_id).to eq(go.id)
  end

  it 'does not pass on the reasons the admin excluded' do
    chain(chain_skip_reason_ids: [gave_up.id])
    lost = lose(deal, gave_up)

    expect(lost.status).to eq('lost')
    expect(summary(lost)).to be_nil
  end

  it 'stops at the forwarding limit and records why' do
    chain(max_forward_attempts: 1)
    second = next_deal(lose(deal))

    lost = lose(second)

    expect(lost.status).to eq('lost')
    expect(summary(lost)).to include('forward_error' => 'limit_reached', 'unit' => 'Filial GO')
  end

  it 'lets a rule that already forwarded the deal win' do
    chain
    Outsider::Crm::AutomationRules.new(account).create(name: 'Perdido vai para GO', trigger: 'lost',
                                                       actions: [{ type: 'forward', to_business_unit_id: go.id }])
    origin = lose(deal)

    expect(next_deal(origin).business_unit_id).to eq(go.id)
    expect(origin.activities.automation.pluck(:metadata).pluck('rule')).to eq(['custom'])
  end

  it 'does not need a forwarding reason even when the account has some' do
    Outsider::Crm::LostReason.create!(account: account, name: 'Unidade errada', kind: :forward)
    chain
    expect(next_deal(lose(deal))).to be_present
  end

  it 'sends the deal only once, even when it runs again' do
    chain(max_forward_attempts: 5)
    origin = lose(deal)

    described_class.new(origin).perform
    expect(Outsider::Crm::Forward.where(from_opportunity_id: origin.id).count).to eq(1)
    expect do
      Outsider::Crm::OpportunityForwarder.new(origin, access: Outsider::Crm::RuleRunner::SystemAccess.new(account.id), user: nil,
                                                      params: { to_business_unit_id: go.id }, lost: :keep).perform
    end.to raise_error(Outsider::Crm::OpportunityForwarder::Refused) { |error| expect(error.code).to eq(:already_forwarded) }
  end

  it 'does not pass on a deal that is created already lost' do
    chain
    created = deal(status: :lost, lost_reason: no_stock)

    expect(next_deal(created)).to be_nil
  end

  describe 'rotation' do
    before { chain(chain_assign: 'rotation') }

    it 'gives each new deal to the next seller of the unit, with the contact task' do
      first, second = [ana.id, bia.id].sort
      targets = Array.new(3) { next_deal(lose(deal)) }

      expect(targets.map(&:owner_id)).to eq([first, second, first])
      expect(targets.first.tasks.pending.pluck(:assignee_id, :kind)).to eq([[first, 'call']])
    end

    it 'skips managers while the unit has sellers and people who left the account' do
      first, second = [ana.id, bia.id].sort
      df.members.create!(account: account, user: create(:user, account: account, role: :agent), role: :manager)
      AccountUser.find_by(account: account, user_id: second).destroy!

      expect(Array.new(2) { next_deal(lose(deal)).owner_id }).to eq([first, first])
    end

    it 'leaves the deal without owner when the unit has nobody' do
      chain(chain_assign: 'rotation', chain_unit_ids: [matriz.id, go.id])
      expect(next_deal(lose(deal)).owner_id).to be_nil
    end

    it 'does not move the turn when the forward is refused' do
      chain(chain_assign: 'rotation', max_forward_attempts: 1)
      start = deal(go, owner: nil)
      manual = Outsider::Crm::OpportunityForwarder.new(start, access: Outsider::Crm::RuleRunner::SystemAccess.new(account.id), user: nil,
                                                              params: { to_business_unit_id: matriz.id }).perform.to_opportunity
      refused = lose(manual)

      expect(summary(refused)).to include('forward_error' => 'limit_reached', 'unit' => 'Filial DF')
      expect(next_deal(lose(deal)).owner_id).to eq([ana.id, bia.id].min)
    end
  end

  describe 'preview' do
    it 'lists the next units for an open deal, cut by the forwarding limit' do
      chain(max_forward_attempts: 1)
      origin = deal
      history = Outsider::Crm::ContactHistory.new(origin.contact, access: Outsider::Crm::Access.new(account.account_users.first))

      expect(history.to_h[:journeys].first).to include(upcoming: [{ 'id' => df.id, 'name' => 'Filial DF' }], upcoming_from: origin.id)
    end
  end

  describe 'settings' do
    it 'refuses units or reasons from another account and unknown assignment modes' do
      other = crm_unit(create(:account))
      expect { settings.update(chain_unit_ids: [matriz.id, other.id]) }.to raise_error(Outsider::Crm::Settings::Invalid, 'chain_unit_ids')
      expect { settings.update(chain_assign: 'random') }.to raise_error(Outsider::Crm::Settings::Invalid, 'chain_assign')
      expect(settings.update(chain_unit_ids: [go.id, matriz.id, go.id])['chain_unit_ids']).to eq([go.id, matriz.id])
    end
  end
end
