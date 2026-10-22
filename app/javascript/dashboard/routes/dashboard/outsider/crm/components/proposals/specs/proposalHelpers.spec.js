import {
  discountPercent,
  itemTotal,
  parsePercent,
  percentDiscount,
} from '../proposalHelpers';

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
