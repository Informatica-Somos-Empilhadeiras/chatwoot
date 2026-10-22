# OUTSIDER: endereços salvos para o envio de localização (ex.: as unidades da empresa), para mandar
# com um clique. Ficam em accounts.internal_attributes, sem tabela nova: são poucos por conta.
# Todos da conta usam; só o administrador salva e apaga.
class Outsider::SavedLocations
  KEY = 'outsider_saved_locations'.freeze
  MAX = 50

  class Invalid < StandardError; end

  def initialize(account)
    @account = account
  end

  def all
    Array(@account.internal_attributes[KEY])
  end

  def create(attributes)
    save do |list|
      raise Invalid, 'too_many_locations' if list.size >= MAX

      item = normalize(attributes.to_h.symbolize_keys).merge('id' => (list.pluck('id').max.to_i + 1))
      [list + [item], item]
    end
  end

  def destroy(id)
    save do |list|
      item = list.find { |row| row['id'] == id.to_i } || raise(ActiveRecord::RecordNotFound)
      [list - [item], item]
    end
  end

  private

  def normalize(data)
    name = data[:name].to_s.squish.first(100)
    latitude = Float(data[:latitude].to_s, exception: false)
    longitude = Float(data[:longitude].to_s, exception: false)
    raise Invalid, 'missing_name' if name.blank?
    raise Invalid, 'invalid_coordinates' unless latitude&.between?(-90, 90) && longitude&.between?(-180, 180)

    { 'name' => name, 'address' => data[:address].to_s.squish.first(300).presence, 'latitude' => latitude.round(6),
      'longitude' => longitude.round(6) }
  end

  def save
    @account.with_lock do
      list, result = yield(all)
      # update_columns para não esbarrar nas validações de outros campos da conta
      @account.update_columns(internal_attributes: @account.internal_attributes.merge(KEY => list)) # rubocop:disable Rails/SkipsModelValidations
      result
    end
  end
end
