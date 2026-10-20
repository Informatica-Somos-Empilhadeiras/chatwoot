require 'rails_helper'

# Fluxo completo do CRM pela API, do jeito que a equipe usa: liga as automações, cria o negócio a
# partir da conversa, anda no Kanban, agenda tarefa, encaminha para outra unidade, ganha lá e confere
# que o relatório, o Kanban e a linha do tempo contam a mesma história.
RSpec.describe 'Outsider CRM full flow', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:target_seller) { create(:user, account: account, role: :agent) }
  let(:origin_unit) { crm_unit(account, name: 'Locação') }
  let(:target_unit) { crm_unit(account, name: 'Seminovos') }
  let!(:origin_pipeline) { crm_pipeline(account, origin_unit, name: 'Locação') }
  let!(:target_pipeline) { crm_pipeline(account, target_unit, name: 'Seminovos') }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Gustavo Teles') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, assignee: seller) }
  let(:reason) { Outsider::Crm::LostReason.create!(account: account, name: 'Quer comprar usado', kind: :forward) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/outsider/crm" }
  let(:target_id) { Outsider::Crm::Forward.last.to_opportunity_id }

  before do
    create(:label, account: account, title: 'cliente-ganho')
    origin_unit.members.create!(account: account, user: seller, role: :seller)
    target_unit.members.create!(account: account, user: target_seller, role: :seller)
    [seller, target_seller].each { |user| create(:inbox_member, inbox: inbox, user: user) }

    call(:patch, 'settings', admin, settings: { automation_won_label: 'cliente-ganho', automation_close_tasks: true })

    created = call(:post, 'opportunities', seller, opportunity: {
                     business_unit_id: origin_unit.id, contact_id: contact.id, title: 'Frota 3x', value: '52.000,00',
                     conversation_display_id: conversation.display_id
                   })
    proposal = origin_pipeline.stages.find_by(name: 'Proposta')
    call(:patch, "opportunities/#{created['id']}/move", seller, stage_id: proposal.id, index: 0)
    call(:post, "opportunities/#{created['id']}/tasks", seller, task: { title: 'Enviar proposta', due_at: 1.day.from_now })
    call(:post, "opportunities/#{created['id']}/forward", seller, forward: {
           to_business_unit_id: target_unit.id, reason_id: reason.id, owner_id: target_seller.id,
           create_task: true, complete_tasks: true, assign_conversation: true
         })
    call(:patch, "opportunities/#{target_id}", target_seller, opportunity: { status: 'won' })
  end

  def call(method, path, user, params = {})
    public_send(method, "#{base_url}/#{path}", params: params, headers: user.create_new_auth_token, as: :json)
    expect(response).to have_http_status(:success), response.body
    response.parsed_body
  end

  it 'runs the automations on the win and records them in the timeline' do
    expect(conversation.reload).to have_attributes(label_list: ['cliente-ganho'], assignee_id: target_seller.id)
    expect(Outsider::Crm::Task.where(opportunity_id: target_id).pending).to be_empty

    timeline = call(:get, "opportunities/#{target_id}/activities", target_seller)['payload']
    rules = timeline.select { |item| item['kind'] == 'automation' }.map { |item| item['metadata']['rule'] }
    expect(rules).to contain_exactly('won_label', 'close_tasks')
  end

  it 'adds up the whole flow in the account report' do
    report = call(:get, 'reports', admin, period: 'month')

    expect(report['summary']).to include('won_count' => 1, 'won_value_cents' => 5_200_000, 'lost_count' => 0, 'forwarded_count' => 1,
                                         'received_count' => 1, 'created_count' => 2, 'open_count' => 0, 'conversion_rate' => 100.0)
    units = report['units'].index_by { |row| row['name'] }
    expect(units['Locação']).to include('forwarded_count' => 1, 'won_count' => 0, 'open_count' => 0)
    expect(units['Seminovos']).to include('won_count' => 1, 'received_count' => 1, 'conversion_rate' => 100.0)
    expect(report['forward_reasons']).to eq([{ 'id' => reason.id, 'name' => 'Quer comprar usado', 'count' => 1, 'value_cents' => 5_200_000 }])
  end

  it 'shows the origin funnel passing both stages and leaving forwarded, not won' do
    funnel = call(:get, 'reports', admin, pipeline_id: origin_pipeline.id)['funnel']

    expect(funnel['stages'].map { |stage| [stage['name'], stage['reached_count'], stage['exits_count']] })
      .to eq([['Qualificação', 1, 1], ['Proposta', 1, 1]])
    expect(funnel['won']).to eq('count' => 0, 'conversion_rate' => 0.0)
  end

  it 'keeps the report funnel equal to the Kanban columns' do
    [origin_pipeline, target_pipeline].each do |pipeline|
      board = call(:get, 'opportunities/board', admin, pipeline_id: pipeline.id)
      report_stages = call(:get, 'reports', admin, pipeline_id: pipeline.id)['funnel']['stages']
      expect(board['stages'].pluck('count')).to eq(report_stages.pluck('open_count'))
    end
  end

  it 'shows a seller of the origin only their own unit' do
    report = call(:get, 'reports', seller, period: 'month')

    expect(report['units'].pluck('name')).to eq(['Locação'])
    expect(report['summary']).to include('won_count' => 0, 'forwarded_count' => 1)
  end
end
