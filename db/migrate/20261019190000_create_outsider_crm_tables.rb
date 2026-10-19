# OUTSIDER: tabelas do CRM (ver app/models/outsider/crm.rb). Só cria tabelas novas com prefixo
# outsider_crm_; nenhuma tabela do Chatwoot é alterada. Contatos, conversas e usuários são
# referenciados por id sem chave estrangeira, para não travar exclusões e mesclagens do Chatwoot.
class CreateOutsiderCrmTables < ActiveRecord::Migration[7.1]
  def change
    create_units
    create_pipelines
    create_lost_reasons
    create_custom_field_definitions
    create_journeys
    create_opportunities
    add_opportunity_indexes
    create_tasks
    create_activities
    create_forwards
  end

  private

  def create_units
    create_table :outsider_crm_business_units do |t|
      t.references :account, null: false, index: true
      t.string :name, null: false
      t.text :description
      t.boolean :active, null: false, default: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :outsider_crm_business_units, [:account_id, :name], unique: true, name: 'idx_ocrm_units_on_account_name'

    create_table :outsider_crm_business_unit_members do |t|
      t.references :account, null: false, index: true
      t.references :business_unit, null: false, index: true, foreign_key: { to_table: :outsider_crm_business_units }
      t.references :user, null: false, index: true
      t.integer :role, null: false, default: 0
      t.timestamps
    end
    add_index :outsider_crm_business_unit_members, [:business_unit_id, :user_id], unique: true, name: 'idx_ocrm_members_on_unit_user'
  end

  def create_pipelines
    create_table :outsider_crm_pipelines do |t|
      t.references :account, null: false, index: true
      t.references :business_unit, null: false, index: true, foreign_key: { to_table: :outsider_crm_business_units }
      t.string :name, null: false
      t.boolean :active, null: false, default: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    create_table :outsider_crm_stages do |t|
      t.references :account, null: false, index: true
      t.references :pipeline, null: false, index: true, foreign_key: { to_table: :outsider_crm_pipelines }
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.integer :probability, null: false, default: 0
      t.integer :kind, null: false, default: 0
      t.string :color
      t.integer :sla_hours
      t.timestamps
    end
  end

  def create_lost_reasons
    create_table :outsider_crm_lost_reasons do |t|
      t.references :account, null: false, index: true
      t.string :name, null: false
      t.integer :kind, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end
  end

  def create_custom_field_definitions
    create_table :outsider_crm_custom_field_definitions do |t|
      t.references :account, null: false, index: true
      t.string :key, null: false
      t.string :label, null: false
      t.integer :field_type, null: false, default: 0
      t.jsonb :options, null: false, default: []
      t.boolean :required, null: false, default: false
      t.boolean :active, null: false, default: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :outsider_crm_custom_field_definitions, [:account_id, :key], unique: true, name: 'idx_ocrm_fields_on_account_key'
  end

  def create_journeys
    create_table :outsider_crm_journeys do |t|
      t.references :account, null: false, index: true
      t.bigint :contact_id, null: false
      t.bigint :company_id
      t.integer :status, null: false, default: 0
      t.string :origin
      t.datetime :closed_at
      t.timestamps
    end
    add_index :outsider_crm_journeys, [:account_id, :contact_id], name: 'idx_ocrm_journeys_on_account_contact'
  end

  def create_opportunities
    create_table :outsider_crm_opportunities do |t|
      t.references :account, null: false, index: true
      t.integer :display_id, null: false
      opportunity_links(t)
      t.string :title, null: false
      t.bigint :value_cents, null: false, default: 0
      t.string :currency, null: false, default: 'BRL'
      t.date :expected_close_on
      t.integer :probability
      t.integer :status, null: false, default: 0
      t.integer :position, null: false, default: 0
      t.jsonb :custom_fields, null: false, default: {}
      t.datetime :closed_at
      t.datetime :stage_changed_at
      t.timestamps
    end
  end

  def opportunity_links(table)
    table.references :journey, null: false, index: true, foreign_key: { to_table: :outsider_crm_journeys }
    table.references :business_unit, null: false, index: true, foreign_key: { to_table: :outsider_crm_business_units }
    table.references :pipeline, null: false, index: true, foreign_key: { to_table: :outsider_crm_pipelines }
    table.references :stage, null: false, index: true, foreign_key: { to_table: :outsider_crm_stages }
    table.references :lost_reason, index: true, foreign_key: { to_table: :outsider_crm_lost_reasons }
    table.references :forwarded_from, index: true, foreign_key: { to_table: :outsider_crm_opportunities }
    table.bigint :contact_id, null: false
    table.bigint :conversation_id
    table.bigint :owner_id
    table.bigint :created_by_id
  end

  def add_opportunity_indexes
    add_index :outsider_crm_opportunities, [:account_id, :display_id], unique: true, name: 'idx_ocrm_opps_on_account_display_id'
    add_index :outsider_crm_opportunities, [:account_id, :contact_id], name: 'idx_ocrm_opps_on_account_contact'
    add_index :outsider_crm_opportunities, [:account_id, :owner_id], name: 'idx_ocrm_opps_on_account_owner'
    add_index :outsider_crm_opportunities, [:account_id, :conversation_id], name: 'idx_ocrm_opps_on_account_conversation'
    add_index :outsider_crm_opportunities, [:stage_id, :position], name: 'idx_ocrm_opps_on_stage_position'
    # No máximo uma oportunidade aberta por contato em cada unidade
    add_index :outsider_crm_opportunities, [:account_id, :contact_id, :business_unit_id],
              unique: true, where: 'status = 0', name: 'idx_ocrm_opps_one_open_per_contact_unit'
  end

  def create_tasks
    create_table :outsider_crm_tasks do |t|
      t.references :account, null: false, index: true
      t.references :opportunity, null: false, index: true, foreign_key: { to_table: :outsider_crm_opportunities }
      t.bigint :assignee_id
      t.bigint :created_by_id
      t.bigint :completed_by_id
      t.string :title, null: false
      t.text :description
      t.integer :kind, null: false, default: 0
      t.datetime :due_at
      t.datetime :completed_at
      t.timestamps
    end
    add_index :outsider_crm_tasks, [:account_id, :assignee_id, :completed_at], name: 'idx_ocrm_tasks_on_account_assignee_done'
  end

  def create_activities
    create_table :outsider_crm_activities do |t|
      t.references :account, null: false, index: true
      t.references :opportunity, null: false, index: true, foreign_key: { to_table: :outsider_crm_opportunities }
      t.bigint :user_id
      t.bigint :message_id
      t.integer :kind, null: false, default: 0
      t.text :body
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :outsider_crm_activities, [:opportunity_id, :created_at], name: 'idx_ocrm_activities_on_opp_created'
  end

  def create_forwards
    create_table :outsider_crm_forwards do |t|
      t.references :account, null: false, index: true
      t.references :journey, null: false, index: true, foreign_key: { to_table: :outsider_crm_journeys }
      t.references :from_opportunity, null: false, index: true, foreign_key: { to_table: :outsider_crm_opportunities }
      t.references :to_opportunity, index: true, foreign_key: { to_table: :outsider_crm_opportunities }
      t.references :from_business_unit, null: false, index: true, foreign_key: { to_table: :outsider_crm_business_units }
      t.references :to_business_unit, null: false, index: true, foreign_key: { to_table: :outsider_crm_business_units }
      t.references :reason, index: true, foreign_key: { to_table: :outsider_crm_lost_reasons }
      t.bigint :requested_by_id
      t.bigint :decided_by_id
      t.integer :status, null: false, default: 0
      t.integer :attempt_number, null: false, default: 1
      t.text :notes
      t.datetime :decided_at
      t.timestamps
    end
  end
end
