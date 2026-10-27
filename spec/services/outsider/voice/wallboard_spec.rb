require 'rails_helper'

RSpec.describe Outsider::Voice::Wallboard do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:access) { Outsider::Crm::Access.new(admin.account_users.first) }
  let(:zone) { ActiveSupport::TimeZone['America/Sao_Paulo'] }

  def call_at(time, linkedid)
    Outsider::Voice::Call.create!(account_id: account.id, linkedid: linkedid, direction: :outbound, status: :answered,
                                  user_id: admin.id, from_number: '6232345678', to_number: '62998100000', started_at: time,
                                  answered_at: time + 5.seconds, ended_at: time + 65.seconds, talk_seconds: 60)
  end

  around { |example| travel_to(zone.local(2026, 10, 27, 15, 0)) { example.run } }

  it 'counts a call made at 23h on its own day and hour, in the telephony time zone' do
    call_at(zone.local(2026, 10, 26, 23, 30), 'late')

    board = described_class.new(access, period: 'month').to_h
    day = board[:timeline][:rows].find { |row| row[:date] == Date.new(2026, 10, 26) }

    expect(day[:outbound]).to eq(1)
    expect(board[:timeline][:rows].find { |row| row[:date] == Date.new(2026, 10, 27) }[:outbound]).to eq(0)
    expect(board[:by_hour][23][:outbound]).to eq(1)
    expect(described_class.new(access, period: 'today').to_h[:summary][:total]).to eq(0)
  end

  it 'shows this month and last month day by day, every day of the month' do
    month = described_class.new(access, period: 'month').to_h
    last_month = described_class.new(access, period: 'last_month').to_h

    expect(month[:timeline][:unit]).to eq('day')
    expect(month[:timeline][:rows].size).to eq(31)
    expect(month[:timeline][:rows].last).to include(future: true)
    expect(last_month[:timeline][:rows].size).to eq(30)
    expect(last_month[:period]).to include(previous_from: Date.new(2026, 8, 1), previous_to: Date.new(2026, 8, 31))
  end

  it 'compares the current month with the previous one up to the same day' do
    period = described_class.new(access, period: 'month').to_h[:period]

    expect(period).to include(from: Date.new(2026, 10, 1), previous_from: Date.new(2026, 9, 1), previous_to: Date.new(2026, 9, 27))
  end
end
