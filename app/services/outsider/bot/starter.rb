# OUTSIDER: o desenho com que um fluxo novo começa: boas-vindas, horário de atendimento, menu com três
# opções e cada opção passando para a equipe. Serve de exemplo para editar. document_graph é o exemplo
# com integrações (2ª via de documento).
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

  # exemplo de integração: confere no sistema da empresa se o WhatsApp é o do cadastro antes de mandar
  # documento (dados de um cliente só para ele). As conexões ficam em branco para o administrador escolher.
  def document_graph
    nodes = [
      node('start', 'start', 40, 240, 'trigger' => 'keyword', 'keywords' => d('keywords').split(','), 'cooldown_hours' => 0,
                                      'timeout_minutes' => 30, 'set_pending' => true, 'only_unassigned' => true),
      node('ask', 'question', 400, 240, 'text' => d('ask'), 'variable' => 'cpf_cnpj'),
      node('lookup', 'api', 760, 240, 'method' => 'GET', 'path' => '/clientes',
                                      'query' => [{ 'key' => 'cpf_cnpj', 'value' => '{{cpf_cnpj | digitos}}' }],
                                      'variable' => 'cadastro', 'mappings' => [{ 'path' => 'telefone', 'variable' => 'telefone_cadastro' }]),
      node('verify', 'decision', 1120, 240, 'subject' => '{{telefone_cadastro | digitos | ultimos:8}}',
                                            'rules' => [{ 'id' => 'no_phone', 'label' => d('no_phone'), 'operator' => 'empty', 'value' => '' },
                                                        { 'id' => 'same_phone', 'label' => d('same_phone'), 'operator' => 'equals',
                                                          'value' => '{{contato.telefone | digitos | ultimos:8}}' }]),
      node('search', 'doc_search', 1480, 120, 'folder' => '/Clientes/{{cpf_cnpj | digitos}}', 'query' => '', 'extensions' => ['pdf'],
                                              'limit' => 5, 'pick' => 'ask', 'text' => d('choose'), 'button_label' => d('button'),
                                              'variable' => 'documento'),
      node('send', 'doc_send', 1840, 40, 'source' => 'documento', 'mode' => 'file', 'caption' => d('caption')),
      node('done', 'end', 2200, 40, 'text' => d('done')),
      node('nothing', 'handoff', 1840, 240, 'text' => d('nothing')),
      node('not_verified', 'handoff', 1480, 420, 'text' => d('not_verified')),
      node('failure', 'handoff', 1120, 560, 'text' => d('failure'))
    ]
    edges = [
      edge('start', 'next', 'ask'), edge('ask', 'default', 'lookup'), edge('lookup', 'ok', 'verify'), edge('lookup', 'error', 'failure'),
      edge('verify', 'no_phone', 'not_verified'), edge('verify', 'same_phone', 'search'), edge('verify', 'default', 'not_verified'),
      edge('search', 'found', 'send'), edge('search', 'not_found', 'nothing'), edge('search', 'error', 'failure'),
      edge('send', 'ok', 'done'), edge('send', 'error', 'failure')
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

  def d(key)
    I18n.t("outsider_bot.document_example.#{key}")
  end
end
