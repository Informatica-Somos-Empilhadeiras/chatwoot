// OUTSIDER: apoio do relatório de desempenho dos técnicos: períodos prontos, link para o pedido na seção ERP e o CSV
// (separado por ponto e vírgula, números com vírgula, para abrir direto no Excel).
import { companyName, ERP_ROUTE } from '../../erp/erpStore';

const iso = date => {
  const pad = value => String(value).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
};

export const PERIODS = ['month', 'last_month', 'days30', 'custom'];

// { from, to } (aaaa-mm-dd) de um período pronto; today é para os testes
export const periodRange = (period, today = new Date()) => {
  const year = today.getFullYear();
  const month = today.getMonth();
  if (period === 'last_month')
    return {
      from: iso(new Date(year, month - 1, 1)),
      to: iso(new Date(year, month, 0)),
    };
  if (period === 'days30') {
    const start = new Date(today);
    start.setDate(start.getDate() - 29);
    return { from: iso(start), to: iso(today) };
  }
  return { from: iso(new Date(year, month, 1)), to: iso(today) };
};

// o pedido aberto na seção ERP (aba Pedidos, painel de detalhe), onde o técnico é informado
export const saleLink = (accountId, sale) => ({
  name: ERP_ROUTE,
  params: { accountId, tab: 'pedidos' },
  query: { open: `${sale.unidade}:${sale.pedido}` },
});

export const notesText = sale =>
  (sale.notas || []).map(note => `${note.tipo} ${note.numero}`).join(', ');

const number = value =>
  Number(value || 0).toLocaleString('pt-BR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });

// o Excel só lê os acentos do CSV com a marca de UTF-8 no começo
const BOM = String.fromCharCode(0xfeff);

const cell = value => {
  const text = String(value ?? '');
  return /[;"\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
};

// uma linha por técnico em cada pedido (o valor creditado é a parte dele)
export const detailCsv = (sales, headers) => {
  const rows = sales.flatMap(sale =>
    sale.linhas.map(line => [
      line.tecnico,
      companyName(sale.unidade),
      sale.pedido,
      notesText(sale),
      sale.data_nota ? String(sale.data_nota).slice(0, 10) : '',
      sale.cliente,
      sale.vendedor,
      line.os,
      number(line.parte),
      number((sale.total * line.parte) / 100),
      number((sale.pecas * line.parte) / 100),
      number((sale.servicos * line.parte) / 100),
    ])
  );
  return (
    BOM + [headers, ...rows].map(row => row.map(cell).join(';')).join('\n')
  );
};

export const download = (text, filename) => {
  const url = URL.createObjectURL(new Blob([text], { type: 'text/csv' }));
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  link.click();
  URL.revokeObjectURL(url);
};
