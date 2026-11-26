require 'rails_helper'

# OUTSIDER: o ponto exato que o Chatwoot guarda no evento do Google volta na lista (Street View na Agenda)
RSpec.describe Outsider::Apps::Google::Calendar do
  let(:link) { instance_double(Outsider::GoogleLink) }
  let(:calendar) do
    allow(Outsider::Apps::Google::Client).to receive(:new).and_return(nil)
    described_class.new(link, 'America/Sao_Paulo')
  end

  it 'reads the point back and leaves it empty on other events' do
    event = { 'id' => 'a', 'start' => { 'dateTime' => '2026-11-26T09:00:00-03:00' }, 'end' => { 'dateTime' => '2026-11-26T10:00:00-03:00' },
              'extendedProperties' => { 'private' => { 'outsider_latitude' => '-16.68', 'outsider_longitude' => '-49.25' } } }
    expect(calendar.event_json(event)).to include(latitude: -16.68, longitude: -49.25)
    expect(calendar.event_json(event.except('extendedProperties'))).to include(latitude: nil, longitude: nil)
  end
end
