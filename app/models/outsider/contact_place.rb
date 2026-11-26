# OUTSIDER: um local do cliente com o ponto exato (ex.: galpão, filial). Um por contato é o principal: é ele que o
# Agendar OS escolhe sozinho. Ver Outsider::ContactPlaces e Api::V1::Accounts::Outsider::ContactPlacesController.
class Outsider::ContactPlace < ApplicationRecord
  self.table_name = 'outsider_contact_places'

  MAX_PER_CONTACT = 20

  belongs_to :account
  belongs_to :contact
  belongs_to :created_by, class_name: 'User', optional: true

  validates :name, presence: true, length: { maximum: 100 }
  validates :address, length: { maximum: 300 }
  validates :latitude, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }
  validates :longitude, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }

  scope :ordered, -> { order(main: :desc, created_at: :asc) }

  def as_place_json
    { id: id, name: name, address: address, latitude: latitude.to_f, longitude: longitude.to_f, main: main,
      created_by: created_by&.name, created_at: created_at.iso8601 }
  end
end
