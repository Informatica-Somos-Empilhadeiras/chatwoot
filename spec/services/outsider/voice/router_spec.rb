require 'rails_helper'

RSpec.describe Outsider::Voice::Router do
  let(:account) { create(:account) }
  let(:owner) { create(:user, account: account, role: :agent) }
  let(:goias) { create(:user, account: account, role: :agent) }
  let(:paulista) { create(:user, account: account, role: :agent) }
  let(:settings) { Outsider::Voice::Settings.new(account) }
  let(:router) { described_class.new(settings) }
  let!(:contact) { create(:contact, account: account, phone_number: '+5562999998888') }

  before do
    settings.update(
      'enabled' => true, 'ring_seconds' => 20, 'dial_format' => 'zero_ddd', 'owner_first' => true,
      'numbers' => [{ 'number' => '6232345678', 'state' => 'GO' }, { 'number' => '1132345678', 'state' => 'SP' }],
      'agents' => { owner.id.to_s => { 'extension' => '201', 'state' => 'SP', 'enabled' => true },
                    goias.id.to_s => { 'extension' => '202', 'state' => 'GO', 'enabled' => true },
                    paulista.id.to_s => { 'extension' => '203', 'state' => 'SP', 'enabled' => true } }
    )
  end

  describe 'inbound' do
    it 'rings the deal owner, then adds the state sellers, then everybody' do
      unit = crm_unit(account)
      crm_pipeline(account, unit)
      create_opportunity = Outsider::Crm::OpportunityBuilder.new(
        account: account, user: owner, params: { contact_id: contact.id, business_unit_id: unit.id, title: 'Locação', owner_id: owner.id }
      ).perform

      plan = router.inbound(linkedid: 'L1', did: '556232345678', from: '062999998888')

      expect(plan).to eq('20|PJSIP/201|PJSIP/201&PJSIP/202|PJSIP/201&PJSIP/202&PJSIP/203')
      call = Outsider::Voice::Call.find_by!(linkedid: 'L1')
      expect(call).to have_attributes(direction: 'inbound', status: 'ringing', state_code: 'GO', contact_id: contact.id,
                                      opportunity_id: create_opportunity.id, from_number: '+5562999998888', did: '6232345678')
    end

    it 'starts with the state sellers when the owner does not ring first' do
      settings.update(settings.as_json.merge('owner_first' => false))
      unit = crm_unit(account)
      crm_pipeline(account, unit)
      Outsider::Crm::OpportunityBuilder.new(
        account: account, user: owner, params: { contact_id: contact.id, business_unit_id: unit.id, title: 'Locação', owner_id: owner.id }
      ).perform

      expect(router.inbound(linkedid: 'L7', did: '6232345678', from: '062999998888')).to eq('20|PJSIP/202|PJSIP/202&PJSIP/201&PJSIP/203')
    end

    it 'finds the number in the To header when the operator sends the account user' do
      plan = router.inbound(linkedid: 'L2', did: 'somos', to: '<sip:1132345678@sip.operadora.com.br>', from: '11988887777')

      expect(plan).to eq('20|PJSIP/201&PJSIP/203|PJSIP/201&PJSIP/203&PJSIP/202')
    end
  end

  describe 'outbound' do
    it 'goes out with the number of the seller state, dialed as the operator wants' do
      expect(router.outbound(linkedid: 'L3', extension: '202', number: '+55 62 99999-8888')).to eq('6232345678|062999998888')

      call = Outsider::Voice::Call.find_by!(linkedid: 'L3')
      expect(call).to have_attributes(direction: 'outbound', user_id: goias.id, to_number: '+5562999998888', contact_id: contact.id)
    end

    it 'refuses international and premium numbers and unknown extensions' do
      expect(router.outbound(linkedid: 'L4', extension: '202', number: '+14155550100')).to eq('')
      expect(router.outbound(linkedid: 'L5', extension: '202', number: '09001234567')).to eq('')
      expect(router.outbound(linkedid: 'L6', extension: '299', number: '62999998888')).to eq('')
      expect(Outsider::Voice::Call.count).to eq(0)
    end
  end
end
