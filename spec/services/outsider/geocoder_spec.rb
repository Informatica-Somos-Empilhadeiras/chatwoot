require 'rails_helper'

RSpec.describe Outsider::Geocoder do
  let(:base) { 'https://nominatim.openstreetmap.org' }
  let(:row) do
    { 'lat' => '-16.6868912', 'lon' => '-49.2647943', 'name' => '', 'display_name' => 'Avenida Anhanguera, 100, Setor Central, Goiânia, GO, Brasil',
      'address' => { 'road' => 'Avenida Anhanguera', 'house_number' => '100' } }
  end

  it 'searches addresses in Brazil and returns short name, address and coordinates' do
    stub = stub_request(:get, "#{base}/search")
           .with(query: hash_including('q' => 'av anhanguera 100 goiania', 'countrycodes' => 'br', 'format' => 'jsonv2'),
                 headers: { 'User-Agent' => described_class::USER_AGENT })
           .to_return(status: 200, body: [row].to_json, headers: { 'Content-Type' => 'application/json' })

    expect(described_class.new.search('  av anhanguera   100 goiania ')).to eq(
      [{ name: 'Avenida Anhanguera, 100', address: row['display_name'], latitude: -16.686891, longitude: -49.264794 }]
    )
    expect(stub).to have_been_requested
  end

  it 'turns typed coordinates and Google Maps links into a point with its address' do
    stub_request(:get, "#{base}/reverse").with(query: hash_including('lat' => '-16.6869', 'lon' => '-49.2648'))
                                         .to_return(status: 200, body: row.to_json, headers: { 'Content-Type' => 'application/json' })

    found = described_class.new.search('https://www.google.com/maps/place/Somos/@-16.6869,-49.2648,17z')

    expect(found).to eq([{ name: 'Avenida Anhanguera, 100', address: row['display_name'], latitude: -16.6869, longitude: -49.2648 }])
  end

  it 'keeps the point when the reverse lookup fails' do
    stub_request(:get, "#{base}/reverse").with(query: hash_including({})).to_return(status: 500)

    expect(described_class.new.search('-23.5505, -46.6333')).to eq([{ name: nil, address: nil, latitude: -23.5505, longitude: -46.6333 }])
  end

  it 'ignores short queries and raises when the service is down' do
    expect(described_class.new.search('ab')).to eq([])

    stub_request(:get, "#{base}/search").with(query: hash_including({})).to_timeout
    expect { described_class.new.search('rua sem resposta') }.to raise_error(described_class::Error)
  end

  it 'reads coordinates only when they look like coordinates' do
    expect(described_class.coordinates('q=-16.68,-49.25')).to eq([-16.68, -49.25])
    expect(described_class.coordinates('rua 10, 200')).to be_nil
    expect(described_class.coordinates('95.1, 10')).to be_nil
  end
end
