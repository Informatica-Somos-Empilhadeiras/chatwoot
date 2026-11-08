require 'rails_helper'

RSpec.describe 'Outsider aviso novo (push)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Admin') }
  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana') }
  let(:bruno) { create(:user, account: account, role: :agent, name: 'Bruno') }
  let(:inbox) { create(:inbox, account: account, name: 'WhatsApp Vendas SP') }
  let(:contact) { create(:contact, account: account, name: 'Marcos Pereira') }
  let(:sent) { [] }

  around do |example|
    ClimateControl.modify(FRONTEND_URL: 'https://chat.exemplo.com.br', OUTSIDER_PUSH: 'on') { example.run }
  end

  before do
    allow(VapidService).to receive_messages(public_key: 'BPublic', private_key: 'private')
    allow(WebPush).to receive(:payload_send) { |args| sent << args.merge(payload: JSON.parse(args[:message])) }
    [ana, bruno].each { |user| create(:inbox_member, user: user, inbox: inbox) }
  end

  def device_for(user, number = 1)
    user.notification_subscriptions.create!(
      subscription_type: 'browser_push', identifier: "https://push.example/#{user.id}/#{number}",
      subscription_attributes: { 'endpoint' => "https://push.example/#{user.id}/#{number}", 'p256dh' => 'p', 'auth' => 'a' }
    )
  end

  def conversation_with(assignee: nil, status: :open, person: contact)
    create(:conversation, account: account, inbox: inbox, contact: person, assignee: assignee, status: status)
  end

  def customer_message(conversation, content = 'Bom dia! Vocês têm empilhadeira 2,5 t?', **attributes)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                     sender: contact, content: content, **attributes)
  end

  it 'avisa todos da caixa quando a conversa não tem responsável e só o responsável depois' do
    device_for(ana)
    device_for(bruno)
    conversation = conversation_with

    Outsider::Push::CustomerMessage.new(customer_message(conversation)).perform
    expect(sent.pluck(:endpoint)).to contain_exactly(%r{/#{ana.id}/1}, %r{/#{bruno.id}/1})
    payload = sent.first[:payload]
    expect(payload).to include('outsider' => 1, 'title' => 'Marcos Pereira · WhatsApp Vendas SP',
                               'body' => 'Bom dia! Vocês têm empilhadeira 2,5 t?', 'tag' => "c-#{conversation.id}",
                               'path' => "/app/accounts/#{account.id}/conversations/#{conversation.display_id}")
    expect(Outsider::Push.read_data(payload['read'])).to include('c' => conversation.id)

    sent.clear
    conversation.update!(assignee: bruno)
    Outsider::Push::CustomerMessage.new(customer_message(conversation, 'Ainda está aí?')).perform
    expect(sent.pluck(:endpoint)).to contain_exactly(%r{/#{bruno.id}/1})
  end

  it 'respeita o que a pessoa desligou e não avisa nota, robô nem conversa silenciada' do
    device_for(ana)
    device_for(bruno)
    Outsider::PushSetting.for(bruno, account).update!(prefs: { 'wa_unassigned' => false })
    conversation = conversation_with

    Outsider::Push::CustomerMessage.new(customer_message(conversation)).perform
    expect(sent.pluck(:endpoint)).to contain_exactly(%r{/#{ana.id}/1})

    sent.clear
    Outsider::Push::CustomerMessage.new(customer_message(conversation, 'nota', private: true)).perform
    Outsider::Push::CustomerMessage.new(customer_message(conversation_with(status: :pending))).perform
    # silenciar bloqueia o contato (vale para as conversas dele)
    muted = conversation_with(person: create(:contact, account: account, name: 'Silenciado'))
    muted.mute!
    Outsider::Push::CustomerMessage.new(customer_message(muted)).perform
    expect(sent).to be_empty

    Outsider::PushSetting.for(ana, account).update!(prefs: { 'hide_content' => true })
    Outsider::Push::CustomerMessage.new(customer_message(conversation, 'segredo')).perform
    expect(sent.first[:payload]['body']).to eq('Nova mensagem de Marcos Pereira')
  end

  it 'manda o aviso pelo Sidekiq quando chega mensagem de cliente' do
    listeners = Rails.configuration.dispatcher.async_dispatcher.send(:local_registrations).map { |r| r.listener.class.name }
    expect(listeners.count('Outsider::PushListener')).to eq(1)

    message = customer_message(conversation_with)
    event = Events::Base.new('message.created', Time.zone.now, message: message)
    expect { Outsider::PushListener.instance.message_created(event) }
      .to have_enqueued_job(Outsider::Push::DeliverJob).with('customer', message.id)
  end

  it 'avisa do Teams: chat 1:1 e @menção sim, grupo sem menção não' do
    device_for(ana)
    link = Outsider::TeamsLink.create!(account: account, user: ana, ms_user_id: 'ms-ana', status: 'active')
    chat = link.threads.create!(kind: 'chat', chat_id: '19:a', chat_type: 'oneOnOne', title: 'Ricardo Mendes')
    group = link.threads.create!(kind: 'chat', chat_id: '19:g', chat_type: 'group', title: 'Vendas Sul')

    one = chat.messages.create!(sender_name: 'Ricardo Mendes', content: 'Segue o contrato', sent_at: Time.current)
    Outsider::Push::TeamsMessage.new(one).perform
    expect(sent.last[:payload]).to include('title' => 'Ricardo Mendes · Teams (chat)', 'body' => 'Segue o contrato',
                                           'path' => "/app/accounts/#{account.id}/teams/chats/#{chat.id}", 'kind' => 'teams')

    quiet = group.messages.create!(sender_name: 'Paula', content: 'Bom dia', sent_at: Time.current)
    expect(Outsider::Push::TeamsMessage.new(quiet).perform).to eq(0)

    called = group.messages.create!(sender_name: 'Paula', content: '@Ana fechado em 4%', mentions_me: true, sent_at: Time.current)
    Outsider::Push::TeamsMessage.new(called).perform
    expect(sent.last[:payload]).to include('title' => 'Paula · Teams › Vendas Sul', 'body' => 'Mencionou você: @Ana fechado em 4%')

    mine = chat.messages.create!(sender_name: 'Ana', content: 'ok', mine: true, sent_at: Time.current)
    expect(Outsider::Push::TeamsMessage.new(mine).perform).to eq(0)
  end

  it 'troca o push do Chatwoot no navegador pelo novo e marca como lida pelo botão do aviso' do
    device_for(ana)
    conversation = conversation_with(assignee: ana)
    notification = Notification.create!(notification_type: 'conversation_assignment', user: ana, account: account,
                                        primary_actor: conversation)
    sent.clear
    Notification::PushNotificationService.new(notification: notification).perform
    expect(sent).to be_empty

    Outsider::Push::ChatwootNotice.new(notification).perform
    expect(sent.last[:payload]['title']).to eq('Marcos Pereira · WhatsApp Vendas SP')

    token = sent.last[:payload]['read']
    post '/outsider/push/read', params: { token: token }, as: :json
    expect(response).to have_http_status(:no_content)
    expect(conversation.reload.agent_last_seen_at).to be_present
    expect(conversation.assignee_last_seen_at).to be_present

    post '/outsider/push/read', params: { token: 'falso' }, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'guarda o aparelho, muda as escolhas e mostra a equipe só para o administrador' do
    url = "/api/v1/accounts/#{account.id}/outsider/push"
    get url, headers: ana.create_new_auth_token, as: :json
    expect(response.parsed_body['prefs']).to include('wa_assigned' => true, 'teams_groups' => false)
    expect(response.parsed_body['team']).to eq([])

    post "#{url}/devices", headers: ana.create_new_auth_token, as: :json,
                           params: { endpoint: 'https://push.example/ana-pc', p256dh: 'p', auth: 'a', label: 'Chrome · Windows' }
    expect(response.parsed_body['devices'].first).to include('label' => 'Chrome · Windows', 'tail' => 'https://push.example/ana-pc'.last(24))
    expect(ana.notification_subscriptions.browser_push.count).to eq(1)

    patch url, headers: ana.create_new_auth_token, as: :json, params: { prefs: { teams_groups: true, wa_groups: false } }
    expect(response.parsed_body['prefs']).to include('teams_groups' => true, 'wa_groups' => false, 'wa_assigned' => true)

    post "#{url}/permission", headers: bruno.create_new_auth_token, as: :json, params: { permission: 'denied' }
    post "#{url}/test", headers: ana.create_new_auth_token, as: :json
    expect(response.parsed_body['sent']).to eq(1)

    post "#{url}/remind/#{bruno.id}", headers: ana.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)

    get url, headers: admin.create_new_auth_token, as: :json
    team = response.parsed_body['team'].index_by { |row| row['name'] }
    expect(team['Ana']).to include('devices' => 1, 'status' => 'active')
    expect(team['Bruno']).to include('status' => 'blocked')
    expect(team['Admin']).to include('status' => 'never')

    post "#{url}/remind/#{admin.id}", headers: admin.create_new_auth_token, as: :json
    expect(Outsider::PushSetting.for(admin, account).reminded_at).to be_present
  end
end
