import {
  kindForTab,
  parseKey,
  periodRange,
  recordKey,
  relativeDay,
  shortName,
  statusClass,
  titleCase,
} from '../recordsConfig';

const t = (key, values) => (values ? `${key}:${JSON.stringify(values)}` : key);

describe('recordsConfig', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-11-20T15:00:00.000Z'));
  });
  afterEach(() => vi.useRealTimers());

  it('maps tabs and route keys', () => {
    expect(kindForTab('os')).toBe('orders');
    expect(kindForTab('nada')).toBeNull();
    expect(recordKey({ banco: 'somosemp', numero: 4117 })).toBe(
      'somosemp:4117'
    );
    expect(parseKey('somosemp:4117')).toEqual({
      company: 'somosemp',
      number: 4117,
    });
    expect(parseKey('somosemp:abc')).toBeNull();
  });

  it('counts days in Brasília time, past and future', () => {
    // meia-noite de Brasília chega do ERP como 03:00 UTC
    expect(relativeDay(t, '2026-11-20T03:00:00.000Z')).toBe(
      'OUTSIDER_ERP.RECORDS.TODAY'
    );
    expect(relativeDay(t, '2026-11-19T03:00:00.000Z')).toBe(
      'OUTSIDER_ERP.RECORDS.YESTERDAY'
    );
    expect(relativeDay(t, '2026-11-17T03:00:00.000Z')).toBe(
      'OUTSIDER_ERP.RECORDS.DAYS_AGO:{"n":3}'
    );
    expect(relativeDay(t, '2026-11-21T03:00:00.000Z')).toBe(
      'OUTSIDER_ERP.RECORDS.TOMORROW'
    );
    expect(relativeDay(t, '2026-11-24T03:00:00.000Z')).toBe(
      'OUTSIDER_ERP.RECORDS.IN_DAYS:{"n":4}'
    );
    expect(relativeDay(t, '2025-01-01T03:00:00.000Z')).toBe('');
  });

  it('builds the period presets', () => {
    expect(periodRange('last_year')).toEqual({
      from: '2025-01-01',
      to: '2025-12-31',
    });
    expect(periodRange('year')).toEqual({
      from: '2026-01-01',
      to: '2026-11-20',
    });
    expect(periodRange('all')).toEqual({ from: '', to: '' });
  });

  it('formats names and status colors', () => {
    expect(titleCase('ATACADAO DIA A DIA LTDA')).toBe(
      'Atacadao Dia A Dia LTDA'
    );
    expect(shortName('LUCAS FERREIRA RORIZ')).toBe('Lucas Roriz');
    expect(statusClass('FATURADO')).toContain('blue');
    expect(statusClass('CANCELADA')).toContain('ruby');
  });
});
