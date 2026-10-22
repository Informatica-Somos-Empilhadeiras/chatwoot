require 'rails_helper'

RSpec.describe 'Outsider CRM proposal templates', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:unit) { crm_unit(account) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/outsider/crm/proposal_templates" }
  let(:templates) { Outsider::Crm::ProposalTemplate.where(account_id: account.id) }
  let(:sale) { templates.find_by(kind: :sale) }

  before do
    unit.members.create!(account: account, user: seller, role: :seller)
    Outsider::Crm::ProposalTemplateDefaults.ensure!(account)
  end

  def call(method, user, path = '', params = {})
    public_send(method, "#{base_url}#{path}", params: params, headers: user.create_new_auth_token, as: :json)
    response.parsed_body if response.media_type == 'application/json'
  end

  def upload(user, path)
    post "#{base_url}#{path}", params: { image: fixture_file_upload(Rails.root.join('spec/assets/sample.png'), 'image/png') },
                               headers: user.create_new_auth_token
    response.parsed_body
  end

  it 'keeps creating, previewing, uploading and deleting for admins' do
    call(:post, seller, '', name: 'Novo', kind: 'sale')
    expect(response).to have_http_status(:forbidden)
    call(:post, seller, "/#{sale.id}/preview", proposal_template: { name: 'X' })
    expect(response).to have_http_status(:forbidden)
    upload(seller, "/#{sale.id}/layout_images")
    expect(response).to have_http_status(:forbidden)
    call(:delete, seller, "/#{sale.id}")
    expect(response).to have_http_status(:forbidden)
  end

  it 'creates a blank template with the default texts and blocks of the kind' do
    body = call(:post, admin, '', name: 'Locação curta', kind: 'rental')

    expect(response).to have_http_status(:created)
    expect(body).to include('name' => 'Locação curta', 'kind' => 'rental', 'active' => true)
    expect(body['content']['conditions_style']).to eq('list')
    expect(body['content']['blocks'].find { |block| block['type'] == 'parties' }['visible']).to be(true)
    expect(body['content']['layout']['elements']).to eq([])
  end

  it 'copies a template pointing to the same image files, with the kind of the original' do
    sale.header_image.attach(io: Rails.root.join('spec/assets/sample.png').open, filename: 'cabecalho.png', content_type: 'image/png')
    image = upload(admin, "/#{sale.id}/layout_images")
    expect(response).to have_http_status(:created)
    call(:patch, admin, "/#{sale.id}", proposal_template: { content: { layout: { elements: [{ type: 'image', x: 10, y: 10, width: 30,
                                                                                              image_id: image['id'] }] } } })

    body = call(:post, admin, '', name: 'Cópia', kind: 'rental', source_id: sale.id)
    copy = templates.find(body['id'])

    expect(copy.kind).to eq('sale')
    expect(copy.header_image.blob).to eq(sale.reload.header_image.blob)
    copied = copy.layout_images.attachments.sole
    expect(copied.blob).to eq(sale.layout_images.attachments.sole.blob)
    expect(copy.layout['elements'].sole['image_id']).to eq(copied.id)
    expect(body['layout_images']).to contain_exactly(include('id' => copied.id))
  end

  it 'saves blocks and letterhead, and drops images no element uses' do
    unused = upload(admin, "/#{sale.id}/layout_images")
    used = upload(admin, "/#{sale.id}/layout_images")
    blocks = sale.blocks.reverse + [{ type: 'text', heading: 'Garantia', text: '12 meses' }]

    body = call(:patch, admin, "/#{sale.id}", proposal_template: {
                  content: { blocks: blocks, layout: { font: 'Courier', header_pages: 'first', margins: { side: 20 },
                                                       elements: [{ type: 'image', x: 5, y: 5, width: 40, image_id: used['id'] },
                                                                  { type: 'text', x: 100, y: 20, width: 90, text: 'Oi', color: '#00ff00' }] } }
                })

    expect(response).to have_http_status(:ok)
    expect(body['content']['blocks'].first['type']).to eq('notes')
    expect(body['content']['blocks'].last).to include('type' => 'text', 'heading' => 'Garantia')
    expect(body['content']['layout']).to include('font' => 'Courier', 'header_pages' => 'first')
    expect(body['content']['layout']['elements'].last['color']).to eq('00ff00')
    expect(sale.reload.layout_images.attachments.pluck(:id)).to eq([used['id']])
    expect(unused['id']).not_to eq(used['id'])
  end

  it 'keeps images used by image blocks and copies them pointing to the same file' do
    image = upload(admin, "/#{sale.id}/layout_images")
    upload(admin, "/#{sale.id}/layout_images")
    blocks = sale.blocks + [{ type: 'image', image_id: image['id'], width: 60, align: 'left' }, { type: 'spacer', height: 10 }]

    call(:patch, admin, "/#{sale.id}", proposal_template: { content: { blocks: blocks } })

    expect(sale.reload.layout_images.attachments.pluck(:id)).to eq([image['id']])
    copy = templates.find(call(:post, admin, '', name: 'Cópia', kind: 'sale', source_id: sale.id)['id'])
    copied = copy.layout_images.attachments.sole
    expect(copied.blob).to eq(sale.layout_images.attachments.sole.blob)
    expect(copy.blocks.find { |block| block['type'] == 'image' }).to include('image_id' => copied.id, 'width' => 60.0, 'align' => 'left')
  end

  it 'refuses a template with every block hidden' do
    hidden = sale.blocks.map { |block| block.merge('visible' => false) }

    call(:patch, admin, "/#{sale.id}", proposal_template: { content: { blocks: hidden } })

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'previews the PDF with what is on screen without saving' do
    crm_product(account)
    before = sale.reload.attributes.slice('name', 'content', 'updated_at')

    post "#{base_url}/#{sale.id}/preview", params: { proposal_template: { name: 'Teste', content: { intro: 'Prévia sem salvar' } } },
                                           headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('application/pdf')
    expect(response.body).to start_with('%PDF')
    expect(sale.reload.attributes.slice('name', 'content', 'updated_at')).to eq(before)
    expect(Outsider::Crm::Proposal.where(account_id: account.id)).to be_empty
  end

  it 'deletes only templates no proposal uses and keeps one active per kind' do
    call(:delete, admin, "/#{sale.id}")
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('last_active')

    other = templates.find(call(:post, admin, '', name: 'Outra venda', kind: 'sale')['id'])
    crm_proposal(account, owner: admin)
    call(:delete, admin, "/#{sale.id}")
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('error' => 'in_use')

    call(:delete, admin, "/#{other.id}")
    expect(response).to have_http_status(:no_content)
    expect(templates.exists?(other.id)).to be(false)
  end

  it 'keeps the shared image when the copy is deleted' do
    image = upload(admin, "/#{sale.id}/layout_images")
    call(:patch, admin, "/#{sale.id}", proposal_template: { content: { layout: { elements: [{ type: 'image', image_id: image['id'] }] } } })
    copy_id = call(:post, admin, '', name: 'Cópia', kind: 'sale', source_id: sale.id)['id']

    perform_enqueued_jobs { call(:delete, admin, "/#{copy_id}") }

    expect(response).to have_http_status(:no_content)
    expect(sale.reload.layout_images.attachments.sole.blob.reload).to be_present
    expect(sale.layout_images.attachments.sole.download).to be_present
  end

  it 'serves the letterhead that comes with the CRM' do
    get "#{base_url}/default_images/header", headers: admin.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('image/jpeg')
  end
end
