# OUTSIDER: ligações da central de telefonia (Entrega 22). Uma linha por ligação, gravada pelos avisos que a
# central (Asterisk) manda ao Chatwoot: começo, atendimento e fim. linkedid é o id da ligação na central.
class CreateOutsiderVoiceCalls < ActiveRecord::Migration[7.1]
  def change
    create_table :outsider_voice_calls do |t|
      t.bigint :account_id, null: false
      t.string :linkedid, null: false
      t.integer :direction, :status, null: false, default: 0
      t.string :from_number, :to_number, :did, :hangup_cause
      t.string :state_code, limit: 2
      t.bigint :user_id, :contact_id, :opportunity_id, :task_id, :returned_by_id
      t.datetime :started_at, null: false
      t.datetime :answered_at, :ended_at, :returned_at
      t.integer :talk_seconds, null: false, default: 0
      t.timestamps
    end
    add_index :outsider_voice_calls, :linkedid, unique: true
    add_index :outsider_voice_calls, [:account_id, :started_at]
    add_index :outsider_voice_calls, [:account_id, :user_id, :started_at], name: 'idx_ovoice_calls_on_account_user_started'
    add_index :outsider_voice_calls, [:account_id, :contact_id]
  end
end
