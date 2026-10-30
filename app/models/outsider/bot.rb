# OUTSIDER: automação por bot desenhada como fluxograma (Configurações > Automação por bot).
# Tudo do bot fica em Outsider::Bot e nas tabelas outsider_bot_*.
module Outsider::Bot
  def self.table_name_prefix
    'outsider_bot_'
  end
end
