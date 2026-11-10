# OUTSIDER: a mensagem que sai pela Evolution nasce "em conferência" (ver Outsider::DeliveryCheck): o balão
# mostra o relógio até a Evolution confirmar que ela foi para o WhatsApp.
# Encaixado no Message por config/initializers/outsider_message_delivery.rb.
module Outsider::DeliveryTracking
  extend ActiveSupport::Concern

  included do
    before_create :outsider_track_delivery
  end

  private

  def outsider_track_delivery
    content_attributes[Outsider::DeliveryCheck::STATE] = Outsider::DeliveryCheck::CHECKING if Outsider::DeliveryCheck.tracks?(self)
  end
end
