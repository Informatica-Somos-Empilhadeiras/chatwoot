import {
  blocksFromPages,
  duplicateBlock,
  freeBlock,
  pagesOf,
} from '../templateDesign';

const block = (key, extra = {}) => ({
  key,
  type: key,
  visible: true,
  new_page: false,
  ...extra,
});

describe('templateDesign pages', () => {
  const blocks = [
    block('date_number'),
    block('customer'),
    block('parties', { visible: false, new_page: true }),
    block('items', { new_page: true }),
    block('conditions'),
    block('bank', { new_page: true }),
  ];

  it('splits the visible blocks into sheets at "new page"', () => {
    expect(pagesOf(blocks).map(page => page.map(item => item.key))).toEqual([
      ['date_number', 'customer'],
      ['items', 'conditions'],
      ['bank'],
    ]);
  });

  it('keeps one empty sheet when nothing is visible', () => {
    expect(pagesOf([block('notes', { visible: false })])).toEqual([[]]);
  });

  it('rebuilds the list after a drag: first block of each sheet opens it, hidden ones go last', () => {
    const [first, second, third] = pagesOf(blocks);
    const moved = [[...first, second[0]], second.slice(1), third];

    const result = blocksFromPages(moved, blocks);

    expect(result.map(item => [item.key, item.new_page])).toEqual([
      ['date_number', false],
      ['customer', false],
      ['items', false],
      ['conditions', true],
      ['bank', true],
      ['parties', true],
    ]);
    expect(result.at(-1).visible).toBe(false);
  });

  it('shows a hidden block dropped from the list once', () => {
    const dropped = { ...blocks[2], visible: true };
    const pages = pagesOf(blocks);
    pages[0].push(dropped);

    const result = blocksFromPages(pages, blocks);

    expect(result.filter(item => item.key === 'parties')).toEqual([
      expect.objectContaining({ visible: true, new_page: false }),
    ]);
  });
});

describe('templateDesign free blocks', () => {
  it('creates free blocks with their own defaults and unique keys', () => {
    const image = freeBlock('image');
    const copy = duplicateBlock(image);

    expect(image).toMatchObject({ type: 'image', width: 40, align: 'center' });
    expect(freeBlock('divider')).toMatchObject({ thickness: 1 });
    expect(freeBlock('spacer')).toMatchObject({ height: 8 });
    expect(copy.key).not.toBe(image.key);
    expect(copy).toMatchObject({ type: 'image', width: 40 });
  });
});
