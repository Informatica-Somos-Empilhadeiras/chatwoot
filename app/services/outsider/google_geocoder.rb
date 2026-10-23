# OUTSIDER: busca de endereço no Google (Geocoding API), usada pelo Outsider::Geocoder quando o servidor
# tem OUTSIDER_GOOGLE_MAPS_KEY. Acha o número da casa na maioria dos endereços do Brasil, ao contrário do
# OpenStreetMap. Cada busca conta na cota do Google (as respostas ficam um dia em cache no Geocoder).
# A chave nunca vai para o navegador nem para o log.
class Outsider::GoogleGeocoder
  include HTTParty

  URL = 'https://maps.googleapis.com/maps/api/geocode/json'.freeze
  LIMIT = Outsider::Geocoder::LIMIT
  TIMEOUT = Outsider::Geocoder::TIMEOUT
  # ROOFTOP: o ponto exato; RANGE_INTERPOLATED: estimado pela numeração da rua (bom o bastante)
  EXACT_TYPES = %w[ROOFTOP RANGE_INTERPOLATED].freeze

  def initialize(key)
    @key = key
  end

  def search(query)
    request(address: query, components: 'country:BR').first(LIMIT).map { |row| result(row) }
  end

  def reverse(latitude, longitude)
    row = request(latlng: "#{latitude},#{longitude}").first
    row ? result(row) : { name: nil, address: nil, exact: false }
  end

  private

  def request(params)
    response = self.class.get(URL, query: params.merge(key: @key, language: 'pt-BR', region: 'br'), timeout: TIMEOUT)
    raise Outsider::Geocoder::Error, "HTTP #{response.code}" unless response.success?

    body = response.parsed_response.to_h
    return [] if body['status'] == 'ZERO_RESULTS'
    raise Outsider::Geocoder::Error, "Google #{body['status']}" unless body['status'] == 'OK'

    Array(body['results'])
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError => e
    raise Outsider::Geocoder::Error, e.message
  end

  def result(row)
    parts = components(row)
    location = row.dig('geometry', 'location').to_h
    {
      name: place_name(parts, row),
      address: row['formatted_address'].presence,
      latitude: location['lat'].to_f.round(6),
      longitude: location['lng'].to_f.round(6),
      road: parts['route'].presence,
      exact: parts['street_number'].present? && EXACT_TYPES.include?(row.dig('geometry', 'location_type'))
    }
  end

  # { 'route' => 'Rua 10', 'street_number' => '250', ... }
  def components(row)
    Array(row['address_components']).each_with_object({}) do |part, all|
      Array(part['types']).each { |type| all[type] ||= part['long_name'] }
    end
  end

  def place_name(parts, row)
    street = [parts['route'], parts['street_number']].compact.join(', ').presence
    parts['establishment'].presence || parts['point_of_interest'].presence || street || row['formatted_address'].to_s.split(',').first
  end
end
