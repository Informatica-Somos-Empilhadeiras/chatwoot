require 'rails_helper'

RSpec.describe Outsider::Voice::IvrRunner do
  let(:account) { create(:account) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:settings) { Outsider::Voice::Settings.new(account) }
  let(:router) { Outsider::Voice::Router.new(settings) }
  let(:graph) do
    {
      'nodes' => [
        { 'id' => 'start', 'type' => 'start', 'data' => {} },
        { 'id' => 'hello', 'type' => 'say', 'data' => { 'prompt' => { 'text' => 'Olá' } } },
        { 'id' => 'menu', 'type' => 'menu', 'data' => { 'label' => 'Principal', 'prompt' => { 'text' => 'Digite 1 ou 2' },
                                                        'invalid_prompt' => { 'text' => 'Inválida' }, 'max_attempts' => 2,
                                                        'options' => [{ 'id' => 'sales', 'digit' => '1', 'label' => 'Vendas' },
                                                                      { 'id' => 'doc', 'digit' => '2', 'label' => 'CPF' }] } },
        { 'id' => 'cpf', 'type' => 'collect', 'data' => { 'label' => 'CPF', 'variable' => 'cpf', 'min_digits' => 11, 'max_digits' => 11,
                                                          'prompt' => { 'text' => 'Digite o CPF' } } },
        { 'id' => 'ring', 'type' => 'transfer', 'data' => { 'target' => 'users', 'user_ids' => [seller.id], 'ring_seconds' => 25 } },
        { 'id' => 'vm', 'type' => 'voicemail', 'data' => { 'prompt' => { 'text' => 'Deixe o recado' }, 'max_seconds' => 60 } },
        { 'id' => 'bye', 'type' => 'hangup', 'data' => { 'prompt' => { 'text' => 'Tchau' } } }
      ],
      'edges' => [%w[start next hello], %w[hello next menu], %w[menu sales ring], %w[menu doc cpf], %w[cpf next ring],
                  %w[menu invalid vm], %w[ring no_answer vm], %w[vm next bye]].map { |from, port, to| { 'from' => from, 'port' => port, 'to' => to } }
    }
  end
  let!(:flow) { Outsider::Voice::IvrFlow.create!(account: account, name: 'Atendimento', active: true, graph: graph) }

  before do
    settings.update('enabled' => true, 'numbers' => [{ 'number' => '6232345678', 'state' => 'GO' }],
                    'agents' => { seller.id.to_s => { 'extension' => '201', 'state' => 'GO', 'enabled' => true } })
    Outsider::Voice::CentralStatus.new(account).report(registration: 'Registered', extensions: ['201'], version: 26, audio: true)
  end

  def step(node = nil, input: nil, dialstatus: nil)
    call = Outsider::Voice::Call.find_by!(linkedid: 'L1')
    described_class.new(settings, call).step(node_id: node, input: input, dialstatus: dialstatus)
  end

  def sounds(text)
    "outsider/#{Digest::SHA256.hexdigest("tts:central:nova:#{text}")[0, 20]}"
  end

  it 'sends a number with an active IVR to it and walks the caller through the blocks' do
    expect(router.inbound(linkedid: 'L1', did: '6232345678', from: '62999998888')).to eq('ivr')

    answers = [step, step('hello'), step('menu', input: '9'), step('menu', input: '2'), step('cpf', input: '12345678901'),
               step('ring', dialstatus: 'NOANSWER'), step('vm')]
    expect(answers).to eq([
                            "play|#{sounds('Olá')}|hello", "menu|#{sounds('Digite 1 ou 2')}|5|menu",
                            "menu|#{sounds('Inválida')}&#{sounds('Digite 1 ou 2')}|5|menu", "collect|#{sounds('Digite o CPF')}|11|8|cpf",
                            'ring||25|ring|PJSIP/201', "record|#{sounds('Deixe o recado')}|60|vm", "hangup|#{sounds('Tchau')}"
                          ])

    call = Outsider::Voice::Call.find_by!(linkedid: 'L1')
    expect(call.ivr_flow).to eq(flow)
    expect(call.ivr_summary).to eq('flow' => 'Atendimento', 'vars' => { 'cpf' => '12345678901' },
                                   'path' => [{ 'title' => 'Principal', 'answer' => '2 - CPF' }, { 'title' => 'CPF', 'answer' => '12345678901' }])
  end

  it 'leaves the menu by the invalid exit after the last attempt and skips a transfer with nobody to ring' do
    router.inbound(linkedid: 'L1', did: '6232345678', from: '62999998888')
    step('menu', input: '')
    expect(step('menu', input: '')).to eq("record|#{sounds('Deixe o recado')}|60|vm")

    settings.update(settings.data.merge('agents' => {}))
    expect(step('menu', input: '1')).to eq("record|#{sounds('Deixe o recado')}|60|vm")
  end

  it 'rings everyone like before when the number has no IVR or the flow lost its start' do
    flow.update!(active: false)
    expect(router.inbound(linkedid: 'L1', did: '6232345678', from: '62999998888')).to eq('20|PJSIP/201')

    flow.update!(active: true, graph: { 'nodes' => [], 'edges' => [] })
    Outsider::Voice::Call.find_by!(linkedid: 'L1').update!(ivr_flow: flow)
    expect(step).to eq('ring||20|_end|PJSIP/201')
    expect(step('_end', dialstatus: 'NOANSWER')).to eq('hangup|')
  end

  it 'stops a looping flow and refuses a second IVR on the same number' do
    flow.update!(graph: { 'nodes' => graph['nodes'], 'edges' => [%w[start next hello], %w[hello next menu], %w[menu invalid hello]]
      .map { |from, port, to| { 'from' => from, 'port' => port, 'to' => to } } })
    router.inbound(linkedid: 'L1', did: '6232345678', from: '62999998888')
    node = 'hello'
    answers = Array.new(70) do
      answer = step(node, input: '')
      node = answer.split('|', -1).last
      answer
    end
    expect(answers.last).to eq('hangup|')

    other = Outsider::Voice::IvrFlow.new(account: account, name: 'Outra', active: true, graph: graph)
    expect(other).not_to be_valid
    expect(other.errors.details[:numbers]).to include(error: :all_taken)
  end
end
