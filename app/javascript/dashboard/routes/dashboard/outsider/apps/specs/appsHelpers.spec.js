import {
  coversDay,
  dayKey,
  parseLocal,
  rangeOf,
  shift,
} from '../calendar/calendarDates';
import { initialsOf, replySubject } from '../mail/mailHelpers';
import { errorText } from '../appsErrors';
import { textKey } from '../providers';
import { fileIcon } from '../drive/driveHelpers';

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
    expect(replySubject('reply', 'Orçamento', 'google')).toBe('Re: Orçamento');
    expect(replySubject('forward', 'Orçamento', 'google')).toBe(
      'Fwd: Orçamento'
    );
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

  it('uses the Google texts for Google requests', () => {
    const google = code => ({
      ...fail(code, code),
      config: { url: '/api/v1/accounts/1/outsider/apps/google/mail/folders' },
    });
    expect(errorText(google('reconnect'), t)).toBe(
      'OUTSIDER_APPS.GERRORS.RECONNECT'
    );
    expect(errorText(google('already_linked'), t)).toBe(
      'OUTSIDER_APPS.GERRORS.ALREADY_LINKED'
    );
    expect(errorText(google('no_recipient'), t)).toBe(
      'OUTSIDER_APPS.ERRORS.NO_RECIPIENT'
    );
  });
});

describe('providers', () => {
  it('swaps the texts that name the company', () => {
    expect(textKey('google', 'MAIL.DELETE')).toBe(
      'OUTSIDER_APPS.G.MAIL_DELETE'
    );
    expect(textKey('microsoft', 'MAIL.DELETE')).toBe(
      'OUTSIDER_APPS.MAIL.DELETE'
    );
    expect(textKey('google', 'MAIL.MOVE')).toBe('OUTSIDER_APPS.MAIL.MOVE');
  });
});

describe('driveHelpers', () => {
  it('picks the Google Docs icons by type', () => {
    expect(
      fileIcon({
        name: 'Relatório',
        mime: 'application/vnd.google-apps.spreadsheet',
      }).icon
    ).toBe('i-lucide-file-spreadsheet');
    expect(fileIcon({ name: 'foto.png' }).icon).toBe('i-lucide-image');
  });
});
