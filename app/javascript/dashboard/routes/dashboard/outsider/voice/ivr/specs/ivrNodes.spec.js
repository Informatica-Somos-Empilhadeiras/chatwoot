import { makeNode, portsOf, warningsOf, copyNode } from '../ivrNodes';

const t = key => key.split('.').pop();

describe('ivrNodes', () => {
  it('gives the menu one exit per key plus the invalid exit', () => {
    const menu = makeNode('menu', 0, 0);
    menu.data.options[0].label = 'Vendas';
    expect(portsOf(menu, t).map(port => port.label)).toEqual([
      '1 · Vendas',
      '2 · —',
      'invalid',
    ]);
    expect(portsOf(makeNode('caller', 0, 0), t).map(port => port.id)).toEqual([
      'deal',
      'contact',
      'unknown',
    ]);
  });

  it('warns about what is missing in a block', () => {
    const say = makeNode('say', 0, 0);
    expect(warningsOf(say, [], t)).toEqual(['EMPTY_PROMPT', 'NOT_CONNECTED']);

    say.data.prompt.audio_id = 12;
    const edges = [{ from: say.id, port: 'next', to: 'x' }];
    expect(warningsOf(say, edges, t)).toEqual([]);

    const transfer = makeNode('transfer', 0, 0);
    transfer.data.target = 'number';
    transfer.data.number = '6299';
    expect(warningsOf(transfer, [], t)).toEqual(['NO_NUMBER']);
  });

  it('gives a copied menu new option ids', () => {
    const menu = makeNode('menu', 0, 0);
    const copy = copyNode(menu, 40, 40);
    expect(copy.id).not.toBe(menu.id);
    expect(copy.data.options[0].id).not.toBe(menu.data.options[0].id);
    expect(copy.data.options[0].digit).toBe('1');
  });
});
