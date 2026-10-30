# OUTSIDER: pedidos de transferência de conversa entre agentes. Quem pede vê na busca que a conversa
# está com outro agente; quem está com ela aceita ou recusa. Sem chaves estrangeiras para as tabelas
# do Chatwoot (apagar conversa ou agente continua funcionando).
class CreateOutsiderTransferRequests < ActiveRecord::Migration[7.1]
  def change
    create_table :outsider_transfer_requests do |t|
      t.bigint :account_id, :conversation_id, :requester_id, :holder_id, null: false
      t.integer :status, null: false, default: 0
      t.string :note, limit: 500
      t.datetime :decided_at, :acknowledged_at
      t.timestamps
    end
    add_index :outsider_transfer_requests, [:account_id, :holder_id, :status], name: 'idx_otransfer_requests_on_holder'
    add_index :outsider_transfer_requests, [:account_id, :requester_id, :status], name: 'idx_otransfer_requests_on_requester'
    add_index :outsider_transfer_requests, [:conversation_id, :requester_id], unique: true, where: 'status = 0',
                                                                              name: 'idx_otransfer_requests_one_pending'
  end
end
