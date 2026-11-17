import {
  isMediaOnly,
  joinsAlbum,
  mediaOf,
  viewerItems,
} from '../teamsMedia';

const photo = index => ({
  index,
  kind: 'image',
  thumb_url: `/t/${index}`,
  full_url: `/f/${index}`,
});
const msg = (id, extra = {}) => ({
  id,
  status: 'sent',
  sender_name: 'Ana',
  mine: false,
  content: '',
  sent_at: `2026-11-17T10:0${id}:00Z`,
  attachments: [photo(0)],
  ...extra,
});

describe('teamsMedia', () => {
  it('keeps only photos and videos with an address', () => {
    const message = msg(1, {
      attachments: [photo(0), { index: 1, kind: 'file', name: 'a.pdf' }],
    });
    expect(mediaOf(message).map(item => item.index)).toEqual([0]);
    expect(isMediaOnly(message)).toBe(false);
  });

  it('joins media-only messages from the same person within 2 minutes', () => {
    expect(joinsAlbum(msg(1), msg(2))).toBe(true);
    expect(joinsAlbum(msg(1), msg(5))).toBe(false);
    expect(joinsAlbum(msg(1), msg(2, { sender_name: 'Bia' }))).toBe(false);
    expect(joinsAlbum(msg(1), msg(2, { content: 'oi' }))).toBe(false);
  });

  it('lists the viewer items oldest first with the message time', () => {
    const items = viewerItems([
      msg(1),
      msg(2, { attachments: [photo(0), photo(1)] }),
      msg(3, { deleted: true }),
    ]);
    expect(items.map(item => item.id)).toEqual(['t-1-0', 't-2-0', 't-2-1']);
    expect(items[0].data_url).toBe('/f/0');
    expect(items[1].created_at).toBeGreaterThan(items[0].created_at);
  });
});
