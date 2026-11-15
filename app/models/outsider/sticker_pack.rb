# OUTSIDER: grupo de figurinhas de um atendente ("Clientes", "Frases", ...). Apagar o grupo só solta as
# figurinhas dele (ficam em "Sem grupo"). Ver app/services/outsider/sticker_library.rb.
class Outsider::StickerPack < ApplicationRecord
  self.table_name = 'outsider_sticker_packs'

  MAX_NAME = 40

  belongs_to :account
  belongs_to :user
  has_many :stickers, class_name: 'Outsider::Sticker', foreign_key: :pack_id, dependent: :nullify, inverse_of: :pack

  validates :name, presence: true, length: { maximum: MAX_NAME }

  def picker_data
    { id: id, name: name, position: position }
  end
end
