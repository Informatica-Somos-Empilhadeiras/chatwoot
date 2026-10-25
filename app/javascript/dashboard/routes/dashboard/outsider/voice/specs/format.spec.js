import { formatPhone, formatDuration, formatTalkTime } from '../format';

describe('voice format', () => {
  it('shows phone numbers the Brazilian way', () => {
    expect(formatPhone('+5562999998888')).toBe('(62) 99999-8888');
    expect(formatPhone('06232345678')).toBe('(62) 3234-5678');
    expect(formatPhone('08001234567')).toBe('0800 123 4567');
    expect(formatPhone('202')).toBe('202');
  });

  it('shows call and month durations', () => {
    expect(formatDuration(187)).toBe('3:07');
    expect(formatDuration(3725)).toBe('1:02:05');
    expect(formatTalkTime(41940)).toBe('11 h 39 min');
    expect(formatTalkTime(2700)).toBe('45 min');
  });
});
