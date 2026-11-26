# OUTSIDER: locais do cliente (Google Maps na agenda). Cada contato pode ter alguns locais com o ponto exato
# (ex.: galpão, filial), um deles o principal; o Agendar OS usa o local para o evento, o pin do WhatsApp e o Street View.
# Também guarda no agendamento da OS o ponto exato escolhido. Só cria a tabela e acrescenta colunas novas.
class CreateOutsiderContactPlaces < ActiveRecord::Migration[7.1]
  def change
    create_table :outsider_contact_places do |t|
      t.bigint :account_id, null: false
      t.bigint :contact_id, null: false
      t.bigint :created_by_id
      t.string :name, null: false
      t.string :address
      t.decimal :latitude, precision: 9, scale: 6, null: false
      t.decimal :longitude, precision: 9, scale: 6, null: false
      t.boolean :main, null: false, default: false
      t.timestamps
    end
    add_index :outsider_contact_places, [:account_id, :contact_id]

    add_column :outsider_erp_order_schedules, :place_name, :string
    add_column :outsider_erp_order_schedules, :latitude, :decimal, precision: 9, scale: 6
    add_column :outsider_erp_order_schedules, :longitude, :decimal, precision: 9, scale: 6
  end
end
