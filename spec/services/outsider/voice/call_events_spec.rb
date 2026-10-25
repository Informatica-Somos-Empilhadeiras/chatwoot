require 'rails_helper'

RSpec.describe Outsider::Voice::CallEvents do
  let(:account) { create(:account) }
  let(:owner) { create(:user, account: account, role: :agent) }
  let(:other) { create(:user, account: account, role: :agent) }
  let(:settings) { Outsider::Voice::Settings.new(account) }
  let(:router) { Outsider::Voice::Router.new(settings) }
  let(:events) { described_class.new(settings) }
  let!(:contact) { create(:contact, account: account, name: 'Transportes Silva', phone_number: '+5562999998888') }
  let!(:deal) { crm_opportunity(account, crm_unit(account), contact: contact, owner: owner) }

  before do
    settings.update(
      'enabled' => true, 'numbers' => [{ 'number' => '6232345678', 'state' => 'GO' }],
      'agents' => { owner.id.to_s => { 'extension' => '201', 'state' => 'GO', 'enabled' => true },
                    other.id.to_s => { 'extension' => '202', 'state' => 'GO', 'enabled' => true } }
    )
  end

  it 'records who answered and how long the conversation took' do
    router.inbound(linkedid: 'L1', did: '6232345678', from: '62999998888')
    events.answered(linkedid: 'L1', endpoint: '202')
    travel 95.seconds
    events.hangup(linkedid: 'L1', dialstatus: 'ANSWER', cause: '16')

    call = Outsider::Voice::Call.find_by!(linkedid: 'L1')
    expect(call).to have_attributes(status: 'answered', user_id: other.id, talk_seconds: 95, hangup_cause: '16')
    expect(deal.activities.call.last.metadata).to include('direction' => 'inbound', 'status' => 'answered', 'talk_seconds' => 95)
  end

  it 'turns a missed call into a return task for the deal owner, done when someone calls back and the customer answers' do
    router.inbound(linkedid: 'L2', did: '6232345678', from: '62999998888')
    events.hangup(linkedid: 'L2', dialstatus: 'NOANSWER', cause: '16')

    missed = Outsider::Voice::Call.find_by!(linkedid: 'L2')
    expect(missed).to be_missed
    expect(missed.task).to have_attributes(kind: 'call', assignee_id: owner.id, title: 'Return call from Transportes Silva')

    router.outbound(linkedid: 'L3', extension: '202', number: '062 99999-8888')
    events.answered(linkedid: 'L3', endpoint: 'operadora')
    events.hangup(linkedid: 'L3', dialstatus: 'ANSWER', cause: '16')

    expect(missed.reload).to have_attributes(returned_by_id: other.id)
    expect(missed.task.reload).to be_completed
    expect(Outsider::Voice::Call.find_by!(linkedid: 'L3')).to have_attributes(status: 'answered', user_id: other.id)
  end

  it 'keeps the call in the return queue when the customer does not answer the callback' do
    router.inbound(linkedid: 'L4', did: '6232345678', from: '62999998888')
    events.hangup(linkedid: 'L4', dialstatus: 'NOANSWER', cause: '16')
    router.outbound(linkedid: 'L5', extension: '201', number: '62999998888')
    events.hangup(linkedid: 'L5', dialstatus: 'BUSY', cause: '17')

    expect(Outsider::Voice::Call.find_by!(linkedid: 'L5')).to be_busy
    expect(Outsider::Voice::Call.to_return.pluck(:linkedid)).to eq(['L4'])
  end

  it 'ignores repeated hangups and unknown calls' do
    router.inbound(linkedid: 'L6', did: '6232345678', from: '62999998888')
    events.hangup(linkedid: 'L6', dialstatus: 'NOANSWER', cause: '16')
    events.hangup(linkedid: 'L6', dialstatus: 'NOANSWER', cause: '16')
    events.hangup(linkedid: 'nope', dialstatus: 'ANSWER', cause: '16')

    expect(deal.tasks.count).to eq(1)
  end
end
