# OUTSIDER: leitura dos valores que vêm do editor de modelos (opções próprias de alguns blocos, cor, lista,
# sim/não, número dentro dos limites, título). Parte do Outsider::Crm::ProposalTemplateLayout.
module Outsider::Crm::ProposalTemplateLayout::Values
  private

  def block_options(raw, type)
    case type
    when 'specs' then machine_options(raw)
    when 'image' then { 'image_id' => raw['image_id'].presence&.to_i, 'width' => number(raw['width'], 40, 5..100),
                        'align' => pick(raw['align'], %w[center left right]) }
    when 'divider' then { 'color' => color(raw['color'], 'BFBFBF'), 'thickness' => number(raw['thickness'], 1, 0.5..4) }
    when 'spacer' then { 'height' => number(raw['height'], 8, 1..80) }
    else {}
    end
  end

  def block_style(raw, base)
    { 'visible' => boolean(raw.fetch('visible', true)), 'new_page' => boolean(raw['new_page']),
      'size' => number(raw['size'], base['size'], 6..16), 'bold' => boolean(raw['bold']), 'highlight' => boolean(raw['highlight']) }
  end

  def machine_options(raw)
    { 'image_side' => pick(raw['image_side'], %w[right left]), 'equipment' => boolean(raw.fetch('equipment', true)),
      'equipment_heading' => heading(raw, 'equipment_heading', Outsider::Crm::ProposalTemplateLayout::EQUIPMENT_HEADING) }
  end

  def heading(raw, key, default)
    raw.key?(key) ? raw[key].to_s.strip.first(200) : default
  end

  def color(value, default)
    value = value.to_s.delete('#')
    value.match?(/\A\h{6}\z/) ? value : default
  end

  # valor da lista ou o primeiro dela
  def pick(value, list)
    list.include?(value) ? value : list.first
  end

  def boolean(value)
    ActiveModel::Type::Boolean.new.cast(value) || false
  end

  def number(value, default, range)
    number = Float(value, exception: false)
    return default if number.nil?

    number.clamp(range.begin, range.end).round(1)
  end
end
