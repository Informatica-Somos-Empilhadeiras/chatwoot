import { isGroupConversation, filterByGroupTab } from '../groupConversations';

const group = { meta: { sender: { identifier: '120363012345678901@g.us' } } };
const person = { meta: { sender: { identifier: null } } };

describe('#isGroupConversation', () => {
  it('detects whatsapp groups by identifier', () => {
    expect(isGroupConversation(group)).toBe(true);
    expect(isGroupConversation(person)).toBe(false);
    expect(isGroupConversation({})).toBe(false);
  });
});

describe('#filterByGroupTab', () => {
  it('shows only groups on the group tab', () => {
    expect(filterByGroupTab(true, 'group', group)).toBe(true);
    expect(filterByGroupTab(true, 'group', person)).toBe(false);
  });

  it('hides groups from mine and unassigned', () => {
    expect(filterByGroupTab(true, 'me', group)).toBe(false);
    expect(filterByGroupTab(true, 'unassigned', group)).toBe(false);
    expect(filterByGroupTab(true, 'me', person)).toBe(true);
  });

  it('keeps groups on all and when no tab is given', () => {
    expect(filterByGroupTab(true, 'all', group)).toBe(true);
    expect(filterByGroupTab(true, undefined, group)).toBe(true);
  });

  it('respects previous filters', () => {
    expect(filterByGroupTab(false, 'group', group)).toBe(false);
  });
});
