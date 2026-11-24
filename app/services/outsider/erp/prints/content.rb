# OUTSIDER: o formato do content de um modelo de relatório (Outsider::Erp::PrintTemplate) e a limpeza dele antes de
# gravar. content = { 'theme' => identidade visual, 'fields' => { lista => [{ key, on }] }, 'blocks' => [...] }.
# - theme: cores (hex, usadas por todos os blocos), fonte dos títulos e do texto (as do próprio PDF), tamanho base,
#   margem e numeração das páginas;
# - fields: para cada grupo/tabela do Outsider::Erp::Prints::Catalog, a ordem e o liga/desliga dos campos;
# - blocks: a lista de blocos, cada um com id, type e as opções dele (BLOCKS). Opção desconhecida é descartada; valor
#   fora do permitido volta ao padrão. Texto livre aceita os marcadores do catálogo ({numero}, {cliente}...).
# rubocop:disable Metrics/ModuleLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
module Outsider::Erp::Prints::Content
  HEX = /\A#[0-9a-fA-F]{6}\z/
  FONTS = %w[helvetica times courier].freeze
  ALIGN = [:enum, %w[left center right], 'left'].freeze
  MAX_BLOCKS = 80
  COLORS = {
    'primary' => '#00663B', 'accent' => '#90EB54', 'text' => '#1D2733', 'muted' => '#6B7686', 'row' => '#F3F7F4',
    'box' => '#EEF6F1', 'line' => '#D6DEE3'
  }.freeze
  THEME = {
    'colors' => COLORS, 'heading_font' => 'helvetica', 'body_font' => 'helvetica', 'size' => 9, 'margin' => 'm',
    'page_numbers' => true
  }.freeze

  # tipo => { opção => [tipo, ...regra, padrão] }. :enum [valores, padrão], :int [mín, máx, padrão], :bool [padrão],
  # :text [tamanho, padrão], :list [itens, tamanho, padrão], :image (id de anexo do modelo ou nil)
  COMMON_BLOCKS = {
    'header' => {
      'logo' => [:enum, %w[erp upload none], 'erp'], 'image_id' => [:image], 'company' => [:bool, true],
      'title' => [:text, 200, ''], 'subtitle' => [:text, 200, ''], 'style' => [:enum, %w[line band plain], 'line']
    },
    'heading' => {
      'text' => [:text, 300, 'Título'], 'size' => [:enum, %w[lg md sm], 'md'], 'align' => ALIGN,
      'color' => [:enum, %w[primary accent text], 'primary']
    },
    'text' => {
      'text' => [:text, 5000, ''], 'align' => ALIGN, 'size' => [:enum, %w[sm md lg], 'md'],
      'color' => [:enum, %w[text muted primary], 'text']
    },
    'fields' => {
      'group' => [:group], 'title' => [:text, 200, ''], 'columns' => [:int, 1, 4, 2],
      'style' => [:enum, %w[boxes labels inline], 'boxes'], 'hide_empty' => [:bool, true]
    },
    'table' => { 'table' => [:table], 'title' => [:text, 200, ''], 'striped' => [:bool, true], 'hide_empty' => [:bool, true] },
    'long_text' => { 'field' => [:long_text], 'title' => [:text, 200, ''], 'boxed' => [:bool, true], 'hide_empty' => [:bool, true] },
    'signatures' => { 'lines' => [:list, 4, 60, %w[Responsável Cliente]], 'names' => [:bool, true], 'date' => [:bool, false] },
    'image' => { 'image_id' => [:image], 'width' => [:int, 10, 100, 40], 'align' => [:enum, %w[left center right], 'center'] },
    'divider' => { 'color' => [:enum, %w[primary accent line], 'line'], 'thickness' => [:int, 1, 4, 1] },
    'spacer' => { 'height' => [:int, 4, 200, 16] },
    'page_break' => {}
  }.freeze
  KIND_BLOCKS = {
    'os' => {
      # checklist: com fotos (grupos por item: título + fotos) ou sem fotos (só as respostas: tabela, lista ou grade);
      # sections filtra pelas seções (vazio = todas) para espalhar o checklist pelo relatório
      'checklist' => {
        'title' => [:text, 200, ''], 'photos' => [:enum, %w[with without], 'with'], 'sections' => [:list, 30, 120, []],
        'show_sections' => [:bool, true], 'answers' => [:enum, %w[table list grid], 'table'], 'grid_columns' => [:int, 2, 3, 2],
        'title_style' => [:enum, %w[band side card compact], 'band'], 'arrangement' => [:enum, %w[auto grid2 grid3 one], 'auto'],
        'size' => [:enum, %w[s m l], 'm'], 'show_count' => [:bool, true], 'show_reading' => [:bool, true],
        'numbering' => [:bool, true], 'show_empty' => [:bool, false], 'max' => [:int, 1, 30, 12]
      }
    },
    'quote' => {
      'totals' => { 'title' => [:text, 200, ''], 'hide_zero' => [:bool, true], 'width' => [:enum, %w[half full], 'half'] }
    }
  }.freeze

  module_function

  def blocks_for(kind) = COMMON_BLOCKS.merge(KIND_BLOCKS.fetch(kind.to_s))

  # para a paleta e os ajustes do estúdio: tipos, os padrões e a regra de cada opção (a tela monta o formulário com ela)
  def block_types(kind)
    blocks_for(kind).map do |type, options|
      { 'type' => type, 'defaults' => defaults(kind, type, options), 'options' => options.transform_values { |rule| describe(kind, rule) } }
    end
  end

  def describe(kind, rule)
    type, first, second = rule
    case type
    when :enum then { 'kind' => 'enum', 'values' => first }
    when :int then { 'kind' => 'int', 'min' => first, 'max' => second }
    when :text then { 'kind' => 'text', 'max' => first }
    when :list then { 'kind' => 'list', 'max' => first, 'length' => second }
    when :group then { 'kind' => 'group', 'values' => Outsider::Erp::Prints::Catalog.groups(kind).keys }
    when :table then { 'kind' => 'table', 'values' => Outsider::Erp::Prints::Catalog.tables(kind).keys }
    when :long_text then { 'kind' => 'long_text', 'values' => Outsider::Erp::Prints::Catalog.texts(kind).keys }
    else { 'kind' => type.to_s }
    end
  end

  def theme(content) = normalize_theme(content.to_h['theme'])

  def normalize(kind, content)
    data = content.to_h.deep_stringify_keys
    { 'theme' => normalize_theme(data['theme']), 'fields' => normalize_fields(kind, data['fields']),
      'blocks' => normalize_blocks(kind, data['blocks']) }
  end

  # ids dos anexos de imagem que os blocos usam (o resto do modelo é apagado ao salvar)
  def image_ids(content)
    Array(content.to_h['blocks']).filter_map { |block| block['image_id'].to_i if block.is_a?(Hash) && block['image_id'].present? }
  end

  def normalize_theme(theme)
    theme = theme.is_a?(Hash) ? theme : {}
    given = theme['colors'].is_a?(Hash) ? theme['colors'] : {}
    colors = COLORS.to_h { |key, fallback| [key, given[key].to_s.match?(HEX) ? given[key].to_s.upcase : fallback] }
    {
      'colors' => colors, 'heading_font' => pick(theme['heading_font'], FONTS), 'body_font' => pick(theme['body_font'], FONTS),
      'size' => theme['size'].to_i.between?(7, 13) ? theme['size'].to_i : THEME['size'],
      'margin' => pick(theme['margin'], %w[m s l]), 'page_numbers' => theme.key?('page_numbers') ? theme['page_numbers'] == true : true
    }
  end

  # cada lista do catálogo na ordem escolhida; campo novo do catálogo entra no fim com o padrão dele
  def normalize_fields(kind, fields)
    fields = fields.is_a?(Hash) ? fields : {}
    Outsider::Erp::Prints::Catalog.lists(kind).to_h do |list, defaults|
      known = defaults.to_h
      chosen = Array(fields[list]).filter_map do |item|
        key = item.is_a?(Hash) ? item['key'].to_s : nil
        [key, item['on'] == true] if known.key?(key)
      end.uniq(&:first)
      missing = defaults.reject { |key, _| chosen.any? { |picked, _| picked == key } }
      [list, (chosen + missing).map { |key, on| { 'key' => key, 'on' => on } }]
    end
  end

  def normalize_blocks(kind, blocks)
    schema = blocks_for(kind)
    list = Array(blocks).first(MAX_BLOCKS).filter_map do |block|
      next unless block.is_a?(Hash) && schema.key?(block['type'].to_s)

      type = block['type'].to_s
      { 'id' => block_id(block['id']), 'type' => type }.merge(options(kind, schema[type], block))
    end
    list.uniq { |block| block['id'] }
  end

  def defaults(kind, type, options = blocks_for(kind)[type])
    options(kind, options, {}).merge('type' => type)
  end

  def options(kind, schema, block)
    schema.to_h { |name, rule| [name, value(kind, rule, block[name])] }
  end

  def value(kind, rule, raw)
    case rule.first
    when :enum then pick(raw, rule[1], rule[2])
    when :int then raw.to_s.match?(/\A-?\d+\z/) ? raw.to_i.clamp(rule[1], rule[2]) : rule[3]
    when :bool then raw.nil? ? rule[1] : ActiveModel::Type::Boolean.new.cast(raw) == true
    when :text then raw.nil? ? rule[2] : raw.to_s.first(rule[1])
    when :list then raw.nil? ? rule[3] : Array(raw).map { |item| item.to_s.squish.first(rule[2]) }.compact_blank.first(rule[1])
    when :image then raw.to_s.match?(/\A\d+\z/) ? raw.to_i : nil
    when :group then pick(raw, Outsider::Erp::Prints::Catalog.groups(kind).keys)
    when :table then pick(raw, Outsider::Erp::Prints::Catalog.tables(kind).keys)
    when :long_text then pick(raw, Outsider::Erp::Prints::Catalog.texts(kind).keys)
    end
  end

  def pick(raw, allowed, fallback = allowed.first)
    allowed.include?(raw.to_s) ? raw.to_s : fallback
  end

  def block_id(raw)
    id = raw.to_s.gsub(/[^a-zA-Z0-9_-]/, '').first(40)
    id.presence || "b#{SecureRandom.hex(4)}"
  end
end
# rubocop:enable Metrics/ModuleLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
