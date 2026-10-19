# OUTSIDER: garante que os registros ligados (do CRM ou do Chatwoot) são da mesma conta.
# Os ids chegam do navegador, então a checagem fica no modelo e vale para qualquer caminho.
module Outsider::Crm::AccountScoped
  extend ActiveSupport::Concern

  included do
    belongs_to :account
  end

  class_methods do
    def validates_same_account(*associations)
      validate do
        associations.each do |association|
          record = public_send(association)
          next if record.nil? || record.account_id == account_id

          errors.add(association, :invalid)
        end
      end
    end
  end
end
