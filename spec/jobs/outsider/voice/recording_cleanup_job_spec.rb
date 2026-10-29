require 'rails_helper'

RSpec.describe Outsider::Voice::RecordingCleanupJob do
  let(:account) { create(:account) }
  let(:settings) { Outsider::Voice::Settings.new(account) }

  before { settings.update('enabled' => true, 'recording_days' => 30) }

  def recorded_call(started_at)
    call = Outsider::Voice::Call.create!(account_id: account.id, linkedid: SecureRandom.hex(4), direction: :inbound, status: :answered,
                                         from_number: '+5562998100003', to_number: '6232345678', started_at: started_at)
    call.recording.attach(io: StringIO.new('webm'), filename: 'ligacao.webm', content_type: 'audio/webm')
    call
  end

  it 'deletes the recordings older than the account limit and keeps the newer ones' do
    old = recorded_call(31.days.ago)
    recent = recorded_call(29.days.ago)

    described_class.perform_now

    expect(old.reload.recording).not_to be_attached
    expect(recent.reload.recording).to be_attached
  end

  it 'keeps the file when it was forwarded to a conversation' do
    old = recorded_call(40.days.ago)
    blob = old.recording.blob
    message = create(:message, account: account)
    message.attachments.create!(account_id: account.id, file_type: :audio, file: blob.signed_id)

    described_class.perform_now

    expect(old.reload.recording).not_to be_attached
    expect(ActiveStorage::Blob.exists?(blob.id)).to be(true)
    expect(message.attachments.first.file.blob).to eq(blob)
  end
end
