import {
  checklistSections,
  chosenFields,
  columnsFor,
  contrastColor,
  fillPlaceholders,
  newBlock,
  optionVisible,
  photoSource,
  readingOf,
} from '../printsHelpers';

const catalog = {
  kind: 'os',
  groups: [
    {
      key: 'os',
      fields: [
        { key: 'numero', label: 'Número', on: true },
        { key: 'tecnico', label: 'Técnico', on: true },
      ],
    },
    { key: 'cliente', fields: [{ key: 'nome', label: 'Cliente', on: true }] },
  ],
  tables: [
    {
      key: 'produtos',
      columns: [{ key: 'codigo', label: 'Código', on: true, align: 'left' }],
    },
  ],
  texts: [{ key: 'avaliacao' }, { key: 'defeitos' }],
  blocks: [
    { type: 'fields', defaults: { type: 'fields', group: 'os', columns: 2 } },
    { type: 'checklist', defaults: { type: 'checklist', photos: 'with' } },
  ],
};

describe('printsHelpers', () => {
  it('fills known placeholders and keeps unknown ones', () => {
    expect(
      fillPlaceholders('OS {numero} - {cliente} {outro}', {
        numero: '966',
        cliente: 'GDS',
      })
    ).toBe('OS 966 - GDS {outro}');
  });

  it('creates a block with the server defaults and the next free group', () => {
    const first = newBlock(catalog, 'fields', []);
    expect(first).toMatchObject({ type: 'fields', group: 'os', columns: 2 });
    expect(first.id).toMatch(/^b[0-9a-f]{8}$/);
    expect(newBlock(catalog, 'fields', [first]).group).toBe('cliente');
  });

  it('keeps the field order and switches of the template', () => {
    const content = {
      fields: {
        os: [
          { key: 'tecnico', on: true },
          { key: 'numero', on: false },
        ],
      },
    };
    expect(chosenFields(content, catalog, 'os').map(f => f.key)).toEqual([
      'tecnico',
    ]);
    expect(chosenFields({}, catalog, 'produtos')[0].label).toBe('Código');
  });

  it('arranges photos like the PDF', () => {
    const auto = { arrangement: 'auto' };
    expect([1, 2, 3, 4, 5, 9].map(n => columnsFor(auto, n))).toEqual([
      1, 2, 3, 2, 3, 3,
    ]);
    expect(columnsFor({ arrangement: 'grid2' }, 1)).toBe(2);
  });

  it('shows only the settings that apply', () => {
    const withPhotos = { type: 'checklist', photos: 'with', answers: 'grid' };
    const without = { ...withPhotos, photos: 'without' };
    expect(optionVisible(withPhotos, 'title_style')).toBe(true);
    expect(optionVisible(withPhotos, 'answers')).toBe(false);
    expect(optionVisible(without, 'title_style')).toBe(false);
    expect(optionVisible(without, 'grid_columns')).toBe(true);
    expect(optionVisible(without, 'show_reading')).toBe(false);
    expect(optionVisible({ type: 'header', logo: 'erp' }, 'image_id')).toBe(
      false
    );
  });

  it('filters checklist sections ignoring accents and case', () => {
    const values = {
      checklist: [{ nome: 'Inspeção visual' }, { nome: 'Testes' }],
    };
    expect(
      checklistSections(values, { sections: ['INSPECAO VISUAL'] })
    ).toEqual([{ nome: 'Inspeção visual' }]);
    expect(checklistSections(values, { sections: [] })).toHaveLength(2);
  });

  it('reads answers and photo sources', () => {
    expect(readingOf({ chegada: 'OK', saida: 'OK' })).toBe('OK');
    expect(readingOf({ chegada: 'Ruim', saida: 'OK' })).toBe(
      'Chegada: Ruim  ·  Saída: OK'
    );
    expect(photoSource({ sample: 'amostra-1.jpg' })).toBe(
      '/outsider/erp-prints/amostra-1.jpg'
    );
    expect(photoSource({ ref: '966_1' }, { '966_1': 'blob:x' })).toBe('blob:x');
  });

  it('picks readable text over the primary color', () => {
    const theme = { colors: { primary: '#00663B', text: '#1D2733' } };
    expect(contrastColor(theme, 'primary')).toBe('#FFFFFF');
    const light = { colors: { primary: '#90EB54', text: '#1D2733' } };
    expect(contrastColor(light, 'primary')).toBe('#1D2733');
  });
});
