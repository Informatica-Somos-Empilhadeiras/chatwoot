import {
  savedChoice,
  choicePatch,
  targetOf,
  visibleOf,
  colorClassOf,
} from '../calendarChoice';

const calendars = [
  { id: 'primary', can_edit: true },
  { id: 'tecnicos', can_edit: true },
  { id: 'feriados', can_edit: false },
];

describe('calendarChoice', () => {
  it('reads the saved choice, defaulting to the main calendar', () => {
    expect(savedChoice({}, 'google')).toEqual({
      visible: ['primary'],
      target: 'primary',
    });
    const ui = {
      outsider_calendars_google: { visible: ['tecnicos'], target: 'tecnicos' },
    };
    expect(savedChoice(ui, 'google').target).toBe('tecnicos');
    expect(savedChoice(ui, 'microsoft').target).toBe('primary');
  });

  it('patches one provider keeping the other fields', () => {
    const ui = {
      outsider_calendars_google: { visible: ['a', 'b'], target: 'a' },
    };
    expect(choicePatch(ui, 'google', { target: 'b' })).toEqual({
      outsider_calendars_google: { visible: ['a', 'b'], target: 'b' },
    });
  });

  it('only marks in an editable calendar that still exists', () => {
    expect(targetOf(calendars, 'tecnicos')).toBe('tecnicos');
    expect(targetOf(calendars, 'feriados')).toBe('primary');
    expect(targetOf(calendars, 'sumiu')).toBe('primary');
    expect(targetOf([], 'tecnicos')).toBe('primary');
  });

  it('shows the calendars that still exist, the main one when none', () => {
    expect(visibleOf(calendars, ['feriados', 'sumiu'])).toEqual(['feriados']);
    expect(visibleOf(calendars, ['sumiu'])).toEqual(['primary']);
  });

  it('colors by position in the list', () => {
    expect(colorClassOf(calendars, 'tecnicos')).toBe('c1');
    expect(colorClassOf(calendars, 'sumiu')).toBe('c0');
  });
});
