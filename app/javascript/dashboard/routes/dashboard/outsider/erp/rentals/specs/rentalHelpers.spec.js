import {
  contractDue,
  contractType,
  daysUntil,
  hourMeter,
  machineName,
  machineTag,
  periodKey,
} from '../rentalHelpers';

const NOW = new Date('2026-11-25T15:00:00Z');

describe('rentalHelpers', () => {
  it('reads the contract type from the ERP text', () => {
    expect(contractType('CONTRATO DE LOCAÇÃO')).toBe('RENTAL');
    expect(contractType('CONTRATO DE MANUTENÇÃO')).toBe('MAINTENANCE');
    expect(contractType('PRESTAÇÃO DE SERVIÇO')).toBe('SERVICE');
    expect(contractType('')).toBe('');
  });

  it('maps the billing period', () => {
    expect(periodKey(' mensal ')).toBe('PER_MONTH');
    expect(periodKey('SEMANAL')).toBe('PER_WEEK');
    expect(periodKey('')).toBe('');
  });

  it('counts days in the Brasília calendar', () => {
    expect(daysUntil('2026-12-05T03:00:00.000Z', NOW)).toBe(10);
    expect(daysUntil('2026-11-25T03:00:00.000Z', NOW)).toBe(0);
    expect(daysUntil(null, NOW)).toBeNull();
  });

  it('flags active contracts ending in 30 days or already past their end', () => {
    const row = termino => ({ status: 'ATIVO', termino });
    expect(contractDue(row('2026-12-07T03:00:00.000Z'), NOW)).toEqual({
      key: 'DUE_IN',
      days: 12,
    });
    expect(contractDue(row('2026-11-25T03:00:00.000Z'), NOW)).toEqual({
      key: 'DUE_TODAY',
      days: 0,
    });
    expect(contractDue(row('2026-11-20T03:00:00.000Z'), NOW)).toEqual({
      key: 'OVERDUE',
      days: 5,
    });
    expect(contractDue(row('2027-10-31T03:00:00.000Z'), NOW)).toBeNull();
    expect(
      contractDue({ status: 'CONCLUÍDO', termino: '2026-11-20' }, NOW)
    ).toBeNull();
  });

  it('names machines and shows the hour meter', () => {
    expect(machineName({ descricao: 'EMPILHADEIRA 2,5T GLP' })).toBe(
      'Empilhadeira 2,5T GLP'
    );
    expect(
      machineName({ descricao: '010353J8544 - CPCD35-XC5K2/480-3V' })
    ).toBe('010353J8544 - CPCD35-XC5K2/480-3V');
    expect(machineName({ descricao: 'empilhadeira elétrica de 3 rodas' })).toBe(
      'Empilhadeira Elétrica De 3 Rodas'
    );
    expect(machineName({ maquina: 77 })).toBe('#77');
    expect(machineTag({ patrimonio: 'SE-0412', numero: 3 })).toBe('SE-0412');
    expect(hourMeter('3412')).toBe('3.412 h');
    expect(hourMeter('3.412,6')).toBe('3.413 h');
    expect(hourMeter('sem leitura')).toBe('sem leitura');
    expect(hourMeter('')).toBe('');
    expect(hourMeter('0')).toBe('');
    expect(hourMeter('0,0')).toBe('');
  });
});
