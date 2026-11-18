require 'rails_helper'

# OUTSIDER: o marcador <attachment id="..."> do Teams não aparece no texto das mensagens
RSpec.describe Outsider::Teams::Graph::Inbound do
  it 'tira o marcador do corpo em texto puro (Teams do celular)' do
    body = { 'contentType' => 'text', 'content' => "ENTREGA TÉCNICA\n<attachment id=\"9146\">\n</attachment>" }
    expect(described_class.text_of(body)).to eq('ENTREGA TÉCNICA')
  end

  it 'tira o marcador do corpo em html, também escapado' do
    body = { 'contentType' => 'html', 'content' => '<p>Oi</p><attachment id="a"></attachment>&lt;attachment id="b"&gt;&lt;/attachment&gt;' }
    expect(described_class.text_of(body)).to eq('Oi')
  end

  it 'mostra sem o marcador as mensagens que já estavam guardadas' do
    expect(Outsider::Teams::Graph::Json.clean('<attachment id="x"></attachment><attachment id="y"></attachment>')).to eq('')
    expect(Outsider::Teams::Graph::Json.clean('Mateus: oi')).to eq('Mateus: oi')
  end
end
