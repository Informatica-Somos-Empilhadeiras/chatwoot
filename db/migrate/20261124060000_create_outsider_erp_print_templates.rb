# OUTSIDER: modelos de relatório (impressão) da OS e do orçamento do ERP, montados no estúdio (Outsider::Erp::Prints).
# kind: os | quote; content: identidade visual, campos (quais e em que ordem) e os blocos; builtin: a chave do modelo
# padrão de onde ele veio (para o selo "Padrão" e para restaurar). Qual modelo cada tipo de atendimento usa fica em
# accounts.internal_attributes (Outsider::Erp::Prints::Bindings). Só cria a tabela.
class CreateOutsiderErpPrintTemplates < ActiveRecord::Migration[7.1]
  def change
    create_table :outsider_erp_print_templates do |t|
      t.bigint :account_id, null: false
      t.string :kind, null: false
      t.string :name, null: false
      t.string :builtin
      t.jsonb :content, null: false, default: {}
      t.bigint :created_by_id
      t.timestamps
    end
    add_index :outsider_erp_print_templates, [:account_id, :kind]
  end
end
