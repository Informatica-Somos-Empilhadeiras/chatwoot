# OUTSIDER: orçamento de peças e serviços feito no chat e gravado no ERP Mais Prático (separado da proposta comercial
# do CRM). O rascunho fica aqui até "Gravar no ERP"; depois guarda o número que o ERP deu. Os envios (WhatsApp/e-mail)
# guardam o PDF enviado. approval: quem liberou o desconto acima do limite (código e nome do ERP, nunca a senha).
# Só cria tabelas novas (rollback remove). Ver Outsider::Erp::Budget.
class CreateOutsiderErpBudgets < ActiveRecord::Migration[7.1]
  def change
    create_budgets
    create_sends
  end

  private

  def create_budgets
    create_table :outsider_erp_budgets do |t|
      t.bigint :account_id, null: false
      t.bigint :contact_id, :conversation_id, :opportunity_id, :user_id
      t.string :company, null: false
      t.integer :customer_code
      t.string :customer_name
      t.integer :status, null: false, default: 0
      t.integer :erp_number
      t.datetime :erp_created_at
      t.jsonb :terms, null: false, default: {}
      t.jsonb :items, null: false, default: []
      t.jsonb :erp_result, null: false, default: {}
      t.jsonb :approval, null: false, default: {}
      t.timestamps
    end
    add_index :outsider_erp_budgets, [:account_id, :contact_id]
    add_index :outsider_erp_budgets, [:account_id, :company, :erp_number],
              unique: true, where: 'erp_number IS NOT NULL', name: 'index_outsider_erp_budgets_on_erp_number'
  end

  def create_sends
    create_table :outsider_erp_budget_sends do |t|
      t.bigint :account_id, null: false
      t.bigint :budget_id, null: false
      t.bigint :user_id
      t.integer :channel, null: false, default: 0
      t.jsonb :recipients, null: false, default: []
      t.string :subject
      t.integer :status, null: false, default: 0
      t.string :error
      t.bigint :conversation_id
      t.bigint :message_id
      t.string :digest
      t.timestamps
    end
    add_index :outsider_erp_budget_sends, :budget_id
  end
end
