# OUTSIDER: uma linha de planilha do bot (Outsider::Bot::Dataset). data = { 'coluna' => 'valor' } e folded =
# o mesmo valor sem acento, sem maiúscula e só com letras e números, para "CPCD-25" achar "cpcd 25" e um CNPJ
# com ou sem pontuação.
class Outsider::Bot::DatasetRow < ApplicationRecord
  belongs_to :dataset, class_name: 'Outsider::Bot::Dataset'

  def self.fold(value)
    ActiveSupport::Inflector.transliterate(value.to_s, '').downcase.gsub(/[^a-z0-9]/, '')
  end
end
