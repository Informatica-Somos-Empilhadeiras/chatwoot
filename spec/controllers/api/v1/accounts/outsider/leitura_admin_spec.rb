require 'rails_helper'

RSpec.describe 'Outsider leitura por administrador', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, agent_last_seen_at: nil) }
  let(:url) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/update_last_seen" }

  before { create(:inbox_member, user: agent, inbox: conversation.inbox) }

  def abrir(user, params = {})
    post url, params: params, headers: user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    conversation.reload
  end

  it 'keeps an unassigned conversation unread when an admin opens it' do
    abrir(admin)

    expect(conversation.agent_last_seen_at).to be_nil
    expect(response.parsed_body['unread_count']).to eq(conversation.unread_incoming_messages.count)
  end

  it 'keeps another agent conversation unread when an admin opens it' do
    conversation.update!(assignee: agent)

    abrir(admin)

    expect(conversation.agent_last_seen_at).to be_nil
    expect(conversation.assignee_last_seen_at).to be_nil
  end

  it 'still clears the admin own notifications' do
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
    notification = create(:notification, account: account, user: admin, primary_actor: conversation, read_at: nil)

    abrir(admin)

    expect(notification.reload.read_at).to be_present
  end

  it 'marks the admin own conversation as read' do
    conversation.update!(assignee: admin)

    abrir(admin)

    expect(conversation.agent_last_seen_at).to be_present
    expect(conversation.assignee_last_seen_at).to be_present
  end

  it 'marks as read when the admin turned the option off in the profile' do
    admin.update!(ui_settings: { 'outsider_marcar_lida_outros' => true })

    abrir(admin)

    expect(conversation.agent_last_seen_at).to be_present
  end

  it 'marks as read when the admin asks explicitly' do
    abrir(admin, outsider_forcar: true)

    expect(conversation.agent_last_seen_at).to be_present
  end

  it 'does not change what agents do' do
    abrir(agent)

    expect(conversation.agent_last_seen_at).to be_present
  end
end
