require 'rails_helper'

RSpec.describe 'Outsider CRM reports API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:unit) { crm_unit(account, name: 'Locação') }
  let(:other_unit) { crm_unit(account, name: 'Seminovos') }
  let!(:pipeline) { crm_pipeline(account, unit) }
  let(:qualification) { pipeline.stages.find_by(name: 'Qualificação') }
  let(:proposal) { pipeline.stages.find_by(name: 'Proposta') }
  let(:won_stage) { pipeline.stages.find_by(name: 'Ganho') }
  let(:lost_stage) { pipeline.stages.find_by(name: 'Perdido') }
  let(:price) { Outsider::Crm::LostReason.create!(account: account, name: 'Preço', kind: :lost) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/outsider/crm" }

  before { unit.members.create!(account: account, user: seller, role: :seller) }

  def deal(**attrs)
    crm_opportunity(account, unit, pipeline: pipeline, owner: seller, **attrs)
  end

  def report(user = seller, **params)
    get "#{base_url}/reports", params: params, headers: user.create_new_auth_token
    expect(response).to have_http_status(:ok)
    response.parsed_body
  end

  describe 'summary' do
    before do
      deal(value_cents: 10_000)
      deal(value_cents: 20_000, stage: proposal)
      deal(value_cents: 5_000, probability: 90)
      deal(value_cents: 50_000).update!(status: :won)
      deal(value_cents: 7_000).update!(status: :lost, lost_reason: price)
      travel_to(1.month.ago) { deal(value_cents: 9_000).update!(status: :lost, lost_reason: price) }
    end

    it 'counts open deals now and closed deals in the period, like the Kanban indicators' do
      summary = report(period: 'month')['summary']

      expect(summary).to include(
        'open_count' => 3, 'open_value_cents' => 35_000, 'weighted_value_cents' => 3_000 + 12_000 + 4_500,
        'won_count' => 1, 'won_value_cents' => 50_000, 'lost_count' => 1, 'lost_value_cents' => 7_000,
        'conversion_rate' => 50.0, 'average_ticket_cents' => 50_000, 'created_count' => 5
      )

      get "#{base_url}/opportunities/summary", params: { period: 'month' }, headers: seller.create_new_auth_token
      kanban = response.parsed_body
      %w[open_count open_value_cents weighted_value_cents won_count won_value_cents lost_count conversion_rate].each do |key|
        expect(summary[key]).to eq(kanban[key]), key
      end
    end

    it 'groups lost deals by reason inside the period' do
      expect(report(period: 'month')['lost_reasons']).to eq([{ 'id' => price.id, 'name' => 'Preço', 'count' => 1, 'value_cents' => 7_000 }])
      expect(report(period: 'last_12_months')['lost_reasons'].first).to include('count' => 2, 'value_cents' => 16_000)
    end
  end

  describe 'funnel' do
    it 'matches the Kanban columns for the same pipeline and filters' do
      deal(value_cents: 10_000)
      deal(value_cents: 20_000, stage: proposal)
      deal(value_cents: 30_000, stage: proposal, owner: admin)

      funnel = report(owner_id: seller.id)['funnel']
      get "#{base_url}/opportunities/board", params: { pipeline_id: pipeline.id, owner_id: seller.id }, headers: seller.create_new_auth_token
      board = response.parsed_body['stages']

      expect(funnel['pipeline_id']).to eq(pipeline.id)
      expect(funnel['stages'].map { |stage| [stage['id'], stage['open_count'], stage['open_value_cents']] })
        .to eq(board.map { |column| [column['id'], column['count'], column['total_cents']] })
      expect(funnel['stages'].pluck('open_count')).to eq([1, 1])
    end

    it 'computes conversion by stage and the average time in each stage from the stage history' do
      start = Time.zone.now.beginning_of_month + 1.day
      first = second = third = nil
      travel_to(start) do
        first = deal
        second = deal
      end
      travel_to(start + 1.day) do
        second.update!(stage: lost_stage, lost_reason: price)
        third = deal
      end
      travel_to(start + 2.days) { first.update!(stage: proposal) }
      travel_to(start + 3.days) { third.update!(stage: proposal) }
      travel_to(start + 5.days) { first.update!(status: :won) }

      funnel = travel_to(start + 6.days) { report(period: 'month')['funnel'] }

      expect(funnel['cohort_count']).to eq(3)
      expect(funnel['stages'].map { |stage| stage.slice('name', 'reached_count', 'conversion_rate', 'average_days', 'exits_count') }).to eq(
        [
          { 'name' => 'Qualificação', 'reached_count' => 3, 'conversion_rate' => nil, 'average_days' => 1.7, 'exits_count' => 3 },
          { 'name' => 'Proposta', 'reached_count' => 2, 'conversion_rate' => 66.7, 'average_days' => 3.0, 'exits_count' => 1 }
        ]
      )
      expect(funnel['won']).to eq('count' => 1, 'conversion_rate' => 50.0)
      expect(funnel['stages'].last['current_average_days']).to eq(3.0)
    end

    it 'uses the first active pipeline of the visible units and ignores pipelines the user cannot see' do
      hidden = crm_pipeline(account, other_unit, name: 'Seminovos')

      expect(report(pipeline_id: hidden.id)['funnel']['pipeline_id']).to eq(pipeline.id)
      expect(report(admin, pipeline_id: hidden.id)['funnel']['pipeline_id']).to eq(hidden.id)
    end
  end

  describe 'forecast' do
    it 'buckets open deals by expected close date, with full and weighted values' do
      deal(value_cents: 10_000, expected_close_on: Time.zone.today - 1)
      deal(value_cents: 20_000, stage: proposal, expected_close_on: Time.zone.today.next_month)
      deal(value_cents: 40_000, expected_close_on: Time.zone.today >> 8)
      deal(value_cents: 1_000)

      forecast = report['forecast'].index_by { |row| row['key'] }

      expect(forecast.keys.size).to eq(9)
      expect(forecast['overdue']).to include('count' => 1, 'value_cents' => 10_000, 'weighted_value_cents' => 3_000)
      expect(forecast[Time.zone.today.next_month.strftime('%Y-%m')]).to include('count' => 1, 'weighted_value_cents' => 12_000)
      expect(forecast['later']).to include('count' => 1, 'value_cents' => 40_000)
      expect(forecast['no_date']).to include('count' => 1, 'value_cents' => 1_000)
    end
  end

  describe 'units and owners' do
    it 'breaks results down by unit and owner, and shows a seller only their units' do
      crm_opportunity(account, other_unit, value_cents: 99_000).update!(status: :won)
      deal(value_cents: 50_000).update!(status: :won)
      deal(value_cents: 7_000, owner: nil).update!(status: :lost)

      admin_report = report(admin)
      expect(admin_report['units'].map { |row| row.slice('name', 'won_count', 'lost_count', 'conversion_rate') }).to eq(
        [{ 'name' => 'Locação', 'won_count' => 1, 'lost_count' => 1, 'conversion_rate' => 50.0 },
         { 'name' => 'Seminovos', 'won_count' => 1, 'lost_count' => 0, 'conversion_rate' => 100.0 }]
      )
      expect(admin_report['owners'].map { |row| [row['name'], row['won_count'], row['lost_count']] }).to eq(
        [[seller.name, 1, 0], [nil, 1, 1]]
      )

      expect(report(seller)['units'].pluck('name')).to eq(['Locação'])
      expect(report(seller)['summary']['won_value_cents']).to eq(50_000)
    end
  end

  it 'refuses users outside the CRM' do
    outsider = create(:user, account: account, role: :agent)
    get "#{base_url}/reports", headers: outsider.create_new_auth_token

    expect(response).to have_http_status(:forbidden)
  end
end
