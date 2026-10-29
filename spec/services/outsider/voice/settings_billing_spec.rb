require 'rails_helper'

RSpec.describe Outsider::Voice::SettingsBilling do
  let(:account) { create(:account) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:settings) { Outsider::Voice::Settings.new(account) }

  def reload
    Outsider::Voice::Settings.new(account.reload)
  end

  it 'keeps prices typed with a comma and refuses negative ones' do
    settings.update('costs' => { 'billing' => '60_6', 'rates' => { 'local_fixed' => { 'minute' => '0,075' } } })
    expect(reload.costs).to include('billing' => '60_6')
    expect(reload.costs['rates']['local_fixed']).to eq('minute' => 0.075, 'call' => 0.0)

    expect { settings.update('costs' => { 'rates' => { 'inbound' => { 'call' => '-1' } } }) }
      .to raise_error(Outsider::Voice::Settings::Invalid, /costs.rates.inbound.call/)
  end

  it 'keeps the branch ids from the screen and drops the branch of a person when it is deleted' do
    settings.update('branches' => [{ 'id' => 'goiania1', 'name' => 'Goiânia' }, { 'name' => 'Nova' }],
                    'agents' => { seller.id.to_s => { 'extension' => '', 'branch' => 'goiania1' } })
    saved = reload
    expect(saved.branches.first).to eq('id' => 'goiania1', 'name' => 'Goiânia')
    expect(saved.branches.last['id']).to match(/\A[a-z0-9]{8}\z/)
    expect(saved.branch_for(seller.id)).to include('name' => 'Goiânia')

    saved.update(saved.as_json.deep_dup.merge('branches' => [saved.branches.last]))
    expect(reload.branch_for(seller.id)).to be_nil
  end

  it 'refuses two branches with the same name' do
    expect { settings.update('branches' => [{ 'name' => 'Goiânia' }, { 'name' => 'goiânia' }]) }
      .to raise_error(Outsider::Voice::Settings::Invalid, /branches.1.name/)
  end

  it 'keeps costs, branches and recording options when an older screen does not send them' do
    settings.update('auto_record' => true, 'recording_days' => 90, 'branches' => [{ 'name' => 'Goiânia' }],
                    'costs' => { 'rates' => { 'international' => { 'minute' => '2' } } })
    reload.update('enabled' => true)

    saved = reload
    expect(saved.auto_record?).to be(true)
    expect(saved.recording_days).to eq(90)
    expect(saved.branches.pluck('name')).to eq(['Goiânia'])
    expect(saved.costs['rates']['international']['minute']).to eq(2.0)
  end

  it 'keeps recordings for 1 year by default and between 30 days and 5 years' do
    expect(settings.recording_days).to eq(365)
    expect { settings.update('recording_days' => 10) }.to raise_error(Outsider::Voice::Settings::Invalid, /recording_days/)
  end
end
