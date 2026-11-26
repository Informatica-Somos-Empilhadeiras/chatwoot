# OUTSIDER: locais do cliente (Outsider::ContactPlace). O primeiro vira o principal; marcar outro como principal tira o
# anterior; apagar o principal passa a marca para o mais antigo que sobrou.
class Outsider::ContactPlaces
  class Invalid < StandardError; end

  def initialize(contact, user = nil)
    @contact = contact
    @user = user
  end

  def all
    scope.ordered.includes(:created_by).to_a
  end

  def main
    scope.ordered.first
  end

  # attributes: name, address, latitude, longitude, main
  def create(attributes)
    data = normalize(attributes)
    @contact.with_lock do
      # o mesmo ponto de novo (ex.: a mesma localização salva duas vezes) devolve o que já existe
      same = scope.find_by(latitude: data[:latitude], longitude: data[:longitude])
      next same if same
      raise Invalid, 'too_many_places' if scope.count >= Outsider::ContactPlace::MAX_PER_CONTACT

      main = data.delete(:main) || scope.none?
      place = scope.create!(data.merge(account_id: @contact.account_id, created_by: @user, main: false))
      make_main(place) if main
      place.reload
    end
  end

  def update(place, attributes)
    attributes = attributes.to_h.symbolize_keys
    @contact.with_lock do
      place.update!(name: clean(attributes[:name], 100)) if attributes.key?(:name)
      place.update!(address: clean(attributes[:address], 300)) if attributes.key?(:address)
      make_main(place) if truthy?(attributes[:main])
      place.reload
    end
  end

  def destroy(place)
    @contact.with_lock do
      place.destroy!
      next_place = scope.ordered.first
      next_place.update!(main: true) if place.main && next_place && !next_place.main
    end
  end

  def find(id)
    scope.find(id)
  end

  # um local que veio de outra tela (Agendar OS, mapa): os mesmos limites do cadastro
  def self.point(attributes)
    data = attributes.to_h.symbolize_keys
    latitude = coordinate(data[:latitude], 90)
    longitude = coordinate(data[:longitude], 180)
    return nil if latitude.nil? || longitude.nil?

    { name: data[:name].to_s.squish.first(100).presence, address: data[:address].to_s.squish.first(300).presence,
      latitude: latitude, longitude: longitude }
  end

  def self.coordinate(value, limit)
    number = Float(value.to_s.tr(',', '.'), exception: false)
    number.round(6) if number&.between?(-limit, limit)
  end

  private

  def scope
    Outsider::ContactPlace.where(account_id: @contact.account_id, contact_id: @contact.id)
  end

  def normalize(attributes)
    point = self.class.point(attributes) || raise(Invalid, 'invalid_coordinates')
    name = point[:name] || point[:address]&.split(',')&.first || raise(Invalid, 'missing_name')
    point.merge(name: name.first(100), main: truthy?(attributes.to_h.symbolize_keys[:main]))
  end

  def make_main(place)
    scope.where.not(id: place.id).where(main: true).update_all(main: false, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    place.update!(main: true)
  end

  def clean(value, size) = value.to_s.squish.first(size).presence
  def truthy?(value) = ActiveModel::Type::Boolean.new.cast(value) == true
end
