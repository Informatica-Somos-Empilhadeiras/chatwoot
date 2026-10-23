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
      [{ name: 'Avenida Anhanguera, 100', address: row['display_name'], latitude: -16.686891, longitude: -49.264794,
         road: 'Avenida Anhanguera', exact: true }]
    )
    expect(stub).to have_been_requested
  end

  it 'turns typed coordinates and Google Maps links into a point with its address' do
    stub_request(:get, "#{base}/reverse").with(query: hash_including('lat' => '-16.6869', 'lon' => '-49.2648'))
                                         .to_return(status: 200, body: row.to_json, headers: { 'Content-Type' => 'application/json' })

    found = described_class.new.search('https://www.google.com/maps/place/Somos/@-16.6869,-49.2648,17z')

    expect(found).to eq([{ name: 'Avenida Anhanguera, 100', address: row['display_name'], latitude: -16.6869, longitude: -49.2648,
                           road: 'Avenida Anhanguera', exact: true }])
  end

  it 'keeps the point when the reverse lookup fails' do
    stub_request(:get, "#{base}/reverse").with(query: hash_including({})).to_return(status: 500)

    expect(described_class.new.search('-23.5505, -46.6333')).to eq([{ name: nil, address: nil, latitude: -23.5505, longitude: -46.6333,
                                                                      exact: false }])
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

  it 'keeps the typed house number when the map only knows the street' do
    street = { 'lat' => '-16.70', 'lon' => '-49.27', 'name' => 'Rua 10', 'display_name' => 'Rua 10, Setor Oeste, Goiânia, GO, Brasil',
               'address' => { 'road' => 'Rua 10' } }
    stub_request(:get, "#{base}/search").with(query: hash_including('q' => 'Rua 10, nº 250, Goiânia'))
                                        .to_return(status: 200, body: [street].to_json, headers: { 'Content-Type' => 'application/json' })

    expect(described_class.new.search('Rua 10, nº 250, Goiânia').first).to include(
      name: 'Rua 10, 250', address: 'Rua 10, 250, Setor Oeste, Goiânia, GO, Brasil', exact: false
    )
    expect(described_class.house_number('Rua 10, Setor Oeste')).to be_nil
    expect(described_class.house_number('Av. T-63, 1200a, Setor Bueno')).to eq('1200A')
  end

  context 'with a Google key' do
    let(:google) { 'https://maps.googleapis.com/maps/api/geocode/json' }
    let(:google_row) do
      { 'formatted_address' => 'R. 10, 250 - Setor Oeste, Goiânia - GO, 74120-020, Brasil',
        'geometry' => { 'location' => { 'lat' => -16.6951234, 'lng' => -49.2712345 }, 'location_type' => 'ROOFTOP' },
        'address_components' => [{ 'long_name' => '250', 'types' => ['street_number'] },
                                 { 'long_name' => 'Rua 10', 'types' => ['route'] }] }
    end

    around { |example| with_modified_env(OUTSIDER_GOOGLE_MAPS_KEY: 'chave-teste') { example.run } }

    it 'searches on Google and marks rooftop results as exact' do
      stub = stub_request(:get, google).with(query: hash_including('address' => 'rua 10 250 goiania', 'key' => 'chave-teste',
                                                                   'components' => 'country:BR'))
                                       .to_return(status: 200, body: { status: 'OK', results: [google_row] }.to_json,
                                                  headers: { 'Content-Type' => 'application/json' })

      expect(described_class.new.search('rua 10 250 goiania')).to eq(
        [{ name: 'Rua 10, 250', address: google_row['formatted_address'], latitude: -16.695123, longitude: -49.271235,
           road: 'Rua 10', exact: true }]
      )
      expect(stub).to have_been_requested
    end

    it 'returns nothing for ZERO_RESULTS and raises when Google refuses' do
      stub_request(:get, google).with(query: hash_including('address' => 'lugar nenhum'))
                                .to_return(status: 200, body: { status: 'ZERO_RESULTS', results: [] }.to_json,
                                           headers: { 'Content-Type' => 'application/json' })
      stub_request(:get, google).with(query: hash_including('address' => 'chave errada'))
                                .to_return(status: 200, body: { status: 'REQUEST_DENIED' }.to_json, headers: { 'Content-Type' => 'application/json' })

      expect(described_class.new.search('lugar nenhum')).to eq([])
      expect { described_class.new.search('chave errada') }.to raise_error(described_class::Error, 'Google REQUEST_DENIED')
    end
  end
end
