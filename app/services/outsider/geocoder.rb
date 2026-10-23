# OUTSIDER: busca de endereço para o envio de localização, no OpenStreetMap (Nominatim): gratuito e
# sem chave. A busca passa pelo servidor para mandar a identificação que o Nominatim exige e guardar
# as respostas em cache (a regra de uso dele é no máximo uma busca por segundo). OUTSIDER_GEOCODER_URL
# troca o endereço do serviço (ex.: um Nominatim próprio).
#
# Coordenadas digitadas ("-16.68, -49.25") ou coladas de um link do Google Maps não precisam de busca:
# viram o resultado direto, com o endereço do ponto quando o Nominatim responde.
#
# O OpenStreetMap quase não tem número de casa no Brasil: o resultado costuma ser a rua, com o pin no
# meio dela. Quando a busca tem o número depois de uma vírgula ("Rua 10, 250") e o resultado não, o
# número digitado entra no nome e no endereço, e "exact: false" avisa a tela para pedir o ajuste do pin
# no mapa. Com OUTSIDER_GOOGLE_MAPS_KEY a busca vai para o Google (Outsider::GoogleGeocoder), que
# acha o número na maioria dos endereços, mas é pago acima da cota grátis do Google.
class Outsider::Geocoder
  include HTTParty

  class Error < StandardError; end

  DEFAULT_URL = 'https://nominatim.openstreetmap.org'.freeze
  USER_AGENT = 'Chatwoot (outsider location sharing)'.freeze
  LIMIT = 6
  TIMEOUT = 8
  CACHE_TTL = 1.day
  # "@-16.68,-49.25", "q=-16.68,-49.25", "query=...", "ll=..." ou só "-16.68, -49.25"
  COORDINATES = /(?:^|[@=\s(])(-?\d{1,2}(?:\.\d+)?)\s*,\s*(-?\d{1,3}(?:\.\d+)?)/

  def self.coordinates(text)
    match = text.to_s.match(COORDINATES)
    return unless match

    latitude = match[1].to_f
    longitude = match[2].to_f
    [latitude, longitude] if latitude.between?(-90, 90) && longitude.between?(-180, 180) && match[1].include?('.')
  end

  # número depois de uma vírgula: "Rua 10, 250", "Rua 10, nº 250", "Av. T-63, 1200A, Setor Bueno"
  HOUSE_NUMBER = /\A(?:n[º°o.]?\s*)?(\d{1,5}[a-z]?)\z/i

  def self.house_number(query)
    query.to_s.split(',').drop(1).each do |part|
      match = part.strip.match(HOUSE_NUMBER)
      return match[1].upcase if match
    end
    nil
  end

  def search(query)
    query = query.to_s.squish.first(200)
    return [] if query.length < 3

    point = self.class.coordinates(query)
    return [reverse(*point)] if point

    found = cached("search/#{query.downcase}") { provider_search(query) }
    number = self.class.house_number(query)
    number ? found.map { |place| with_typed_number(place, number) } : found
  end

  private

  def google
    key = ENV.fetch('OUTSIDER_GOOGLE_MAPS_KEY', nil).presence
    @google = Outsider::GoogleGeocoder.new(key) if key && @google.nil?
    @google
  end

  def provider_search(query)
    return google.search(query) if google

    request('/search', q: query, countrycodes: 'br', limit: LIMIT).map { |row| result(row) }
  end

  def provider_reverse(latitude, longitude)
    return google.reverse(latitude, longitude) if google

    result(request('/reverse', lat: latitude, lon: longitude))
  end

  def reverse(latitude, longitude)
    found = cached("reverse/#{latitude},#{longitude}") { provider_reverse(latitude, longitude) }
    found.merge(latitude: latitude, longitude: longitude)
  rescue Error
    { name: nil, address: nil, latitude: latitude, longitude: longitude, exact: false }
  end

  # o resultado achou a rua, mas não o número: usa o número digitado; o pin continua na rua
  def with_typed_number(place, number)
    return place if place[:exact] || place[:road].blank?

    road = place[:road]
    street = "#{road}, #{number}"
    address = place[:address].to_s
    place.merge(name: place[:name] == road ? street : place[:name],
                address: address.include?(road) ? address.sub(road, street) : address.presence)
  end

  def cached(key, &)
    provider = google ? 'google' : 'osm'
    Rails.cache.fetch("outsider_geocoder/#{provider}/#{Digest::SHA256.hexdigest(key)}", expires_in: CACHE_TTL, &)
  end

  def request(path, params)
    response = self.class.get("#{base_url}#{path}", query: params.merge(format: 'jsonv2', addressdetails: 1, 'accept-language': 'pt-BR'),
                                                    headers: { 'User-Agent' => USER_AGENT }, timeout: TIMEOUT)
    raise Error, "HTTP #{response.code}" unless response.success?

    response.parsed_response
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError => e
    raise Error, e.message
  end

  def base_url
    (ENV['OUTSIDER_GEOCODER_URL'].presence || DEFAULT_URL).chomp('/')
  end

  # Nome curto (o lugar ou rua e número) e o endereço completo como o Nominatim escreve. exact: achou o
  # número da casa (ou é um lugar com nome); road fica para encaixar o número digitado.
  def result(row)
    row = row.to_h
    address = row['address'].to_h
    street = [address['road'], address['house_number']].compact.join(', ').presence
    {
      name: row['name'].presence || street || row['display_name'].to_s.split(',').first,
      address: row['display_name'].presence,
      latitude: row['lat'].to_f.round(6),
      longitude: row['lon'].to_f.round(6),
      road: address['road'].presence,
      exact: exact_row?(row, address)
    }
  end

  def exact_row?(row, address)
    address['house_number'].present? || (row['name'].present? && row['name'] != address['road'])
  end
end
