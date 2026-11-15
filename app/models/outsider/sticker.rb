# OUTSIDER: uma figurinha da coleção de um atendente: arquivo webp (512x512, fundo transparente), de onde
# veio (salva de uma conversa, subida de uma imagem), favorita ou não, em que grupo está e quantas vezes
# foi usada (para "Recentes"). Ver app/services/outsider/sticker_library.rb.
class Outsider::Sticker < ApplicationRecord
  include Rails.application.routes.url_helpers

  self.table_name = 'outsider_stickers'

  SOURCES = %w[upload received].freeze

  belongs_to :account
  belongs_to :user
  belongs_to :pack, class_name: 'Outsider::StickerPack', optional: true, inverse_of: :stickers
  has_one_attached :file

  validates :digest, presence: true, uniqueness: { scope: [:account_id, :user_id] }
  validates :source, inclusion: { in: SOURCES }
  validates :emoji, length: { maximum: 16 }, allow_nil: true

  def file_url
    file.attached? ? url_for(file) : ''
  end

  def picker_data
    {
      id: id, url: file_url, favorite: favorite, pack_id: pack_id, emoji: emoji, animated: animated,
      uses_count: uses_count, last_used_at: last_used_at&.iso8601, created_at: created_at.iso8601
    }
  end
end
