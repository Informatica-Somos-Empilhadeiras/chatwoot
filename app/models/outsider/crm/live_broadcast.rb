# OUTSIDER: depois de gravar ou apagar, avisa as telas do CRM abertas na conta
# (Outsider::Crm::LiveUpdates). Roda depois do commit, quando a API já devolve o dado novo.
module Outsider::Crm::LiveBroadcast
  extend ActiveSupport::Concern

  included do
    after_commit -> { Outsider::Crm::LiveUpdates.record_changed(self) }
  end
end
