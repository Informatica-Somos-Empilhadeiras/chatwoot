require 'rails_helper'

# OUTSIDER: desempenho dos técnicos: a OS de tipo fora da soma (Configurações; por padrão garantia, entrega técnica e
# frotas) aparece no pedido, marcada, mas não entra nos números do técnico.
RSpec.describe Outsider::Erp::TechnicianReport do
  let(:account) { create(:account) }
  let(:settings) { Outsider::Erp::Settings.new(account) }

  describe 'types out of the sum' do
    it 'comes with warranty, technical delivery and fleets, matching without accents, case or plural' do
      expect(settings.report_excluded_types).to eq(['GARANTIA', 'ENTREGA TÉCNICA', 'FROTAS'])
      excluded = ['Garantia', 'Entrega Técnica', 'MANUT. FROTA', 'frotas', 'ENTREGA', 'MANUT. CORRETIVA', '', nil].map do |type|
        settings.report_excluded?(type)
      end
      expect(excluded).to eq([true, true, true, true, false, false, false, false])
    end

    it 'saves the list cleaned and accepts an empty one' do
      settings.update('report_excluded_types' => [' garantia ', 'Frotas', '', 'GARANTÍA'])
      expect(Outsider::Erp::Settings.new(account).report_excluded_types).to eq(%w[GARANTIA FROTAS])

      settings.update('report_excluded_types' => [])
      expect(Outsider::Erp::Settings.new(account).report_excluded?('GARANTIA')).to be(false)
    end
  end

  describe Outsider::Erp::TechnicianReport::Totals do
    let(:sale) do
      { 'unidade' => 'somosemp', 'pedido' => 155, 'cliente_codigo' => 716, 'vendedor' => 'CRISTIANE', 'total' => 1000.0, 'pecas' => 600.0,
        'servicos' => 400.0, 'data_nota' => '2026-11-20',
        'linhas' => [
          { 'tecnico' => 'MARCOS', 'os' => 310, 'parte' => 50, 'atendimento' => 'CORRETIVA', 'data_os' => '2026-11-10' },
          { 'tecnico' => 'MARCOS', 'os' => 311, 'parte' => 50, 'atendimento' => 'GARANTIA', 'fora_da_soma' => true }
        ] }
    end

    it 'credits only the lines inside the sum' do
      marcos = described_class.new(settings).technicians([sale]).first
      expect(marcos).to include('tecnico' => 'MARCOS', 'faturado' => 500.0, 'pecas' => 300.0, 'servicos' => 200.0, 'os' => 1)
      expect(marcos['atendimentos']).to eq('CORRETIVA' => 1)
    end
  end
end
