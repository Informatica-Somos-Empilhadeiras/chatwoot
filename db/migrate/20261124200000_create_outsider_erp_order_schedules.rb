# OUTSIDER: agendamentos de OS do ERP nas agendas conectadas (Microsoft e Google) de quem agendou. O evento mora na
# agenda da pessoa; aqui fica só o que o painel da OS mostra e o que permite cancelar: quando, título, em quais agendas
# (provedor + id do evento + link) e os e-mails convidados. Só cria a tabela.
class CreateOutsiderErpOrderSchedules < ActiveRecord::Migration[7.1]
  def change
    create_table :outsider_erp_order_schedules do |t|
      t.bigint :account_id, null: false
      t.bigint :user_id
      t.string :company, null: false
      t.integer :order_number, null: false
      t.string :title, null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.boolean :all_day, null: false, default: false
      t.string :time_zone
      t.string :location
      t.jsonb :events, null: false, default: []
      t.jsonb :attendees, null: false, default: []
      t.integer :whatsapp_count, null: false, default: 0
      t.timestamps
    end
    add_index :outsider_erp_order_schedules, [:account_id, :company, :order_number], name: 'index_outsider_erp_order_schedules_on_order'
  end
end
