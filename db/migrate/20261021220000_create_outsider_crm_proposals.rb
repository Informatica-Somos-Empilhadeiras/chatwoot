# OUTSIDER: propostas do CRM (catálogo de máquinas e acessórios, modelos, propostas, itens e envios).
# Só cria tabelas novas com prefixo outsider_crm_; nenhuma tabela do Chatwoot é alterada. Contato,
# usuários, conversa e mensagem ficam por id, sem chave estrangeira, como no resto do CRM. Imagens e PDFs
# usam o armazenamento de arquivos do Chatwoot (Active Storage): um arquivo só, apontado por quem usa.
class CreateOutsiderCrmProposals < ActiveRecord::Migration[7.1]
  def change
    create_products
    create_templates
    create_proposals
    create_items
    create_sends
  end

  private

  def create_products
    create_table :outsider_crm_products do |t|
      t.references :account, null: false, index: true
      t.integer :kind, null: false, default: 0
      t.string :name, null: false
      t.string :code
      t.string :brand
      t.text :description
      t.jsonb :specs, null: false, default: []
      t.jsonb :features, null: false, default: []
      t.bigint :sale_price_cents, null: false, default: 0
      t.bigint :rental_price_cents, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.bigint :created_by_id
      t.timestamps
    end
  end

  def create_templates
    create_table :outsider_crm_proposal_templates do |t|
      t.references :account, null: false, index: true
      t.string :name, null: false
      t.integer :kind, null: false, default: 0
      t.jsonb :content, null: false, default: {}
      t.jsonb :layout, null: false, default: {}
      t.boolean :active, null: false, default: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end
  end

  def create_proposals
    create_table :outsider_crm_proposals do |t|
      t.references :account, null: false, index: true
      t.integer :number, null: false
      t.integer :kind, null: false, default: 0
      t.integer :status, null: false, default: 0
      t.string :title, null: false
      proposal_links(t)
      proposal_contents(t)
      t.timestamps
    end
    add_index :outsider_crm_proposals, [:account_id, :number], unique: true, name: 'idx_ocrm_proposals_on_account_number'
    add_index :outsider_crm_proposals, [:account_id, :contact_id], name: 'idx_ocrm_proposals_on_account_contact'
    add_index :outsider_crm_proposals, [:account_id, :owner_id], name: 'idx_ocrm_proposals_on_account_owner'
  end

  def proposal_links(table)
    table.bigint :contact_id, null: false
    table.references :opportunity, index: true, foreign_key: { to_table: :outsider_crm_opportunities, on_delete: :nullify }
    table.references :business_unit, index: true, foreign_key: { to_table: :outsider_crm_business_units, on_delete: :nullify }
    table.references :template, null: false, index: true, foreign_key: { to_table: :outsider_crm_proposal_templates }
    table.bigint :owner_id
    table.bigint :created_by_id
  end

  def proposal_contents(table)
    table.date :issued_on, null: false
    table.date :valid_until
    table.jsonb :customer, null: false, default: {}
    table.jsonb :conditions, null: false, default: []
    table.jsonb :signer, null: false, default: {}
    table.text :notes
    table.bigint :total_cents, null: false, default: 0
    table.string :currency, null: false, default: 'BRL'
    table.datetime :sent_at
    table.datetime :decided_at
  end

  def create_items
    create_table :outsider_crm_proposal_items do |t|
      t.references :account, null: false, index: true
      t.references :proposal, null: false, index: true, foreign_key: { to_table: :outsider_crm_proposals, on_delete: :cascade }
      t.references :product, index: true, foreign_key: { to_table: :outsider_crm_products }
      t.integer :position, null: false, default: 0
      t.string :description, null: false
      t.decimal :quantity, precision: 12, scale: 2, null: false, default: 1
      t.bigint :unit_price_cents, null: false, default: 0
      t.bigint :discount_cents, null: false, default: 0
      t.bigint :total_cents, null: false, default: 0
      t.boolean :show_details, null: false, default: true
      t.jsonb :details, null: false, default: {}
      t.timestamps
    end
  end

  # Envio por WhatsApp ou e-mail (Entrega 15): o PDF enviado fica ligado aqui e à mensagem da conversa,
  # apontando para o mesmo arquivo
  def create_sends
    create_table :outsider_crm_proposal_sends do |t|
      t.references :account, null: false, index: true
      t.references :proposal, null: false, index: true, foreign_key: { to_table: :outsider_crm_proposals, on_delete: :cascade }
      t.integer :channel, null: false, default: 0
      t.bigint :contact_id
      t.string :recipient
      t.bigint :conversation_id
      t.bigint :message_id
      t.bigint :user_id
      t.integer :status, null: false, default: 0
      t.string :error
      t.string :digest
      t.timestamps
    end
  end
end
