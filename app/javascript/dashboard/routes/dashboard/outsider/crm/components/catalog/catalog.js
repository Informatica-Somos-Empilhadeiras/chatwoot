// OUTSIDER: constantes e utilidades do catálogo de máquinas e acessórios (mesmos limites do backend,
// ver Outsider::Crm::Product).

export const PRODUCT_KINDS = ['machine', 'accessory'];

export const KIND_COLORS = {
  machine: 'bg-n-blue-3 text-n-blue-11',
  accessory: 'bg-n-teal-3 text-n-teal-11',
};

// "Máquina" ou "Acessório"
export const kindLabel = (t, kind) =>
  kind === 'accessory'
    ? t('OUTSIDER_CRM.CATALOG.KINDS.ACCESSORY')
    : t('OUTSIDER_CRM.CATALOG.KINDS.MACHINE');

export const IMAGE_TYPES = ['image/png', 'image/jpeg'];

export const MAX_SPECS = 40;
export const MAX_FEATURES = 60;
export const MAX_QUANTITY = 1000000;

// quantidade disponível ou reservada: vazio = não controla (null); inválido = NaN
export const parseStock = text => {
  const value = String(text ?? '').trim();
  if (!value) return null;
  const number = Number(value);
  return Number.isInteger(number) && number >= 0 && number < MAX_QUANTITY
    ? number
    : NaN;
};

export const hasStock = product =>
  product.available_quantity != null || product.reserved_quantity != null;

// tipo da proposta que um item do catálogo abre: locação só quando ele não tem preço de venda
export const proposalKindFor = product =>
  !product.sale_price_cents && product.rental_price_cents ? 'rental' : 'sale';
export const SPEC_MAX_LENGTH = 120;
export const FEATURE_MAX_LENGTH = 200;

// chave estável para as linhas editáveis (v-for), que não vai para o servidor
let lastRowId = 0;
export const newRowId = () => {
  lastRowId += 1;
  return lastRowId;
};

// troca o item de lugar com o vizinho (step -1 sobe, 1 desce); devolve uma lista nova
export const moveItem = (list, index, step) => {
  const target = index + step;
  if (target < 0 || target >= list.length) return list;
  const copy = [...list];
  [copy[index], copy[target]] = [copy[target], copy[index]];
  return copy;
};
