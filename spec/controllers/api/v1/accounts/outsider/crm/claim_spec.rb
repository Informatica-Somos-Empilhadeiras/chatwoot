require 'rails_helper'

RSpec.describe 'Outsider CRM claim unowned deals', type: :request do
  # negócio sem responsável na unidade: os vendedores dela veem na tela principal e podem pegar
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:ana) { create(:user, account: account, role: :agent) }
  let(:bia) { create(:user, account: account, role: :agent) }
  let(:outsider) { create(:user, account: account, role: :agent) }
  let(:unit) { crm_unit(account, name: 'Filial DF') }
  let(:other_unit) { crm_unit(account, name: 'Matriz') }
  let(:pipeline) { crm_pipeline(account, unit) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/outsider/crm" }

  before do
    unit.members.create!(account: account, user: ana, role: :seller)
    unit.members.create!(account: account, user: bia, role: :seller)
    other_unit.members.create!(account: account, user: outsider, role: :seller)
  end

  def deal(**attrs)
    crm_opportunity(account, unit, pipeline: pipeline, **attrs)
  end

  def forwarded_deal
    origin = crm_opportunity(account, other_unit, owner: outsider)
    Outsider::Crm::OpportunityForwarder.new(origin, access: Outsider::Crm::RuleRunner::SystemAccess.new(account.id), user: nil,
                                                    params: { to_business_unit_id: unit.id, pipeline_id: pipeline.id }).perform.to_opportunity
  end

  def claim(user, opportunity)
    post "#{base_url}/opportunities/#{opportunity.id}/claim", headers: user.create_new_auth_token, as: :json
  end

  it 'shows the unowned deals of the unit to its sellers, besides their own' do
    pool = deal(title: 'Na fila')
    mine = deal(title: 'Meu', owner: ana)
    deal(title: 'Da Bia', owner: bia)

    get "#{base_url}/opportunities", headers: ana.create_new_auth_token, as: :json
    expect(response.parsed_body['payload'].pluck('id')).to contain_exactly(pool.id, mine.id)
    expect(response.parsed_body['payload'].find { |item| item['id'] == pool.id }).to include('can_claim' => true, 'can_edit' => false)

    get "#{base_url}/opportunities/unowned", headers: ana.create_new_auth_token, as: :json
    expect(response.parsed_body).to eq('count' => 1)

    get "#{base_url}/opportunities/unowned", headers: outsider.create_new_auth_token, as: :json
    expect(response.parsed_body).to eq('count' => 0)
  end

  it 'gives the deal to whoever takes it first' do
    opportunity = deal

    claim(ana, opportunity)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('owner' => include('id' => ana.id), 'can_edit' => true, 'can_claim' => false)
    expect(opportunity.activities.owner_changed.last).to have_attributes(user_id: ana.id)

    claim(bia, opportunity)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('error' => 'already_taken')
    expect(opportunity.reload.owner_id).to eq(ana.id)
  end

  it 'refuses people outside the unit, closed deals and deals that already have an owner' do
    claim(outsider, deal)
    expect(response).to have_http_status(:not_found)

    claim(ana, deal(status: :lost))
    expect(response).to have_http_status(:unprocessable_entity)

    claim(ana, deal(owner: bia))
    expect(response).to have_http_status(:unprocessable_entity)

    claim(admin, deal)
    expect(response).to have_http_status(:ok)
  end

  it 'creates the contact task for a forwarded deal and clears the notice for everybody' do
    target = forwarded_deal
    get "#{base_url}/received_forwards", headers: bia.create_new_auth_token, as: :json
    expect(response.parsed_body['payload'].first).to include('opportunity_id' => target.id, 'can_claim' => true)

    claim(ana, target)

    expect(target.tasks.pending.pluck(:assignee_id, :kind)).to eq([[ana.id, 'call']])
    %w[ana bia].each do |name|
      get "#{base_url}/received_forwards", headers: send(name).create_new_auth_token, as: :json
      expect(response.parsed_body['payload']).to be_empty
    end
  end
end
