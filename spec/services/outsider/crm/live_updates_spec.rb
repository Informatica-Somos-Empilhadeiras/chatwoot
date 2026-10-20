require 'rails_helper'

RSpec.describe Outsider::Crm::LiveUpdates do
  let(:account) { create(:account) }
  let(:unit) { crm_unit(account) }
  let(:pipeline) { crm_pipeline(account, unit) }
  let(:stream) { described_class.stream(account.id) }

  it 'tells the open CRM screens when a deal or a task changes' do
    deal = nil
    expect { deal = crm_opportunity(account, unit, pipeline: pipeline) }
      .to have_broadcasted_to(stream).with(hash_including(kind: 'opportunity', business_unit_id: unit.id))
    expect { deal.update!(status: :won) }.to have_broadcasted_to(stream).with(hash_including(kind: 'opportunity', id: deal.id))
    expect { deal.tasks.create!(account: account, title: 'Ligar') }
      .to have_broadcasted_to(stream).with(hash_including(kind: 'task', opportunity_id: deal.id))
  end

  it 'tells them when goals, commission or settings change' do
    expect { Outsider::Crm::Commission.new(account).update(general_bp: 100, rules: []) }
      .to have_broadcasted_to(stream).with(kind: 'config')
    expect { Outsider::Crm::Settings.new(account).update(sellers_see_own_deals: true) }
      .to have_broadcasted_to(stream).with(kind: 'config')
  end
end
