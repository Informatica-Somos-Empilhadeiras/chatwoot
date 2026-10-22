require 'rails_helper'

RSpec.describe Outsider::Crm::ProposalTemplateLayout do
  it 'derives the block sequence from the old switches when the template has no blocks' do
    blocks = described_class.blocks('show_specs' => false, 'show_parties' => true, 'show_bank' => true)

    expect(blocks.pluck('type')).to eq(%w[date_number customer intro title specs items conditions parties closing bank signature notes])
    expect(blocks.find { |block| block['type'] == 'specs' }['visible']).to be(false)
    expect(blocks.find { |block| block['type'] == 'parties' }['visible']).to be(true)
    expect(blocks.select { |block| block['new_page'] }.pluck('type')).to eq(%w[items bank])
  end

  it 'keeps known blocks once, numbers free texts and clamps sizes' do
    blocks = described_class.normalize_blocks(
      [{ type: 'title', size: 99, bold: '1' }, { type: 'title' }, { type: 'hack' },
       { type: 'text', heading: '  Garantia ', text: 'x' * 6000 }, { type: 'text', key: 'mine', visible: 'false' }]
    )

    expect(blocks.pluck('type')).to eq(%w[title text text])
    expect(blocks[0]).to include('size' => 16.0, 'bold' => true, 'visible' => true)
    expect(blocks[1]).to include('key' => 'text-3', 'heading' => 'Garantia')
    expect(blocks[1]['text'].length).to eq(5_000)
    expect(blocks[2]).to include('key' => 'mine', 'visible' => false)
  end

  it 'cleans the letterhead: font, pages, margins and free elements' do
    layout = described_class.normalize_layout(
      font: 'Comic Sans', header_pages: 'first', footer_pages: 'odd', margins: { side: -5, top: 'abc', bottom: 500 },
      elements: [{ type: 'text', x: 300, y: -1, width: 1, text: 'Oi', color: '#FF0000', align: 'justify', pages: 'first' },
                 { type: 'video' }, { type: 'image', image_id: '7' }]
    )

    expect(layout).to include('font' => 'Helvetica', 'header_pages' => 'first', 'footer_pages' => 'all')
    expect(layout['margins']).to eq('side' => 0.0, 'top' => 6.4, 'bottom' => 80.0)
    expect(layout['elements'].size).to eq(2)
    expect(layout['elements'][0]).to include('x' => 210.0, 'y' => 0.0, 'width' => 5.0, 'color' => 'FF0000', 'align' => 'left',
                                             'pages' => 'first')
    expect(layout['elements'][0]['id']).to be_present
    expect(layout['elements'][1]).to include('type' => 'image', 'image_id' => 7)
  end

  it 'repeats free image, divider and spacer blocks and clamps their options' do
    blocks = described_class.normalize_blocks(
      [{ type: 'image', image_id: '12', width: 300, align: 'middle' }, { type: 'image', key: 'logo' },
       { type: 'divider', color: '#ff0000', thickness: 9 }, { type: 'divider', color: 'red' }, { type: 'spacer', height: 0 }]
    )

    expect(blocks.pluck('type')).to eq(%w[image image divider divider spacer])
    expect(blocks[0]).to include('key' => 'image-0', 'image_id' => 12, 'width' => 100.0, 'align' => 'center')
    expect(blocks[1]).to include('key' => 'logo', 'image_id' => nil)
    expect(blocks[2]).to include('color' => 'ff0000', 'thickness' => 4.0)
    expect(blocks[3]['color']).to eq('BFBFBF')
    expect(blocks[4]['height']).to eq(1.0)
  end

  it 'lists the template images in use by elements and image blocks' do
    content = { 'blocks' => [{ 'type' => 'image', 'image_id' => 3 }, { 'type' => 'text' }],
                'layout' => { 'elements' => [{ 'type' => 'image', 'image_id' => 5 }] } }

    expect(described_class.image_ids(content)).to contain_exactly(3, 5)
  end
end
