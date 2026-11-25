require 'rails_helper'

# OUTSIDER: aviso das notas fiscais que ainda não foram para a nuvem
RSpec.describe Outsider::Erp::InvoiceCloud do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:cloud) { described_class.new(account) }
  let(:located) { {} }

  before do
    Outsider::Erp::Settings.new(account).update('enabled' => true, 'companies' => %w[somosemp], 'device_id' => 'abc123')
    allow_any_instance_of(Outsider::Erp::NextcloudInvoices).to receive(:locate) { |_, _company, number, _kind| located[number.to_i] } # rubocop:disable RSpec/AnyInstance
    $alfred.with { |conn| conn.del("outsider:erp:nf_nuvem:#{account.id}:ok", "outsider:erp:nf_nuvem:#{account.id}:falta") } # rubocop:disable Style/GlobalVars
  end

  it 'checks unseen notes on demand, remembers the ones found and ignores bad keys' do
    located[10] = '/f/10.pdf'
    statuses = cloud.statuses(%w[invoices:somosemp:10 invoices:somosemp:11 invoices:outra:12 orders:somosemp:1])
    expect(statuses).to eq('invoices:somosemp:10' => 'ok', 'invoices:somosemp:11' => 'missing')

    located.clear
    expect(cloud.statuses(%w[invoices:somosemp:10])).to eq('invoices:somosemp:10' => 'ok')
  end

  it 'does not flip a found note on a single failed open: it checks again later and only then marks it missing' do
    located[20] = '/f/20.pdf'
    cloud.statuses(%w[service_invoices:somosemp:20])
    located.clear

    expect { cloud.open_failed('service_invoices', 'somosemp', 20) }.to have_enqueued_job(Outsider::Erp::InvoiceCloudJob)
    expect(cloud.statuses(%w[service_invoices:somosemp:20]).values).to eq(['ok'])

    perform_enqueued_jobs
    expect(cloud.statuses(%w[service_invoices:somosemp:20]).values).to eq(['missing'])
  end

  it 'keeps a found note when the second check finds it again (the first failure was a glitch)' do
    located[30] = '/f/30.pdf'
    cloud.statuses(%w[invoices:somosemp:30])
    cloud.open_failed('invoices', 'somosemp', 30)
    perform_enqueued_jobs
    expect(cloud.statuses(%w[invoices:somosemp:30]).values).to eq(['ok'])
  end

  it 'never counts a Nextcloud outage as missing' do
    allow_any_instance_of(Outsider::Erp::NextcloudInvoices).to receive(:locate).and_raise(Outsider::Erp::NextcloudInvoices::Error, 'down') # rubocop:disable RSpec/AnyInstance
    expect(cloud.statuses(%w[invoices:somosemp:40]).values).to eq(['unknown'])
  end

  it 'sweeps the recent notes of every unit in the periodic job, skipping cancelled ones and the ones already found' do
    allow_any_instance_of(Outsider::Erp::Settings).to receive(:nextcloud_enabled?).and_return(true) # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(Outsider::Erp::Schema).to receive(:pick) { |_, _company, _table, candidates| Array(candidates).first } # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(Outsider::Erp::Client).to receive(:query_execute) do |_, sql| # rubocop:disable RSpec/AnyInstance
      sql.include?('notafiscalservico') ? [] : [{ 'chave' => 50, 'status' => 'IMPRESSA' }, { 'chave' => 51, 'status' => 'CANCELADA' }]
    end
    located[50] = '/f/50.pdf'
    Outsider::Erp::InvoiceCloudJob.perform_now
    expect($alfred.with { |conn| conn.hkeys("outsider:erp:nf_nuvem:#{account.id}:ok") }).to eq(['invoices:somosemp:50']) # rubocop:disable Style/GlobalVars
    expect($alfred.with { |conn| conn.hkeys("outsider:erp:nf_nuvem:#{account.id}:falta") }).to be_empty # rubocop:disable Style/GlobalVars
  end
end
