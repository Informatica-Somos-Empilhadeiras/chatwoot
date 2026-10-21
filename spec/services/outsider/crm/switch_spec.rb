require 'rails_helper'

RSpec.describe Outsider::Crm::Switch do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:other) { create(:user, account: account, role: :agent) }
  let(:unit) { crm_unit(account) }
  let(:stream) { Outsider::Crm::LiveUpdates.stream(account.id) }

  def account_user(user)
    account.account_users.find_by(user: user)
  end

  def switch
    described_class.new(account.reload)
  end

  before do
    [seller, other].each { |user| Outsider::Crm::BusinessUnitMember.create!(account: account, business_unit: unit, user: user, role: :seller) }
  end

  it 'starts off in every account, administrators included' do
    crm_enable(account, enabled: false)

    expect(switch.account_enabled?).to be(false)
    expect(switch.enabled_for?(account_user(admin))).to be(false)
    expect(Outsider::Crm::Access.new(account_user(admin))).not_to be_enabled
    expect(Outsider::Crm::Access.new(account_user(seller)).disabled_reason).to eq('account')
  end

  it 'gives every agent the CRM once the account is on, until an administrator turns an agent off' do
    expect(switch.enabled_for?(account_user(seller))).to be(true)

    expect { switch.update_agent(seller.id, false) }.to have_broadcasted_to(stream).with(kind: 'access', user_id: seller.id)
    expect(switch.enabled_for?(account_user(seller))).to be(false)
    expect(switch.enabled_for?(account_user(other))).to be(true)
    expect(Outsider::Crm::Access.new(account_user(seller)).disabled_reason).to eq('agent')

    switch.update_agent(seller.id, true)
    expect(switch.enabled_for?(account_user(seller))).to be(true)
  end

  it 'keeps administrators on and forgets people who left the account' do
    switch.update_agent(seller.id, false)
    account.account_users.find_by(user: other).update!(role: :administrator)
    switch.update_agent(other.id, false)

    expect(switch.enabled_for?(account_user(other))).to be(true)
    expect(switch.disabled_agent_ids).to eq([seller.id])

    account_user(seller).destroy!
    switch.update_agent(other.id, true)
    expect(account.reload.internal_attributes['outsider_crm_disabled_user_ids']).to eq([])
  end

  it 'takes agents with the CRM off out of owners, assignees and the rotation' do
    manager = create(:user, account: account, role: :agent)
    Outsider::Crm::BusinessUnitMember.create!(account: account, business_unit: unit, user: manager, role: :manager)
    switch.update_agent(seller.id, false)

    expect(Outsider::Crm::Access.assignable_user_ids(account.id, unit.id)).to contain_exactly(admin.id, other.id, manager.id)
    expect(Outsider::Crm::Rotation.new(account.reload).candidate_ids(unit.id)).to eq([other.id])

    switch.update_agent(other.id, false)
    expect(Outsider::Crm::Rotation.new(account.reload).candidate_ids(unit.id)).to eq([manager.id])
  end

  it 'lists only the accounts with the CRM on' do
    off = create(:account)

    expect(described_class.enabled_accounts.where(id: [account.id, off.id])).to eq([account])
  end

  describe 'account field' do
    it 'reads and writes the account switch from the super admin form without touching other internal attributes' do
      account.update_columns(internal_attributes: account.internal_attributes.merge('other' => 1)) # rubocop:disable Rails/SkipsModelValidations

      expect { account.update!(outsider_crm_enabled: '0') }.to have_broadcasted_to(stream).with(kind: 'access')
      expect(account.reload.outsider_crm_enabled).to be(false)
      expect(account.internal_attributes).to include('other' => 1, 'outsider_crm_enabled' => false)

      account.update!(outsider_crm_enabled: '1')
      expect(account.reload.outsider_crm_enabled).to be(true)
      expect { account.update!(name: 'Outro nome', outsider_crm_enabled: '1') }.not_to have_broadcasted_to(stream)
    end

    it 'does not erase what the CRM saved in the account while the super admin form was open' do
      form = Account.find(account.id)
      switch.update_agent(seller.id, false)

      form.update!(name: 'Conta renomeada', outsider_crm_enabled: '0')

      expect(account.reload.internal_attributes).to include('outsider_crm_enabled' => false, 'outsider_crm_disabled_user_ids' => [seller.id])
      expect(account.name).to eq('Conta renomeada')
    end
  end

  describe 'people leaving the account or changing role' do
    it 'start with the CRM on again and get their open screens to check access' do
      switch.update_agent(seller.id, false)
      switch.update_agent(other.id, false)

      expect { account_user(seller).update!(role: :administrator) }.to have_broadcasted_to(stream).with(kind: 'access', user_id: seller.id)
      account_user(seller).update!(role: :agent)
      expect(switch.enabled_for?(account_user(seller))).to be(true)

      expect { account_user(other).destroy! }.to have_broadcasted_to(stream).with(kind: 'access', user_id: other.id)
      expect(account.reload.internal_attributes['outsider_crm_disabled_user_ids']).to eq([])
    end

    it 'tells the open screens when someone joins or leaves a unit' do
      newcomer = create(:user, account: account, role: :agent)

      expect { Outsider::Crm::BusinessUnitMember.create!(account: account, business_unit: unit, user: newcomer, role: :seller) }
        .to have_broadcasted_to(stream).with(kind: 'access', user_id: newcomer.id)
    end
  end

  describe 'automation rules' do
    let(:manager) { create(:user, account: account, role: :agent) }
    let(:rules) { Outsider::Crm::AutomationRules.new(account) }

    before { Outsider::Crm::BusinessUnitMember.create!(account: account, business_unit: unit, user: manager, role: :manager) }

    it 'gives tasks only to people with the CRM on, falling back to the owner or to nobody' do
      rules.create(name: 'Ganhou', trigger: 'won', actions: [
                     { type: 'create_task', title: 'Gestor', assignee: 'managers' },
                     { type: 'create_task', title: 'Pessoa', assignee: 'user', user_id: other.id },
                     { type: 'create_task', title: 'Dono', assignee: 'owner' }
                   ])
      switch.update_agent(manager.id, false)
      switch.update_agent(other.id, false)
      deal = crm_opportunity(account, unit, owner: seller)
      deal.update!(status: :won)
      expect(deal.tasks.pluck(:title, :assignee_id)).to contain_exactly(['Gestor', seller.id], ['Pessoa', seller.id], ['Dono', seller.id])

      switch.update_agent(seller.id, false)
      other_deal = crm_opportunity(account, unit, owner: seller)
      other_deal.update!(status: :won)
      expect(other_deal.tasks.pluck(:assignee_id)).to eq([nil, nil, nil])
    end

    it 'forwards without an owner when the owner chosen in the rule has the CRM off' do
      target = crm_unit(account, name: 'Vendas')
      crm_pipeline(account, target, name: 'Novos')
      receiver = create(:user, account: account, role: :agent)
      target.members.create!(account: account, user: receiver, role: :seller)
      reason = Outsider::Crm::LostReason.create!(account: account, name: 'Unidade errada', kind: :both)
      rule = rules.create(name: 'Perdido vai para Vendas', trigger: 'lost',
                          actions: [{ type: 'forward', to_business_unit_id: target.id, owner_id: receiver.id }])
      switch.update_agent(receiver.id, false)
      # a regra salva continua editável com o responsável desligado
      expect { rules.update(rule['id'], name: 'Perdido segue para Vendas') }.not_to raise_error

      deal = crm_opportunity(account, unit, owner: seller)
      deal.update!(status: :lost, lost_reason: reason)

      forwarded = Outsider::Crm::Opportunity.find_by(business_unit_id: target.id, contact_id: deal.contact_id)
      expect(forwarded).to have_attributes(owner_id: nil)
    end
  end

  describe 'scheduled automations' do
    it 'skip accounts with the CRM off' do
      Outsider::Crm::Settings.new(account).update(automation_stalled_task: true, automation_stalled_days: 3)
      deal = travel_to(4.days.ago) { crm_opportunity(account, unit, owner: seller) }
      crm_enable(account, enabled: false)

      Outsider::Crm::StalledOpportunities.perform_all
      expect(deal.tasks.count).to eq(0)

      crm_enable(account)
      switch.update_agent(seller.id, false)
      Outsider::Crm::StalledOpportunities.perform_all
      expect(deal.tasks.pluck(:assignee_id)).to eq([nil])
    end
  end
end
