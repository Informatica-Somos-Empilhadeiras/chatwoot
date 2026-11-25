# OUTSIDER: modelos dos textos de envio ao cliente, que as Configurações do ERP guardam e o agente ainda edita antes de
# enviar (Outsider::Erp::BudgetTexts preenche): do orçamento ({numero}, {contato}, {cliente}, {total}, {pagamento},
# {vendedor}), do relatório da OS ({numero}, {contato}, {cliente}, {tecnico}, {vendedor}), da nota fiscal ({numero},
# {contato}, {cliente}, {vendedor}), do contrato e da ficha da máquina ({numero}, {contato}, {cliente}, {vendedor}).
# LIMITS: tamanho máximo.
module Outsider::Erp::SendTexts
  DEFAULTS = {
    'quote_email_subject' => 'Orçamento Nº {numero}',
    'quote_email_body' => "Olá, {contato}!\n\nSegue em anexo o orçamento Nº {numero} de peças e serviços, no valor de {total}, " \
                          "com pagamento em {pagamento}.\n\nQualquer dúvida, estou à disposição.\n{vendedor}",
    'quote_whatsapp_text' => 'Olá, {contato}! Segue o orçamento Nº {numero}, no valor de {total}.',
    'os_email_subject' => 'Ordem de Serviço Nº {numero}',
    'os_email_body' => "Olá, {contato}!\n\nSegue em anexo o relatório da Ordem de Serviço Nº {numero}, com o check-list e as fotos " \
                       "do atendimento.\n\nQualquer dúvida, estou à disposição.\n{vendedor}",
    'os_whatsapp_text' => 'Olá, {contato}! Segue o relatório da Ordem de Serviço Nº {numero}.',
    'nf_email_subject' => 'Nota fiscal Nº {numero}',
    'nf_email_body' => "Olá, {contato}!\n\nSegue em anexo a nota fiscal Nº {numero}.\n\nQualquer dúvida, estou à disposição.\n{vendedor}",
    'nf_whatsapp_text' => 'Olá, {contato}! Segue a nota fiscal Nº {numero}.',
    'contract_email_subject' => 'Contrato Nº {numero}',
    'contract_email_body' => "Olá, {contato}!\n\nSegue em anexo o contrato Nº {numero}.\n\nQualquer dúvida, estou à disposição.\n{vendedor}",
    'contract_whatsapp_text' => 'Olá, {contato}! Segue o contrato Nº {numero}.',
    'machine_email_subject' => 'Ficha da máquina',
    'machine_email_body' => "Olá, {contato}!\n\nSegue em anexo a ficha da máquina, com os contratos e o histórico de OS.\n\n" \
                            "Qualquer dúvida, estou à disposição.\n{vendedor}",
    'machine_whatsapp_text' => 'Olá, {contato}! Segue a ficha da máquina.'
  }.freeze
  LIMITS = { 'quote_email_subject' => 200, 'quote_email_body' => 4000, 'quote_whatsapp_text' => 2000, 'os_email_subject' => 200,
             'os_email_body' => 4000, 'os_whatsapp_text' => 2000, 'nf_email_subject' => 200, 'nf_email_body' => 4000,
             'nf_whatsapp_text' => 2000, 'contract_email_subject' => 200, 'contract_email_body' => 4000, 'contract_whatsapp_text' => 2000,
             'machine_email_subject' => 200, 'machine_email_body' => 4000, 'machine_whatsapp_text' => 2000 }.freeze
end
