require 'rails_helper'

RSpec.describe Outsider::Crm::ProposalTimedRules do
  let(:account) { create(:account) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:unit) { crm_unit(account) }
  let(:pipeline) { crm_pipeline(account, unit) }
  let(:rules) { Outsider::Crm::AutomationRules.new(account) }
  let(:contact) { create(:contact, account: account) }
  let(:deal) { crm_opportunity(account, unit, pipeline: pipeline, owner: seller, contact: contact) }

  def rule(trigger, wait_hours = nil, title: 'Cobrar {proposta}')
    rules.create(name: trigger, trigger: trigger, wait_hours: wait_hours,
                 actions: [{ type: 'create_task', title: title, due_in_hours: 0 }, { type: 'add_note', body: 'Nota da {proposta}' }])
  end

  def proposal(**attrs)
    crm_proposal(account, owner: seller, contact: contact, opportunity: deal, **attrs)
  end

  def timed
    Outsider::Crm::TimedRules.new(account).perform
  end

  describe 'event triggers' do
    it 'runs the rules of the linked deal when the proposal is sent, accepted or rejected' do
      rule('proposal_sent')
      rule('proposal_rejected', title: 'Entender a recusa')
      record = proposal
      saver = Outsider::Crm::ProposalSaver.new(account.account_users.find_by(user: seller))

      saver.change_status(record, 'sent')
      task = deal.tasks.last
      expect(task.title).to eq("Cobrar #{record.code}")
      log = deal.activities.automation.last.metadata
      expect(log).to include('rule' => 'custom', 'proposal_id' => record.id, 'proposal_number' => record.number, 'tasks' => 1)
      expect(deal.activities.where(kind: :note).last.body).to eq("Nota da #{record.code}")

      expect { saver.change_status(record, 'rejected') }.to change { deal.tasks.where(title: 'Entender a recusa').count }.by(1)
    end

    it 'does nothing for proposals without a deal or for other status changes' do
      rule('proposal_accepted')
      record = crm_proposal(account, owner: seller, contact: contact)
      record.update!(status: :accepted)
      linked = proposal
      linked.update!(title: 'Outro título')

      expect(Outsider::Crm::Task.count).to eq(0)
    end
  end

  describe 'timed triggers' do
    it 'charges proposals sent without reply, once per send' do
      rule('proposal_no_reply', 72)
      old = travel_to(4.days.ago) { proposal.tap { |record| record.update!(status: :sent, sent_at: Time.current) } }
      travel_to(1.day.ago) { proposal.update!(status: :sent, sent_at: Time.current) }
      proposal.update!(status: :accepted, sent_at: 5.days.ago)

      expect(timed).to eq(1)
      expect(deal.tasks.last.title).to eq("Cobrar #{old.code}")
      expect(timed).to eq(0)

      old.sends.create!(account: account, channel: :whatsapp, status: :delivered, contact_id: contact.id)
      expect(timed).to eq(0)
      travel_to(4.days.from_now) { expect(timed).to eq(2) }
    end

    it 'warns about sent proposals expiring inside the window, but not expired ones' do
      rule('proposal_expiring', 48)
      soon = proposal(valid_until: Time.zone.today + 1).tap { |record| record.update!(status: :sent) }
      proposal(valid_until: Time.zone.today + 5).update!(status: :sent)
      proposal(valid_until: Time.zone.today - 1).update!(status: :sent)
      proposal(valid_until: Time.zone.today).tap { |record| record.update!(status: :sent) }.update!(status: :rejected)

      expect(timed).to eq(1)
      expect(deal.activities.automation.last.metadata).to include('proposal_id' => soon.id)
      expect(timed).to eq(0)

      # validade mudou: situação nova
      soon.update!(valid_until: Time.zone.today)
      expect(timed).to eq(1)
    end

    it 'skips proposals whose deal is closed or outside the rule conditions' do
      rules.create(name: 'x', trigger: 'proposal_no_reply', wait_hours: 1, conditions: { business_unit_id: unit.id },
                   actions: [{ type: 'create_task', title: 'Cobrar', due_in_hours: 0 }])
      other_unit = crm_unit(account, name: 'Vendas')
      other_deal = crm_opportunity(account, other_unit, owner: seller, contact: create(:contact, account: account))
      crm_proposal(account, owner: seller, contact: other_deal.contact, opportunity: other_deal, status: :sent, sent_at: 2.hours.ago)
      proposal(status: :sent, sent_at: 2.hours.ago)
      deal.update!(status: :won)

      expect(timed).to eq(0)
    end
  end
end
