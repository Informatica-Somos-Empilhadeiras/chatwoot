# OUTSIDER: quantidades disponível e reservada de cada item do catálogo do CRM. Em branco = não controla.
class AddQuantitiesToOutsiderCrmProducts < ActiveRecord::Migration[7.1]
  def change
    add_column :outsider_crm_products, :available_quantity, :integer
    add_column :outsider_crm_products, :reserved_quantity, :integer
  end
end
