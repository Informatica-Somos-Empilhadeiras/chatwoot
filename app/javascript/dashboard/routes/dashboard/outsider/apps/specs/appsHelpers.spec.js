import {
  coversDay,
  dayKey,
  parseLocal,
  rangeOf,
  shift,
} from '../calendar/calendarDates';
import { initialsOf, replySubject } from '../mail/mailHelpers';
import { errorText } from '../appsErrors';

describe('calendarDates', () => {
  it('reads Microsoft local times without changing the time zone', () => {
    const date = parseLocal('2026-11-24T09:30:00.0000000');
    expect(dayKey(date)).toBe('2026-11-24');
    expect(date.getHours()).toBe(9);
    expect(date.getMinutes()).toBe(30);
  });

  it('builds day, week (from Monday) and whole-week month ranges', () => {
    const anchor = new Date(2026, 10, 24, 15);
    expect(rangeOf('day', anchor).days.map(dayKey)).toEqual(['2026-11-24']);

    const week = rangeOf('week', anchor);
    expect(dayKey(week.from)).toBe('2026-11-23');
    expect(week.days).toHaveLength(7);

    const month = rangeOf('month', anchor);
    expect(dayKey(month.from)).toBe('2026-10-26');
    expect(month.days).toHaveLength(42);
    expect(month.days.map(dayKey)).toContain('2026-11-30');
  });

  it('moves by one period', () => {
    const anchor = new Date(2026, 10, 24);
    expect(dayKey(shift('day', anchor, 1))).toBe('2026-11-25');
    expect(dayKey(shift('week', anchor, -1))).toBe('2026-11-17');
    expect(dayKey(shift('month', anchor, 1))).toBe('2026-12-01');
  });

  it('shows multi-day events on every day they cover', () => {
    const event = { start: '2026-11-24T00:00:00', end: '2026-11-26T00:00:00' };
    expect(coversDay(event, new Date(2026, 10, 24))).toBe(true);
    expect(coversDay(event, new Date(2026, 10, 25))).toBe(true);
    expect(coversDay(event, new Date(2026, 10, 26))).toBe(false);
  });
});

describe('mailHelpers', () => {
  it('makes initials and reply subjects', () => {
    expect(initialsOf('Maria da Silva')).toBe('MS');
    expect(initialsOf('joao@empresa.com')).toBe('J');
    expect(replySubject('reply', 'Orçamento')).toBe('RE: Orçamento');
    expect(replySubject('reply_all', 'RE: Orçamento')).toBe('RE: Orçamento');
    expect(replySubject('forward', 'Orçamento')).toBe('ENC: Orçamento');
  });
});

describe('appsErrors', () => {
  const t = (key, params) =>
    params ? `${key}:${JSON.stringify(params)}` : key;
  const fail = (error, message) => ({ response: { data: { error, message } } });

  it('translates the apps codes and falls back to the Teams texts', () => {
    expect(errorText(fail('scope_outdated', 'scope_outdated'), t)).toBe(
      'OUTSIDER_APPS.ERRORS.SCOPE_OUTDATED'
    );
    expect(errorText(fail('busy', 'too many'), t)).toBe(
      'OUTSIDER_APPS.ERRORS.BUSY'
    );
    expect(errorText(fail('empty', 'empty'), t)).toBe(
      'OUTSIDER_TEAMS_AREA.ERRORS.EMPTY:{"name":""}'
    );
    expect(errorText({}, t)).toBe('OUTSIDER_TEAMS_AREA.ERRORS.GENERIC');
  });
});
