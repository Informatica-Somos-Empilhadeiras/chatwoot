require 'rails_helper'

RSpec.describe 'Outsider CRM deleting items', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:manager) { create(:user, account: account, role: :agent) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:unit) { crm_unit(account, name: 'Locação') }
  let(:other_unit) { crm_unit(account, name: 'Seminovos') }
  let!(:pipeline) { crm_pipeline(account, unit) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/outsider/crm" }

  before do
    unit.members.create!(account: account, user: manager, role: :manager)
    unit.members.create!(account: account, user: seller, role: :seller)
  end

  def delete_as(user, path)
    delete "#{base_url}/#{path}", headers: user.create_new_auth_token, as: :json
    response.parsed_body.presence
  end

  describe 'units and pipelines' do
    it 'deletes an unused unit with its pipelines, stages and members' do
      delete_as(admin, "business_units/#{unit.id}")

      expect(response).to have_http_status(:no_content)
      expect(Outsider::Crm::BusinessUnit.exists?(unit.id)).to be(false)
      expect(Outsider::Crm::Stage.where(pipeline_id: pipeline.id)).to be_empty
      expect(Outsider::Crm::BusinessUnitMember.where(business_unit_id: unit.id)).to be_empty
    end

    it 'refuses while there are deals or rules pointing to them, saying what blocks it' do
      Outsider::Crm::AutomationRules.new(account).create(name: 'Boas-vindas', trigger: 'created', conditions: { pipeline_id: pipeline.id },
                                                         actions: [{ type: 'add_note', body: 'Oi' }])
      expect(delete_as(manager, "pipelines/#{pipeline.id}")).to eq('error' => 'in_use', 'reason' => 'used_by_rules', 'names' => 'Boas-vindas')

      2.times { crm_opportunity(account, unit, pipeline: pipeline) }
      expect(delete_as(admin, "business_units/#{unit.id}")).to eq('error' => 'in_use', 'reason' => 'has_opportunities', 'count' => 2)
      expect(delete_as(manager, "pipelines/#{pipeline.id}")).to include('reason' => 'has_opportunities', 'count' => 2)
      expect(Outsider::Crm::Pipeline.exists?(pipeline.id)).to be(true)
    end

    it 'keeps sellers from deleting pipelines and units' do
      delete_as(seller, "pipelines/#{pipeline.id}")
      expect(response).to have_http_status(:forbidden)
      delete_as(manager, "business_units/#{unit.id}")
      expect(response).to have_http_status(:forbidden)
    end
  end

  it 'deletes a custom field nobody filled in and refuses one that is in use' do
    unused = Outsider::Crm::CustomFieldDefinition.create!(account: account, key: 'frota', label: 'Frota', field_type: 'text')
    used = Outsider::Crm::CustomFieldDefinition.create!(account: account, key: 'cnpj', label: 'CNPJ', field_type: 'text')
    crm_opportunity(account, unit, pipeline: pipeline, custom_fields: { 'cnpj' => '12.345', 'frota' => '' })

    delete_as(admin, "custom_fields/#{unused.id}")
    expect(Outsider::Crm::CustomFieldDefinition.exists?(unused.id)).to be(false)
    expect(delete_as(admin, "custom_fields/#{used.id}")).to include('reason' => 'has_values', 'count' => 1)
  end

  describe 'deals' do
    let(:deal) { crm_opportunity(account, unit, pipeline: pipeline, owner: seller) }

    it 'lets the unit manager delete a deal with its tasks and timeline, but not the seller' do
      deal.tasks.create!(account: account, title: 'Ligar')
      journey = deal.journey

      delete_as(seller, "opportunities/#{deal.id}")
      expect(response).to have_http_status(:forbidden)

      delete_as(manager, "opportunities/#{deal.id}")
      expect(response).to have_http_status(:no_content)
      expect(Outsider::Crm::Task.where(opportunity_id: deal.id)).to be_empty
      expect(Outsider::Crm::Journey.exists?(journey.id)).to be(false)
    end

    it 'deletes a forwarded deal from the end: the copy first, then the origin' do
      crm_pipeline(account, other_unit, name: 'Seminovos')
      reason = Outsider::Crm::LostReason.create!(account: account, name: 'Quer usado', kind: :forward)
      post "#{base_url}/opportunities/#{deal.id}/forward", params: { forward: { to_business_unit_id: other_unit.id, reason_id: reason.id } },
                                                           headers: seller.create_new_auth_token, as: :json
      copy = Outsider::Crm::Opportunity.find_by!(business_unit_id: other_unit.id)

      expect(delete_as(admin, "opportunities/#{deal.id}")).to include('reason' => 'forwarded_out', 'code' => copy.code, 'unit' => 'Seminovos')

      delete_as(admin, "opportunities/#{copy.id}")
      delete_as(admin, "opportunities/#{deal.id}")
      expect(response).to have_http_status(:no_content)
      expect(Outsider::Crm::Forward.where(account_id: account.id)).to be_empty
      expect(Outsider::Crm::Journey.where(account_id: account.id)).to be_empty
    end
  end
end
