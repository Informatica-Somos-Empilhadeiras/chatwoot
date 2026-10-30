# OUTSIDER: aparência da conta (Configurações > Aparência). Favicon, logo e papel de parede ficam no
# Active Storage do próprio Account (sem coluna nova) e o título e os ajustes em
# accounts.internal_attributes (Outsider::Branding). Incluído no Account pelo
# config/initializers/outsider_branding.rb.
module Outsider::AccountBranding
  extend ActiveSupport::Concern

  included do
    has_one_attached :outsider_favicon
    has_one_attached :outsider_logo
    has_one_attached :outsider_wallpaper
  end
end
