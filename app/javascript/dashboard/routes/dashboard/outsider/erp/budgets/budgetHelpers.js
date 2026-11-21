// OUTSIDER: contas e textos do orçamento de peças e serviços (Outsider::Erp::Budget) usados pela tela. As contas são
// as mesmas do servidor (Budget.line_total): quantidade x preço menos o desconto em % da linha, sem impostos (o ERP
// calcula ICMS/IPI/ST ao gravar).
import { erpErrorMessage } from '../erpStore';

// "1.234,56", "1234.56" ou número -> número (vazio = fallback)
export const parseNumber = (value, fallback = 0) => {
  if (typeof value === 'number')
    return Number.isFinite(value) ? value : fallback;
  let text = String(value ?? '').trim();
  if (!text) return fallback;
  if (text.includes(',')) text = text.replace(/\./g, '').replace(',', '.');
  const number = Number(text);
  return Number.isFinite(number) ? number : fallback;
};

const round2 = value => Math.round(value * 100) / 100;

export const lineTotal = item => {
  const gross = parseNumber(item.quantidade, 1) * parseNumber(item.preco);
  return round2(gross - (gross * parseNumber(item.desconto)) / 100);
};

export const lineDiscount = item => {
  const gross = parseNumber(item.quantidade, 1) * parseNumber(item.preco);
  return round2((gross * parseNumber(item.desconto)) / 100);
};

// peças, serviços, descontos e total (sem impostos) do que está na tela
export const budgetTotals = (items, freight = 0) => {
  const sum = (list, fn) =>
    round2(list.reduce((acc, item) => acc + fn(item), 0));
  const parts = items.filter(item => Number(item.tipo) !== 1);
  const services = items.filter(item => Number(item.tipo) === 1);
  const gross = item =>
    parseNumber(item.quantidade, 1) * parseNumber(item.preco);
  return {
    parts: sum(parts, gross),
    services: sum(services, gross),
    discounts: sum(items, lineDiscount),
    freight: parseNumber(freight),
    total: round2(sum(items, lineTotal) + parseNumber(freight)),
  };
};

// 3181.47 -> "3.181,47" (campos de valor); quantidade sem casas quando inteira
export const formatNumber = (value, digits = 2) =>
  Number(value || 0).toLocaleString('pt-BR', {
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  });

export const formatQty = value => {
  const number = parseNumber(value, 1);
  return Number.isInteger(number)
    ? String(number)
    : number.toLocaleString('pt-BR', { maximumFractionDigits: 4 });
};

// chave de um orçamento do ERP (unidade + número), para juntar o espelho com os registros do chat
export const quoteKey = (company, number) => `${company}:${number}`;

// "Orçamento Nº 3310 - SUPERMERCADO.pdf" vindo do servidor
export const pdfFilename = (headers, fallback) => {
  const header = headers?.['content-disposition'] || '';
  const encoded = header.match(/filename\*=UTF-8''([^;]+)/i);
  if (encoded) return decodeURIComponent(encoded[1]);
  const plain = header.match(/filename="?([^";]+)"?/i);
  return plain ? plain[1] : fallback;
};

// resposta de erro de um pedido "blob" (PDF) chega como Blob: lê o JSON para mostrar o motivo
export const blobError = async error => {
  try {
    const data = JSON.parse(await error?.response?.data?.text?.());
    return { ...error, response: { ...error.response, data } };
  } catch {
    return error;
  }
};

const KNOWN_REASONS = [
  'senha_comercial',
  'sem_os',
  'muitas_os',
  'os_repetida',
  'partes',
  'sem_tecnico',
  'os_nao_encontrada',
  'os_aberta',
  'os_cancelada',
  'no_conversation',
  'not_draft',
  'in_erp',
  'company',
  'customer',
  'company_items',
  'too_many_items',
  'no_companies',
  'number',
  'forma_pagto',
  'vendedor',
  'sem_cliente',
  'empresa',
  'sem_itens',
  'em_andamento',
  'cliente_inexistente',
  'sem_numero',
  'quote_write_disabled',
  'erro_interno',
  'not_in_erp',
  'channel',
  'no_phone',
  'inbox',
  'no_mail_server',
  'subject_required',
  'no_email',
  'too_many_emails',
  'invalid_email',
  'too_long',
  'budget_forbidden',
  'erp_quote_not_found',
  'desconto_sem_liberacao',
  'codigo_gerente',
  'senha_gerente',
  'tentativas',
  'senha_invalida',
  'sem_permissao',
  'sem_cadastro',
  'em_uso',
  'status',
  'em_edicao',
  'not_revising',
];

// motivo do servidor (gravação, envio, formulário) em texto; o resto cai na mensagem geral do ERP
export const reasonText = (t, reason) => {
  if (!reason) return '';
  const key = String(reason);
  if (KNOWN_REASONS.includes(key))
    return t(`OUTSIDER_ERP.BUDGET.REASONS.${key.toUpperCase()}`);
  return t('OUTSIDER_ERP.BUDGET.REASONS.ERP', { detail: key.slice(0, 80) });
};

export const budgetErrorMessage = (t, error) => {
  const data = error?.response?.data || {};
  const reason =
    data.reason || (KNOWN_REASONS.includes(data.error) && data.error);
  return reason ? reasonText(t, reason) : erpErrorMessage(t, error);
};
