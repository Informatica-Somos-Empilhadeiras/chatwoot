require 'rails_helper'

RSpec.describe Outsider::Crm::Automations do
  let(:account) { create(:account) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:unit) { crm_unit(account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:opportunity) { crm_opportunity(account, unit, contact: contact, conversation: conversation, owner: seller) }
  let(:settings) { Outsider::Crm::Settings.new(account) }

  before do
    create(:label, account: account, title: 'cliente-ganho')
    create(:label, account: account, title: 'perdido')
  end

  def automation_entries
    opportunity.activities.automation.map(&:metadata)
  end

  it 'does nothing while the automations are off (the default)' do
    opportunity.tasks.create!(account: account, title: 'Ligar')

    opportunity.update!(status: :won)

    expect(conversation.reload.label_list).to be_empty
    expect(opportunity.tasks.pending.count).to eq(1)
    expect(automation_entries).to be_empty
  end

  it 'applies the won label to the linked conversation as the automation system and records it' do
    settings.update(automation_won_label: 'cliente-ganho', automation_lost_label: 'perdido')
    Current.user = seller

    opportunity.update!(status: :won)

    expect(conversation.reload.label_list).to eq(['cliente-ganho'])
    expect(automation_entries).to eq([{ 'rule' => 'won_label', 'label' => 'cliente-ganho',
                                        'conversation_display_id' => conversation.display_id }])
    expect(opportunity.activities.automation.last.user_id).to be_nil
    expect(Current.user).to eq(seller)
  ensure
    Current.reset
  end

  it 'applies the lost label when the deal is lost' do
    settings.update(automation_lost_label: 'perdido')

    opportunity.update!(status: :lost)

    expect(conversation.reload.label_list).to eq(['perdido'])
  end

  it 'completes the pending tasks when the deal closes' do
    settings.update(automation_close_tasks: true)
    tasks = Array.new(2) { |index| opportunity.tasks.create!(account: account, title: "Tarefa #{index}") }

    opportunity.update!(status: :lost)

    expect(tasks.map { |task| task.reload.completed_at }).to all(be_present)
    expect(automation_entries).to eq([{ 'rule' => 'close_tasks', 'count' => 2 }])
  end

  it 'records a label that no longer exists instead of creating it' do
    settings.update(automation_won_label: 'cliente-ganho')
    account.labels.find_by(title: 'cliente-ganho').destroy!

    opportunity.update!(status: :won)

    expect(conversation.reload.label_list).to be_empty
    expect(automation_entries).to eq([{ 'rule' => 'won_label', 'label' => 'cliente-ganho', 'missing' => true }])
  end

  it 'never undoes the win when an automation fails' do
    settings.update(automation_won_label: 'cliente-ganho')
    allow_any_instance_of(Conversation).to receive(:add_labels).and_raise(StandardError, 'boom') # rubocop:disable RSpec/AnyInstance

    expect { opportunity.update!(status: :won) }.not_to raise_error
    expect(opportunity.reload.status).to eq('won')
  end

  describe Outsider::Crm::Settings do
    it 'refuses a label that does not exist and an out of range number' do
      expect { settings.update(automation_won_label: 'nao-existe') }.to raise_error(Outsider::Crm::Settings::Invalid, 'automation_won_label')
      expect { settings.update(automation_stalled_days: 0) }.to raise_error(Outsider::Crm::Settings::Invalid, 'automation_stalled_days')
      expect(settings.update(automation_won_label: '', automation_close_tasks: '1', automation_stalled_days: '10'))
        .to include('automation_won_label' => nil, 'automation_close_tasks' => true, 'automation_stalled_days' => 10, 'max_forward_attempts' => 3)
    end
  end
end
