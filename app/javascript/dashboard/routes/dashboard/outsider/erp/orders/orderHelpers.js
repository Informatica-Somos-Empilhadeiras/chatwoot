// OUTSIDER: textos e contas da OS feita no chat (Outsider::Erp::OrderDraft): motivos do servidor, linhas da conferência
// (Outsider::Erp::Orders::Checks), selo da lista e o total estimado (sem impostos, como o app do técnico).
import { ref } from 'vue';
import { erpErrorMessage } from '../erpStore';
import { parseNumber } from '../budgets/budgetHelpers';

const REASONS = [
  'estrutura',
  'usuario_erp',
  'permissao_os',
  'permissao_conversao',
  'cliente',
  'cliente_inativo',
  'maquina',
  'maquina_obrigatoria',
  'sem_itens',
  'produto_inexistente',
  'produto_bloqueado',
  'orcamento',
  'orcamento_status',
  'orcamento_com_os',
  'orcamento_com_pedido',
  'orcamento_em_uso',
  'orcamento_sem_itens',
  'orcamento_nao_fechado',
  'unidade',
  'tipo_atendimento',
  'classe',
  'sem_cliente',
  'cabecalho_recusado',
  'cabecalho_nao_gravado',
  'em_andamento',
  'order_write_disabled',
  'order_forbidden',
  'erro_interno',
  'not_draft',
  'in_erp',
  'company',
  'quote_number',
  'too_many_items',
  'item',
  'not_created',
  'cancelled',
  'os_mudou',
  'os_status',
];

// motivo do servidor (gravação, conferência, formulário) em texto; detail completa ("produto 491 bloqueado")
export const orderReasonText = (t, reason, detail = '') => {
  if (!reason) return '';
  const key = String(reason);
  if (REASONS.includes(key))
    return t(`OUTSIDER_ERP.ORDER_DRAFT.REASONS.${key.toUpperCase()}`, {
      detail: detail || '—',
    });
  return t('OUTSIDER_ERP.BUDGET.REASONS.ERP', { detail: key.slice(0, 80) });
};

export const orderErrorMessage = (t, error) => {
  const data = error?.response?.data || {};
  const reason = data.reason || (REASONS.includes(data.error) && data.error);
  return reason ? orderReasonText(t, reason) : erpErrorMessage(t, error);
};

const CHECKS_OK = [
  'estrutura',
  'permissao_os',
  'permissao_conversao',
  'cliente',
  'maquina',
  'produtos',
  'orcamento',
];

// uma linha da conferência: { key, ok, detail } -> texto (a que passou diz o que foi visto; a que falhou, o motivo)
export const checkText = (t, check) => {
  if (!check.ok) return orderReasonText(t, check.key, check.detail);
  const key = CHECKS_OK.includes(check.key) ? check.key : 'generic';
  if (key === 'maquina' && !check.detail)
    return t('OUTSIDER_ERP.ORDER_DRAFT.CHECKS.MAQUINA_NONE');
  return t(`OUTSIDER_ERP.ORDER_DRAFT.CHECKS.${key.toUpperCase()}`, {
    detail: check.detail || '',
  });
};

// total estimado do rascunho (quantidade x preço; o ERP calcula impostos quando o escritório salva a OS)
export const orderTotals = items => {
  const round2 = value => Math.round(value * 100) / 100;
  const sum = list =>
    round2(
      list.reduce(
        (acc, item) =>
          acc + parseNumber(item.quantidade, 1) * parseNumber(item.preco),
        0
      )
    );
  const parts = sum(items.filter(item => Number(item.tipo) !== 1));
  const services = sum(items.filter(item => Number(item.tipo) === 1));
  return { parts, services, total: round2(parts + services) };
};

export const isRecorded = draft => draft?.status === 'created';

// selo da OS na lista e no cabeçalho: gravando, falhou, gravada, cancelada ou rascunho
export const draftChip = (t, draft) => {
  if (draft.cancelled)
    return {
      text: t('OUTSIDER_ERP.ORDER_DRAFT.LIST.CANCELLED'),
      class: 'bg-n-slate-3 text-n-slate-11',
    };
  if (draft.status === 'created')
    return {
      text: t('OUTSIDER_ERP.ORDER_DRAFT.LIST.RECORDED'),
      class: 'bg-n-teal-3 text-n-teal-11',
    };
  if (draft.status === 'submitting' && !draft.stuck)
    return {
      text: t('OUTSIDER_ERP.ORDER_DRAFT.LIST.SUBMITTING'),
      class: 'bg-n-blue-3 text-n-blue-11',
      spinner: true,
    };
  if (draft.error || draft.stuck || draft.erp_number)
    return {
      text: t('OUTSIDER_ERP.ORDER_DRAFT.LIST.FAILED'),
      class: 'bg-n-ruby-3 text-n-ruby-11',
    };
  return {
    text: t('OUTSIDER_ERP.ORDER_DRAFT.LIST.NOT_RECORDED'),
    class: 'bg-n-alpha-2 text-n-slate-11',
  };
};

// "CBD20J-LI3 ELÉTRICA · série 08020JGG855" (sem descrição, o código da máquina)
export const machineLabel = machine =>
  [
    machine.descricao || machine.modelo,
    machine.serie && `série ${machine.serie}`,
  ]
    .filter(Boolean)
    .join(' · ') || `#${machine.codigo}`;

// orçamento que o desktop deixa converter: em NEGOCIAÇÃO (com ou sem acento, como vier do ERP)
export const isNegotiation = status =>
  String(status || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .trim()
    .toUpperCase() === 'NEGOCIACAO';

// muda a cada OS convertida ou cancelada fora da lista do contato (orçamento, seção ERP): a lista lê de novo
export const orderDraftsTick = ref(0);
