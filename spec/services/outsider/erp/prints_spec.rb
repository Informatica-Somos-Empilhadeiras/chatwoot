require 'rails_helper'

# OUTSIDER: modelos de relatório da OS e do orçamento (Outsider::Erp::Prints): limpeza do conteúdo, escolha por tipo de
# atendimento, modelos padrão e o PDF de cada bloco com os dados de exemplo.
RSpec.describe Outsider::Erp::Prints do
  let(:account) { create(:account) }
  let(:content) { Outsider::Erp::Prints::Content }

  def template(kind = 'os', blocks = [], name: 'Modelo')
    Outsider::Erp::PrintTemplate.create!(account: account, kind: kind, name: name, content: { 'blocks' => blocks })
  end

  def render(kind, blocks, theme: {})
    values = Outsider::Erp::Prints::Values.new(kind, Outsider::Erp::Prints::Sample.for(kind)).build
    Outsider::Erp::Prints::Pdf.new(content.normalize(kind, 'theme' => theme, 'blocks' => blocks), values).render
  end

  describe 'content' do
    it 'drops unknown blocks and options and keeps values inside the rules' do
      data = content.normalize('os', 'theme' => { 'colors' => { 'primary' => '#123abc', 'text' => 'red' }, 'size' => 40, 'body_font' => 'comic' },
                                     'blocks' => [{ 'type' => 'fields', 'group' => 'cliente', 'columns' => 9, 'evil' => 1 },
                                                  { 'type' => 'totals' }, { 'type' => 'script' },
                                                  { 'type' => 'checklist', 'photos' => 'without', 'sections' => [' Inspeção  visual ', ''] }])
      expect(data['theme']['colors']).to include('primary' => '#123ABC', 'text' => '#1D2733')
      expect(data['theme']).to include('size' => 9, 'body_font' => 'helvetica')
      expect(data['blocks'].pluck('type')).to eq(%w[fields checklist])
      expect(data['blocks'].first).to include('columns' => 4, 'group' => 'cliente')
      expect(data['blocks'].first).not_to have_key('evil')
      expect(data['blocks'].last).to include('photos' => 'without', 'sections' => ['Inspeção visual'], 'answers' => 'table')
    end

    it 'keeps the chosen field order and adds new catalog fields at the end' do
      data = content.normalize('os', 'fields' => { 'cliente' => [{ 'key' => 'cidade', 'on' => true }, { 'key' => 'nome', 'on' => false },
                                                                 { 'key' => 'nope', 'on' => true }] })
      expect(data['fields']['cliente']).to eq([{ 'key' => 'cidade', 'on' => true }, { 'key' => 'nome', 'on' => false },
                                               { 'key' => 'documento', 'on' => true }, { 'key' => 'endereco', 'on' => true }])
    end
  end

  describe 'bindings' do
    let(:bindings) { Outsider::Erp::Prints::Bindings.new(account) }

    it 'uses the original report until a template is chosen' do
      expect(bindings.choice('os', 'MANUT. CORRETIVA')).to eq('original')
      expect(bindings.uses_templates?('os')).to be(false)
      expect(bindings.template('quote')).to be_nil
    end

    it 'picks the template of the attendance type, else the default, and forgets deleted ones' do
      corretiva = template
      padrao = template(name: 'Padrão')
      bindings.update('os', default: padrao.id, types: { ' manut.  corretiva ' => corretiva.id, 'VISITA' => 'default', 'X' => 999 })

      expect(described_class::Bindings.new(account).to_h['os']['types']).to eq('MANUT. CORRETIVA' => corretiva.id, 'X' => 'original')
      expect(bindings.choice('os', 'Manut. Corretiva')).to eq(corretiva.id)
      expect(bindings.template('os', 'PREVENTIVA')).to eq(padrao)

      corretiva.destroy!
      expect(described_class::Bindings.new(account).choice('os', 'MANUT. CORRETIVA')).to eq('original')
    end
  end

  describe 'defaults' do
    it 'creates the ready templates once per kind and restores them' do
      2.times { Outsider::Erp::Prints::Defaults.ensure!(account, 'os') }
      list = Outsider::Erp::PrintTemplate.where(account: account, kind: 'os')
      expect(list.pluck(:builtin)).to match_array(%w[os_fotos os_respostas os_vistoria os_entrega])

      edited = list.find_by(builtin: 'os_fotos')
      edited.update!(name: 'Meu', content: { 'blocks' => [{ 'type' => 'spacer' }] })
      Outsider::Erp::Prints::Defaults.restore(edited)
      expect(edited.reload.name).to eq('OS com fotos do checklist')
      expect(edited.blocks.pluck('type')).to include('checklist', 'signatures')
    end
  end

  describe 'pdf' do
    it 'renders every ready template with the sample data' do
      Outsider::Erp::Prints::Defaults::TEMPLATES.each do |key, data|
        pdf = render(data['kind'], Outsider::Erp::Prints::Defaults.content(key)['blocks'])
        expect(pdf).to start_with('%PDF'), key
      end
    end

    it 'renders the checklist in every layout, with and without photos' do
      layouts = %w[band side card compact].map { |style| { 'type' => 'checklist', 'title_style' => style } } +
                %w[table list grid].map { |answers| { 'type' => 'checklist', 'photos' => 'without', 'answers' => answers } } +
                [{ 'type' => 'checklist', 'sections' => ['Testes funcionais'], 'arrangement' => 'grid3', 'size' => 'l' }]
      layouts.each { |block| expect(render('os', [block], theme: { 'heading_font' => 'times', 'margin' => 's' })).to start_with('%PDF') }
    end

    it 'fills the placeholders and leaves unknown ones as typed' do
      values = Outsider::Erp::Prints::Values.new('quote', Outsider::Erp::Prints::Sample.for('quote')).build
      pdf = Outsider::Erp::Prints::Pdf.new(content.normalize('quote', {}), values)
      expect(pdf.send(:fill, 'Proposta {numero} para {cliente} {outro}')).to eq('Proposta 3309 para LOGÍSTICA ATLÂNTICO LTDA {outro}')
      expect(render('quote', [{ 'type' => 'heading', 'text' => '{total}' }, { 'type' => 'checklist' }])).to start_with('%PDF')
    end
  end

  describe 'photos to fetch' do
    let(:document) { Outsider::Erp::Prints::Document }

    it 'fetches none without a checklist with photos and only the filtered sections otherwise' do
      expect(document.photo_filter('blocks' => [{ 'type' => 'checklist', 'photos' => 'without' }])).to be_nil

      filter = document.photo_filter('blocks' => [{ 'type' => 'checklist', 'photos' => 'with', 'sections' => ['Inspeção visual'] }])
      expect([filter.call('INSPECAO VISUAL'), filter.call('Testes funcionais')]).to eq([true, false])

      all = document.photo_filter('blocks' => [{ 'type' => 'checklist', 'photos' => 'with', 'sections' => [] }])
      expect(all.call('Qualquer')).to be(true)
    end
  end
end
