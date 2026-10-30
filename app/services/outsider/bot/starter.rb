# OUTSIDER: o desenho com que um fluxo novo começa: boas-vindas, horário de atendimento, menu com três
# opções e cada opção passando para a equipe. Serve de exemplo para editar.
module Outsider::Bot::Starter
  module_function

  def graph
    nodes = [
      node('start', 'start', 40, 200, 'trigger' => 'unassigned_message', 'cooldown_hours' => 12, 'timeout_minutes' => 60,
                                      'set_pending' => true, 'only_unassigned' => true),
      node('welcome', 'message', 400, 200, 'text' => t('welcome'), 'delay_seconds' => 1),
      node('hours', 'condition', 760, 200, 'hours' => Outsider::Bot::Graph::DEFAULT_HOURS, 'timezone' => Outsider::Bot::Graph::DEFAULT_TIMEZONE),
      node('menu', 'menu', 1120, 60, 'text' => t('menu_text'), 'title' => '', 'footer' => t('menu_footer'), 'style' => 'list',
                                     'button_label' => t('menu_button'), 'max_attempts' => 2, 'invalid_text' => t('invalid'),
                                     'options' => [option('opt_buy', t('buy')), option('opt_rent', t('rent')), option('opt_support', t('support'))]),
      node('closed', 'handoff', 1120, 380, 'text' => t('closed')),
      node('to_sales', 'handoff', 1480, 0, 'text' => t('to_sales')),
      node('to_rent', 'handoff', 1480, 160, 'text' => t('to_sales')),
      node('to_support', 'handoff', 1480, 320, 'text' => t('to_support'))
    ]
    edges = [
      edge('start', 'next', 'welcome'), edge('welcome', 'next', 'hours'), edge('hours', 'inside', 'menu'),
      edge('hours', 'outside', 'closed'), edge('menu', 'opt_buy', 'to_sales'), edge('menu', 'opt_rent', 'to_rent'),
      edge('menu', 'opt_support', 'to_support'), edge('menu', 'invalid', 'to_support')
    ]
    Outsider::Bot::Graph.sanitize('nodes' => nodes, 'edges' => edges)
  end

  def node(id, type, left, top, data)
    { 'id' => id, 'type' => type, 'x' => left, 'y' => top, 'data' => data }
  end

  def option(id, label)
    { 'id' => id, 'label' => label, 'description' => '' }
  end

  def edge(from, port, to)
    { 'id' => "e_#{from}_#{port}", 'from' => from, 'port' => port, 'to' => to }
  end

  def t(key)
    I18n.t("outsider_bot.starter.#{key}")
  end
end
