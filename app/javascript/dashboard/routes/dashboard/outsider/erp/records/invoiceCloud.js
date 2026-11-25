// OUTSIDER: aviso das notas fiscais que ainda não foram para a nuvem (Nextcloud). O servidor guarda o que já achou
// (Outsider::Erp::InvoiceCloud); aqui só se pergunta o estado das notas à vista. ok | missing | unknown
import ErpAPI from 'dashboard/api/outsider/erp';
import { erpState } from '../erpStore';

export const CLOUD_KINDS = ['invoices', 'service_invoices'];
export const cloudKey = (kind, company, number) =>
  `${kind}:${company}:${Number(number)}`;

export const fetchCloud = async (kind, keys) => {
  if (!erpState.nextcloudInvoices || !CLOUD_KINDS.includes(kind)) return {};
  if (!keys.length) return {};
  try {
    const { data } = await ErpAPI.invoiceCloud(kind, keys);
    return data.statuses || {};
  } catch {
    return {};
  }
};
