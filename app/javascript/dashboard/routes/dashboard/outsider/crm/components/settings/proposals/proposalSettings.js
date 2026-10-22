// OUTSIDER: constantes de Configurações > Propostas: chaves do conteúdo dos modelos (ver
// app/models/outsider/crm/proposal_template.rb), campos automáticos dos textos (ver
// app/services/outsider/crm/proposal_fields.rb) e as mensagens de erro do servidor.
import { errorMessage } from '../../../helpers';

export const COMPANY_KEYS = [
  'legal_name',
  'trade_name',
  'cnpj',
  'address',
  'city',
  'documents_email',
  'bank_details',
];

// textos do modelo, na ordem em que aparecem na proposta; multiline vira caixa de texto grande
export const TEXT_FIELDS = [
  { key: 'title_prefix' },
  { key: 'intro', multiline: true },
  { key: 'total_label' },
  { key: 'conditions_heading' },
  { key: 'parties_text', multiline: true },
  { key: 'acceptance_text', multiline: true },
  { key: 'closing', multiline: true },
  { key: 'order_heading' },
  { key: 'bank_heading' },
  { key: 'documents_heading' },
  { key: 'signature_box', multiline: true },
];

export const TEXT_KEYS = TEXT_FIELDS.map(field => field.key);

export const FLAG_KEYS = [
  'show_specs',
  'show_discount',
  'show_parties',
  'show_bank',
];

export const MAX_CONDITIONS = 40;

// linha do editor de condições; uid só serve de chave na tela e não vai para o servidor
let nextUid = 0;
export const conditionRow = (condition = {}) => {
  nextUid += 1;
  return {
    uid: `row-${nextUid}`,
    label: condition.label || '',
    text: condition.text || '',
  };
};
export const MAX_TEXT = 5000;
export const MAX_LABEL = 120;

// campos que o PDF troca pelo valor da proposta
export const PROPOSAL_FIELDS = [
  {
    group: 'cliente',
    keys: [
      'empresa',
      'documento',
      'ie',
      'endereco',
      'bairro',
      'cidade',
      'estado',
      'cep',
      'telefone',
      'email',
      'atencao',
      'endereco_completo',
    ],
  },
  {
    group: 'proposta',
    keys: ['numero', 'titulo', 'validade', 'data', 'total'],
  },
  {
    group: 'empresa',
    keys: [
      'razao_social',
      'nome_fantasia',
      'cnpj',
      'endereco',
      'cidade',
      'email_documentos',
    ],
  },
  { group: 'maquina', keys: ['nome', 'marca'] },
  { group: 'vendedor', keys: ['nome', 'cargo', 'telefone'] },
];

const MONTHS = [
  'Janeiro',
  'Fevereiro',
  'Março',
  'Abril',
  'Maio',
  'Junho',
  'Julho',
  'Agosto',
  'Setembro',
  'Outubro',
  'Novembro',
  'Dezembro',
];

// igual à linha de data do PDF: "Goiânia, 21 de Outubro de 2026"
export const dateLine = city => {
  const today = new Date();
  const date = `${String(today.getDate()).padStart(2, '0')} de ${MONTHS[today.getMonth()]} de ${today.getFullYear()}`;
  return [city?.trim(), date].filter(Boolean).join(', ');
};

const INVALID_MESSAGES = {
  next_number: t => t('OUTSIDER_CRM.PROPOSAL_SETTINGS.INVALID.NEXT_NUMBER'),
  unit: t => t('OUTSIDER_CRM.PROPOSAL_SETTINGS.INVALID.UNIT'),
  view: t => t('OUTSIDER_CRM.PROPOSAL_SETTINGS.INVALID.VIEW'),
  user_ids: t => t('OUTSIDER_CRM.PROPOSAL_SETTINGS.INVALID.USER_IDS'),
};

// 422 { error: 'invalid', message: 'next_number' } vira uma frase; o resto segue o padrão do CRM
export const settingsError = (t, error) => {
  const data = error?.response?.data || {};
  if (
    data.error === 'invalid' &&
    Object.hasOwn(INVALID_MESSAGES, data.message)
  ) {
    return INVALID_MESSAGES[data.message](t);
  }
  if (data.error === 'invalid_image' && !data.message) {
    return t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.IMAGE_INVALID');
  }
  return errorMessage(t, error);
};
