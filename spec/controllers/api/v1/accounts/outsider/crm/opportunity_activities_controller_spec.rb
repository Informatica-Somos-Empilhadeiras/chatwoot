require 'rails_helper'

RSpec.describe 'Outsider CRM timeline, notes and audit API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:colleague) { create(:user, account: account, role: :agent) }
  let(:unit) { crm_unit(account) }
  let(:contact) { create(:contact, account: account) }
  let(:opportunity) { crm_opportunity(account, unit, contact: contact, owner: seller) }
  let(:base) { "/api/v1/accounts/#{account.id}/outsider/crm/opportunities/#{opportunity.id}" }

  before do
    unit.members.create!(account: account, user: seller, role: :seller)
    unit.members.create!(account: account, user: colleague, role: :seller)
  end

  describe 'notes' do
    it 'saves a CRM note only in the CRM, never as a Chatwoot message' do
      conversation = create(:conversation, account: account, contact: contact)

      expect do
        post "#{base}/activities", params: { activity: { body: 'Cliente pediu desconto', conversation_display_id: conversation.display_id } },
                                   headers: colleague.create_new_auth_token, as: :json
      end.not_to change(Message, :count)

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body).to include('kind' => 'note', 'body' => 'Cliente pediu desconto', 'can_delete' => true)
      expect(body['metadata']).to eq('conversation_display_id' => conversation.display_id)
    end

    it 'refuses an empty note' do
      post "#{base}/activities", params: { activity: { body: '  ' } }, headers: seller.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'lets only the author or a manager delete a note, and audits the deletion' do
      note = opportunity.activities.create!(account: account, user: colleague, kind: :note, body: 'Rascunho')

      delete "#{base}/activities/#{note.id}", headers: seller.create_new_auth_token
      expect(response).to have_http_status(:forbidden)

      delete "#{base}/activities/#{note.id}", headers: colleague.create_new_auth_token
      expect(response).to have_http_status(:no_content)

      get "#{base}/audits", headers: admin.create_new_auth_token
      deleted = response.parsed_body.find { |audit| audit['subject'] == 'note' }
      expect(deleted).to include('action' => 'destroy', 'subject_label' => 'Rascunho')
    end
  end

  describe 'GET activities' do
    it 'returns the timeline newest first, with pages' do
      35.times { |index| opportunity.activities.create!(account: account, kind: :note, body: "Nota #{index}") }

      get "#{base}/activities", headers: seller.create_new_auth_token
      first_page = response.parsed_body
      expect(first_page['payload'].size).to eq(30)
      expect(first_page['payload'].first['body']).to eq('Nota 34')
      expect(first_page['meta']['has_more']).to be(true)

      get "#{base}/activities", params: { before_id: first_page['payload'].last['id'] }, headers: seller.create_new_auth_token
      expect(response.parsed_body['payload'].pluck('kind')).to end_with('created')
      expect(response.parsed_body['meta']['has_more']).to be(false)
    end
  end

  describe 'GET audits' do
    it 'shows who changed the stage, value and owner, with names instead of ids' do
      proposal = opportunity.pipeline.stages.find_by(name: 'Proposta')
      patch base, params: { opportunity: { stage_id: proposal.id, value: '1.500,00', owner_id: colleague.id } },
                  headers: admin.create_new_auth_token, as: :json

      get "#{base}/audits", headers: seller.create_new_auth_token

      update = response.parsed_body.find { |audit| audit['action'] == 'update' && audit['subject'] == 'opportunity' }
      expect(update['user']).to include('id' => admin.id)
      expect(update['changes']).to include(
        { 'field' => 'stage_id', 'from' => 'Qualificação', 'to' => 'Proposta' },
        { 'field' => 'value_cents', 'from' => 0, 'to' => 150_000 },
        { 'field' => 'owner_id', 'from' => seller.name, 'to' => colleague.name }
      )
      expect(update['changes'].pluck('field')).not_to include('updated_at', 'stage_changed_at')
    end

    it 'includes the changes of the tasks, even deleted ones' do
      task = opportunity.tasks.create!(account: account, title: 'Visita', assignee: seller)
      task.update!(due_at: 1.day.from_now)
      task.destroy!

      get "#{base}/audits", headers: seller.create_new_auth_token

      task_audits = response.parsed_body.select { |audit| audit['subject'] == 'task' }
      expect(task_audits.pluck('action')).to eq(%w[destroy update create])
      expect(task_audits.pluck('subject_label').uniq).to eq(['Visita'])
    end

    it 'translates enum values' do
      patch base, params: { opportunity: { status: 'won' } }, headers: seller.create_new_auth_token, as: :json

      get "#{base}/audits", headers: seller.create_new_auth_token

      changes = response.parsed_body.first['changes']
      expect(changes).to include({ 'field' => 'status', 'from' => 'open', 'to' => 'won' })
    end
  end
end
