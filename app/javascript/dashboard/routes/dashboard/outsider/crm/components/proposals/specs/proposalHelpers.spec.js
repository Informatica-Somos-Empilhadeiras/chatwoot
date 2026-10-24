import {
  addDays,
  conditionLabel,
  discountPercent,
  itemTotal,
  lookupDocument,
  parsePercent,
  paymentConditionIndex,
  percentDiscount,
  productItemFields,
} from '../proposalHelpers';
import { parseStock, proposalKindFor } from '../../catalog/catalog';

describe('proposal item discount in percent', () => {
  const item = { quantity: '2', unit_price: '1.000,00', discount: '' };

  it('computes the discount in cents from the percentage of the gross value', () => {
    expect(percentDiscount(item, '5')).toBe(10000);
    expect(percentDiscount(item, '2,5')).toBe(5000);
    expect(percentDiscount(item, '')).toBe(0);
    expect(percentDiscount(item, '120')).toBeNaN();
  });

  it('shows what a discount in R$ means in percent', () => {
    expect(discountPercent({ ...item, discount: '100,00' })).toBe('5');
    expect(discountPercent({ ...item, discount: '33,33' })).toBe('1,67');
    expect(discountPercent(item)).toBeNull();
  });

  it('parses percentages and keeps the line total consistent', () => {
    expect(parsePercent('10%')).toBe(10);
    expect(parsePercent('abc')).toBeNaN();
    expect(itemTotal({ ...item, discount: '100,00' })).toBe(190000);
  });
});

describe('proposal from the catalog (Entrega 19)', () => {
  const product = {
    id: 7,
    kind: 'machine',
    name: 'Empilhadeira 3,5t',
    sale_price_cents: 15000000,
    rental_price_cents: 900000,
    image_url: '/foto.png',
  };

  it('fills the item with the price of the proposal kind', () => {
    expect(productItemFields(product, 'sale')).toMatchObject({
      product_id: 7,
      description: 'Empilhadeira 3,5t',
      unit_price: '150000,00',
      show_details: true,
    });
    expect(productItemFields(product, 'rental').unit_price).toBe('9000,00');
  });

  it('opens a rental proposal only for items without a sale price', () => {
    expect(proposalKindFor(product)).toBe('sale');
    expect(proposalKindFor({ ...product, sale_price_cents: 0 })).toBe('rental');
  });

  it('reads the optional stock quantities', () => {
    expect(parseStock('')).toBeNull();
    expect(parseStock('3')).toBe(3);
    expect(parseStock('-1')).toBeNaN();
    expect(parseStock('1,5')).toBeNaN();
  });
});

describe('payment row and CNPJ lookup (Entrega 19)', () => {
  it('finds the payment row, but not the late payment one', () => {
    const conditions = [
      { label: 'Frete:', text: 'CIF' },
      { label: 'Atraso de Pagamento:', text: 'multa' },
      { label: 'Pagamento com recurso próprio', text: 'A VISTA' },
    ];
    expect(paymentConditionIndex(conditions)).toBe(2);
    expect(paymentConditionIndex(conditions.slice(0, 2))).toBe(-1);
  });

  it('accepts the classic and the alphanumeric CNPJ, not a CPF', () => {
    expect(lookupDocument('11.222.333/0001-81')).toBe('11222333000181');
    expect(lookupDocument('12.abc.345/01de-35')).toBe('12ABC34501DE35');
    expect(lookupDocument('123.456.789-09')).toBe('');
  });
});

describe('simpler proposal editor (Entrega 20)', () => {
  it('shows condition titles without the bold marks and the colon', () => {
    expect(conditionLabel('**Impostos:**')).toBe('Impostos');
    expect(
      conditionLabel('**Documentos para análise de crédito PJ:**\n\n* Primeira')
    ).toBe('Documentos para análise de crédito PJ');
    expect(conditionLabel('Frete:')).toBe('Frete');
  });

  it('counts the validity days from the proposal date', () => {
    expect(addDays('2026-10-24', 5)).toBe('2026-10-29');
    expect(addDays('2026-12-30', 5)).toBe('2027-01-04');
  });
});
