# OUTSIDER: os modelos de relatório que já vêm prontos no estúdio (builtin). Entram na conta na primeira vez que a lista
# abre (e de novo se todos daquele tipo forem apagados), podem ser editados como qualquer outro e "Restaurar" devolve o
# conteúdo original. Nenhum é usado sozinho: até o administrador escolher, a OS e o orçamento saem no relatório original.
module Outsider::Erp::Prints::Defaults
  def self.header(title, subtitle, style: 'line')
    { 'type' => 'header', 'logo' => 'erp', 'company' => true, 'title' => title, 'subtitle' => subtitle, 'style' => style }
  end

  def self.fields(group, title, columns: 3, style: 'boxes')
    { 'type' => 'fields', 'group' => group, 'title' => title, 'columns' => columns, 'style' => style }
  end

  def self.table(table, title) = { 'type' => 'table', 'table' => table, 'title' => title }
  def self.long_text(field, title) = { 'type' => 'long_text', 'field' => field, 'title' => title }
  def self.signatures(lines, date: false) = { 'type' => 'signatures', 'lines' => lines, 'names' => true, 'date' => date }

  OS_HEADER = header('Ordem de Serviço Nº {numero}', '{tipo_atendimento}')
  OS_DATA = [fields('os', 'Dados da OS', columns: 4), fields('cliente', 'Cliente', columns: 2),
             fields('equipamento', 'Equipamento', columns: 3)].freeze

  TEMPLATES = {
    'os_fotos' => {
      'kind' => 'os', 'name' => 'OS com fotos do checklist',
      'blocks' => [OS_HEADER, *OS_DATA, table('eventos', 'Check-in / check-out'), long_text('defeitos', 'Defeitos mencionados'),
                   long_text('avaliacao', 'Avaliação técnica'), table('produtos', 'Produtos utilizados'),
                   { 'type' => 'checklist', 'title' => 'Checklist', 'photos' => 'with', 'title_style' => 'band', 'arrangement' => 'auto' },
                   signatures(%w[Técnico Cliente])]
    },
    'os_respostas' => {
      'kind' => 'os', 'name' => 'OS com as respostas do checklist (sem fotos)',
      'blocks' => [OS_HEADER, *OS_DATA, long_text('defeitos', 'Defeitos mencionados'),
                   { 'type' => 'checklist', 'title' => 'Checklist', 'photos' => 'without', 'answers' => 'table' },
                   long_text('avaliacao', 'Avaliação técnica'), table('produtos', 'Produtos utilizados'), signatures(%w[Técnico Cliente])]
    },
    'os_vistoria' => {
      'kind' => 'os', 'name' => 'Vistoria com fotos grandes',
      'theme' => { 'heading_font' => 'helvetica', 'size' => 9 },
      'blocks' => [header('Relatório de vistoria', 'OS {numero}', style: 'band'), fields('cliente', 'Cliente', columns: 2),
                   fields('equipamento', 'Equipamento', columns: 3),
                   { 'type' => 'checklist', 'title' => 'Registro fotográfico', 'photos' => 'with', 'title_style' => 'card',
                     'arrangement' => 'auto', 'size' => 'l' },
                   long_text('avaliacao', 'Parecer técnico'), signatures(['Técnico responsável'], date: true)]
    },
    'os_entrega' => {
      'kind' => 'os', 'name' => 'Entrega técnica',
      'blocks' => [header('Termo de entrega técnica', 'OS {numero}'), fields('cliente', 'Cliente', columns: 2),
                   fields('equipamento', 'Equipamento', columns: 3),
                   { 'type' => 'checklist', 'title' => 'Itens verificados na entrega', 'photos' => 'without', 'answers' => 'grid',
                     'grid_columns' => 2 },
                   { 'type' => 'text', 'text' => 'Declaro que recebi o equipamento acima em perfeito estado de funcionamento e ' \
                                                 'fui orientado sobre a operação e os cuidados de manutenção.', 'size' => 'md' },
                   { 'type' => 'spacer', 'height' => 24 }, signatures(%w[Técnico Cliente], date: true)]
    },
    'quote_padrao' => {
      'kind' => 'quote', 'name' => 'Orçamento padrão',
      'blocks' => [header('Orçamento Nº {numero}', '{data}'), fields('orcamento', 'Dados do orçamento', columns: 4),
                   fields('cliente', 'Cliente', columns: 2), table('itens', 'Peças e serviços'),
                   { 'type' => 'totals', 'title' => '', 'width' => 'half' }, fields('condicoes', 'Condições', columns: 3),
                   long_text('observacoes', 'Observações'), signatures(%w[Vendedor Cliente])]
    }
  }.freeze

  module_function

  def content(key)
    data = TEMPLATES.fetch(key)
    Outsider::Erp::Prints::Content.normalize(data['kind'], 'theme' => data['theme'], 'blocks' => data['blocks'])
  end

  # cria os padrões de um tipo quando a conta não tem nenhum modelo dele
  def ensure!(account, kind, user: nil)
    return if Outsider::Erp::PrintTemplate.exists?(account_id: account.id, kind: kind)

    TEMPLATES.each do |key, data|
      next unless data['kind'] == kind

      Outsider::Erp::PrintTemplate.create!(account_id: account.id, kind: kind, name: data['name'], builtin: key,
                                           content: content(key), created_by_id: user&.id)
    end
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    nil
  end

  def restore(template)
    return false unless TEMPLATES.key?(template.builtin)

    template.update!(content: content(template.builtin), name: TEMPLATES[template.builtin]['name'])
    template.unused_images.each(&:purge_later)
    true
  end
end
