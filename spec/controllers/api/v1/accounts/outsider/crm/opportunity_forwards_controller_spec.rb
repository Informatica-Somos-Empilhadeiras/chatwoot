require 'rails_helper'

RSpec.describe 'Outsider CRM opportunity forwarding API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:colleague) { create(:user, account: account, role: :agent) }
  let(:target_seller) { create(:user, account: account, role: :agent) }
  let(:origin_unit) { crm_unit(account, name: 'Locação') }
  let(:target_unit) { crm_unit(account, name: 'Seminovos') }
  let!(:target_pipeline) { crm_pipeline(account, target_unit, name: 'Seminovos') }
  let(:contact) { create(:contact, account: account) }
  let(:opportunity) do
    crm_opportunity(account, origin_unit, contact: contact, owner: seller, title: 'Frota 3x', value_cents: 5_200_000)
  end
  let(:url) { "/api/v1/accounts/#{account.id}/outsider/crm/opportunities/#{opportunity.id}/forward" }
  let(:reason) { Outsider::Crm::LostReason.create!(account: account, name: 'Quer comprar usado', kind: :forward) }

  before do
    origin_unit.members.create!(account: account, user: seller, role: :seller)
    origin_unit.members.create!(account: account, user: colleague, role: :seller)
    target_unit.members.create!(account: account, user: target_seller, role: :seller)
  end

  def forward(user = seller, **attrs)
    post url, params: { forward: { to_business_unit_id: target_unit.id, reason_id: reason.id }.merge(attrs) },
              headers: user.create_new_auth_token, as: :json
  end

  describe 'POST create' do
    it 'closes the origin as forwarded and opens a copy in the destination, in the same journey' do
      forward(owner_id: target_seller.id, notes: 'Cliente quer ver seminovos')

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      target = Outsider::Crm::Opportunity.find(body['opportunity']['id'])
      expect(opportunity.reload).to have_attributes(status: 'forwarded', lost_reason_id: reason.id, closed_at: be_present)
      expect(target).to have_attributes(
        business_unit_id: target_unit.id, pipeline_id: target_pipeline.id, stage_id: target_pipeline.first_open_stage.id,
        journey_id: opportunity.journey_id, contact_id: contact.id, title: 'Frota 3x', value_cents: 5_200_000,
        owner_id: target_seller.id, forwarded_from_id: opportunity.id, status: 'open'
      )
      expect(body['attempt_number']).to eq(1)
      expect(body['origin']).to include('can_edit' => false, 'can_forward' => false)
      expect(body['origin']['forwarded_to']).to include('code' => target.code, 'business_unit_name' => 'Seminovos')
      expect(body['opportunity']['forwarded_from']).to include('code' => opportunity.code, 'business_unit_name' => 'Locação')
    end

    it 'records the attempt and both timeline entries, without the usual status and creation entries' do
      forward(notes: 'Ligar à tarde')

      record = Outsider::Crm::Forward.last
      expect(record).to have_attributes(status: 'accepted', attempt_number: 1, from_opportunity_id: opportunity.id,
                                        from_business_unit_id: origin_unit.id, to_business_unit_id: target_unit.id,
                                        reason_id: reason.id, notes: 'Ligar à tarde', requested_by_id: seller.id)
      expect(opportunity.activities.pluck(:kind)).to eq(%w[created forwarded])
      expect(opportunity.activities.forwarded.last.metadata).to include('to_unit' => 'Seminovos', 'reason' => 'Quer comprar usado',
                                                                        'attempt' => 1, 'max' => 3)
      target = record.to_opportunity
      expect(target.activities.pluck(:kind)).to eq(%w[received])
      expect(target.activities.last).to have_attributes(body: 'Ligar à tarde', user_id: seller.id)
      expect(target.activities.last.metadata).to include('from_unit' => 'Locação', 'from_code' => opportunity.code)
    end

    it 'creates the contact task for the destination owner and completes the origin tasks when asked' do
      pending_task = opportunity.tasks.create!(account: account, title: 'Visita', assignee: seller)

      forward(owner_id: target_seller.id, create_task: true, complete_tasks: true)

      expect(pending_task.reload.completed_by_id).to eq(seller.id)
      target = Outsider::Crm::Forward.last.to_opportunity
      task = target.tasks.last
      expect(task).to have_attributes(assignee_id: target_seller.id, kind: 'call',
                                      title: I18n.t('outsider_crm.forward.task_title', unit: 'Locação'))
      expect(task.due_at).to be_within(1.minute).of(30.minutes.from_now)
    end

    it 'assigns the linked conversation to the destination owner through Chatwoot when asked' do
      inbox = create(:inbox, account: account)
      create(:inbox_member, inbox: inbox, user: seller)
      create(:inbox_member, inbox: inbox, user: target_seller)
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact, assignee: seller)
      opportunity.update!(conversation: conversation)

      forward(owner_id: target_seller.id, assign_conversation: true)

      expect(response).to have_http_status(:created)
      expect(conversation.reload.assignee_id).to eq(target_seller.id)
      expect(Outsider::Crm::Forward.last.to_opportunity.conversation_id).to eq(conversation.id)
    end

    it 'refuses to assign the conversation to someone outside its inbox, changing nothing' do
      inbox = create(:inbox, account: account)
      create(:inbox_member, inbox: inbox, user: seller)
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact, assignee: seller)
      opportunity.update!(conversation: conversation)

      forward(owner_id: target_seller.id, assign_conversation: true)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('owner_not_in_inbox')
      expect(opportunity.reload.status).to eq('open')
      expect(conversation.reload.assignee_id).to eq(seller.id)
    end

    it 'requires a forwarding reason when the account has one' do
      reason

      forward(reason_id: nil)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('error' => 'reason_required',
                                              'message' => I18n.t('outsider_crm.forward.errors.reason_required'))
    end

    it 'does not forward to a unit where the contact already has an open opportunity' do
      crm_opportunity(account, target_unit, contact: contact, pipeline: target_pipeline,
                                            journey: opportunity.journey)

      forward

      expect(response.parsed_body['error']).to eq('duplicate_open')
      expect(opportunity.reload.status).to eq('open')
    end

    it 'respects the account limit of forwards per journey' do
      Outsider::Crm::Settings.new(account).update(max_forward_attempts: 1)
      third_unit = crm_unit(account, name: 'Peças')
      crm_pipeline(account, third_unit, name: 'Peças')
      third_unit.members.create!(account: account, user: target_seller, role: :manager)

      forward(owner_id: target_seller.id)
      target = Outsider::Crm::Forward.last.to_opportunity
      post "/api/v1/accounts/#{account.id}/outsider/crm/opportunities/#{target.id}/forward",
           params: { forward: { to_business_unit_id: third_unit.id, reason_id: reason.id } },
           headers: target_seller.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('limit_reached')
      expect(target.reload.status).to eq('open')
    end

    it 'does not let a colleague who only views the opportunity forward it' do
      forward(colleague)

      expect(response).to have_http_status(:forbidden)
    end

    it 'does not forward an opportunity that is no longer open' do
      opportunity.update!(status: :won)

      forward

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('not_open')
    end

    it 'refuses an owner who is not in the destination unit' do
      forward(owner_id: colleague.id)

      expect(response.parsed_body['error']).to eq('invalid_owner')
    end
  end

  describe 'GET show' do
    it 'lists destination units with availability, owners and the attempt count' do
      empty_unit = crm_unit(account, name: 'Sem funil')
      opportunity.tasks.create!(account: account, title: 'Visita', assignee: seller)
      reason

      get url, headers: seller.create_new_auth_token

      body = response.parsed_body
      expect(body).to include('attempts' => { 'used' => 0, 'max' => 3, 'next' => 1, 'limit_reached' => false },
                              'reason_required' => true, 'pending_tasks' => 1, 'conversation' => nil)
      expect(body['reasons'].pluck('name')).to eq(['Quer comprar usado'])
      target = body['units'].find { |unit| unit['id'] == target_unit.id }
      expect(target).to include('available' => true, 'unavailable_reason' => nil)
      expect(target['pipelines'].pluck('id')).to eq([target_pipeline.id])
      expect(target['members'].pluck('id')).to eq([target_seller.id])
      expect(body['units'].find { |unit| unit['id'] == empty_unit.id }).to include('available' => false, 'unavailable_reason' => 'no_pipeline')
      expect(body['units'].pluck('id')).not_to include(origin_unit.id)
    end
  end

  describe 'after forwarding' do
    before { forward }

    it 'keeps the origin readable but frozen, even for the administrator' do
      origin_url = "/api/v1/accounts/#{account.id}/outsider/crm/opportunities/#{opportunity.id}"

      patch origin_url, params: { opportunity: { title: 'Outro' } }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)

      post "#{origin_url}/activities", params: { activity: { body: 'Nota' } }, headers: seller.create_new_auth_token, as: :json
      expect(response.parsed_body['error']).to eq('forwarded_locked')

      get origin_url, headers: seller.create_new_auth_token
      expect(response.parsed_body).to include('status' => 'forwarded', 'can_edit' => false)
    end

    it 'does not delete opportunities that are part of a forward' do
      delete "/api/v1/accounts/#{account.id}/outsider/crm/opportunities/#{opportunity.id}", headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('in_use')
      expect(Outsider::Crm::Opportunity.exists?(opportunity.id)).to be(true)
    end

    it 'closes the journey when the last open opportunity is won' do
      target = Outsider::Crm::Forward.last.to_opportunity
      expect(opportunity.journey.reload.status).to eq('open')

      target.update!(status: :won)

      expect(opportunity.journey.reload).to have_attributes(status: 'won')
      expect(opportunity.journey.closed_at).to be_present
    end
  end

  describe 'PATCH opportunity status' do
    it 'does not let the status be set to forwarded without the forwarding flow' do
      patch "/api/v1/accounts/#{account.id}/outsider/crm/opportunities/#{opportunity.id}",
            params: { opportunity: { status: 'forwarded' } }, headers: seller.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(opportunity.reload.status).to eq('open')
    end
  end
end
