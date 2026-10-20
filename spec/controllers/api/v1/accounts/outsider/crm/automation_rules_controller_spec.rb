require 'rails_helper'

RSpec.describe 'Outsider CRM automation rules API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:target_seller) { create(:user, account: account, role: :agent) }
  let(:origin_unit) { crm_unit(account, name: 'Locação') }
  let(:target_unit) { crm_unit(account, name: 'Seminovos') }
  let(:base_url) { "/api/v1/accounts/#{account.id}/outsider/crm" }
  let(:attributes) do
    { name: 'Boas-vindas Seminovos', trigger: 'created', conditions: { business_unit_id: target_unit.id },
      actions: [{ type: 'create_task', title: 'Apresentar seminovos', kind: 'call', due_in_hours: 2 }] }
  end

  before do
    crm_pipeline(account, target_unit, name: 'Seminovos')
    origin_unit.members.create!(account: account, user: seller, role: :seller)
    target_unit.members.create!(account: account, user: target_seller, role: :seller)
  end

  def call(method, path, user, params = {})
    public_send(method, "#{base_url}/#{path}", params: params, headers: user.create_new_auth_token, as: :json)
    response.parsed_body.presence
  end

  it 'lets the CRM administrator create, list, change and delete rules' do
    created = call(:post, 'automation_rules', admin, automation_rule: attributes)
    expect(response).to have_http_status(:created)
    expect(created).to include('id' => 1, 'name' => 'Boas-vindas Seminovos', 'active' => true)

    call(:patch, 'automation_rules/1', admin, automation_rule: { active: false })
    expect(call(:get, 'automation_rules', admin)).to match([include('id' => 1, 'active' => false)])

    call(:delete, 'automation_rules/1', admin)
    expect(response).to have_http_status(:no_content)
    expect(call(:get, 'automation_rules', admin)).to be_nil
  end

  it 'answers with field codes for an invalid rule and 404 for an unknown one' do
    call(:post, 'automation_rules', admin, automation_rule: attributes.merge(name: '', actions: [{ type: 'create_task', title: '' }]))
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'invalid', 'fields' => ['name_blank', 'actions.0.title_blank'])

    call(:patch, 'automation_rules/9', admin, automation_rule: { active: true })
    expect(response).to have_http_status(:not_found)
  end

  it 'keeps the rules away from people who are not CRM administrators' do
    call(:get, 'automation_rules', seller)
    expect(response).to have_http_status(:forbidden)
    call(:post, 'automation_rules', seller, automation_rule: attributes)
    expect(response).to have_http_status(:forbidden)
  end

  it 'runs the "created" rule of the destination unit when a deal arrives by forwarding' do
    call(:post, 'automation_rules', admin, automation_rule: attributes)
    origin = crm_opportunity(account, origin_unit, owner: seller, title: 'Frota 3x')
    reason = Outsider::Crm::LostReason.create!(account: account, name: 'Quer usado', kind: :forward)

    call(:post, "opportunities/#{origin.id}/forward", seller, forward: { to_business_unit_id: target_unit.id, reason_id: reason.id,
                                                                         owner_id: target_seller.id })

    target = Outsider::Crm::Opportunity.find_by!(business_unit_id: target_unit.id)
    expect(target.tasks.pluck(:title, :kind, :assignee_id)).to eq([['Apresentar seminovos', 'call', target_seller.id]])
    expect(origin.tasks).to be_empty
  end

  it 'runs the timed rules from "Verificar agora"' do
    call(:post, 'automation_rules', admin, automation_rule: attributes.merge(trigger: 'no_next_task', wait_hours: 1))
    travel_to(2.hours.ago) { crm_opportunity(account, target_unit, owner: target_seller) }

    expect(call(:post, 'automations/stalled', admin)).to eq('created' => 0, 'rules' => 1)
  end
end
