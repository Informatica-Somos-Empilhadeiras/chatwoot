// OUTSIDER: lê a planilha no próprio navegador (Excel .xlsx ou CSV), sem biblioteca nova: o .xlsx é um zip
// com XML (descompactado pelo DecompressionStream do navegador) e o CSV pode vir com ; , ou tab, em UTF-8 ou
// no formato do Excel brasileiro (Windows-1252). Devolve as colunas (primeira linha com texto) e as linhas
// como texto, prontas para mandar ao servidor em pedaços. Datas do Excel viram dd/mm/aaaa.

export const MAX_ROWS = 100000;
export const MAX_COLUMNS = 60;

export class SpreadsheetError extends Error {
  constructor(code, detail = {}) {
    super(code);
    this.code = code;
    this.detail = detail;
  }
}

// ---------- zip ----------
const utf8 = new TextDecoder('utf-8');

const readZip = buffer => {
  const view = new DataView(buffer);
  let end = -1;
  const stop = Math.max(0, buffer.byteLength - 65557);
  for (let index = buffer.byteLength - 22; index >= stop; index -= 1) {
    if (view.getUint32(index, true) === 0x06054b50) {
      end = index;
      break;
    }
  }
  if (end < 0) throw new SpreadsheetError('not_xlsx');
  const count = view.getUint16(end + 10, true);
  let offset = view.getUint32(end + 16, true);
  const entries = {};
  for (let item = 0; item < count; item += 1) {
    if (view.getUint32(offset, true) !== 0x02014b50) {
      throw new SpreadsheetError('not_xlsx');
    }
    const nameLength = view.getUint16(offset + 28, true);
    const name = utf8.decode(new Uint8Array(buffer, offset + 46, nameLength));
    entries[name] = {
      method: view.getUint16(offset + 10, true),
      size: view.getUint32(offset + 20, true),
      local: view.getUint32(offset + 42, true),
    };
    offset +=
      46 +
      nameLength +
      view.getUint16(offset + 30, true) +
      view.getUint16(offset + 32, true);
  }
  return entries;
};

const readEntry = async (buffer, entries, name) => {
  const entry = entries[name];
  if (!entry) return null;
  const view = new DataView(buffer);
  const start =
    entry.local +
    30 +
    view.getUint16(entry.local + 26, true) +
    view.getUint16(entry.local + 28, true);
  const bytes = new Uint8Array(buffer, start, entry.size);
  if (entry.method === 0) return utf8.decode(bytes);
  if (entry.method !== 8 || typeof DecompressionStream === 'undefined') {
    throw new SpreadsheetError('unsupported_xlsx');
  }
  const stream = new Blob([bytes])
    .stream()
    .pipeThrough(new DecompressionStream('deflate-raw'));
  return new Response(stream).text();
};

// ---------- XML (expressões simples: rápidas e leves mesmo com 100 mil linhas) ----------
const ENTITIES = { lt: '<', gt: '>', amp: '&', quot: '"', apos: "'" };
const decodeXml = text =>
  text
    .replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (match, code) => {
      if (code[0] === '#') {
        const number =
          code[1].toLowerCase() === 'x'
            ? parseInt(code.slice(2), 16)
            : parseInt(code.slice(1), 10);
        return Number.isFinite(number) ? String.fromCodePoint(number) : match;
      }
      return ENTITIES[code] ?? match;
    })
    // o Excel escreve caracteres de controle como _x000D_
    .replace(/_x([0-9a-f]{4})_/gi, (_, hex) =>
      String.fromCharCode(parseInt(hex, 16))
    );

const attr = (attrs, name) =>
  attrs.match(new RegExp(`(?:^|\\s)(?:\\w+:)?${name}="([^"]*)"`))?.[1];

const TEXT = /<(?:\w+:)?t(?:\s[^>]*)?>([\s\S]*?)<\/(?:\w+:)?t>/g;
const textOf = xml =>
  [
    ...xml
      .replace(/<(?:\w+:)?rPh\b[\s\S]*?<\/(?:\w+:)?rPh>/g, '')
      .matchAll(TEXT),
  ]
    .map(match => decodeXml(match[1]))
    .join('');

const sharedStrings = xml =>
  xml
    ? [
        ...xml.matchAll(
          /<(?:\w+:)?si(?:\s[^>]*)?(?:\/>|>([\s\S]*?)<\/(?:\w+:)?si>)/g
        ),
      ].map(match => textOf(match[1] || ''))
    : [];

// formatos de número que são data ou hora (os fixos do Excel e os criados na planilha)
const DATE_IDS = new Set([
  14, 15, 16, 17, 18, 19, 20, 21, 22, 27, 30, 36, 45, 46, 47, 50, 57,
]);
const dateStyles = xml => {
  if (!xml) return [];
  const custom = {};
  [...xml.matchAll(/<(?:\w+:)?numFmt\s([^>]*?)\/?>/g)].forEach(([, attrs]) => {
    const code = decodeXml(attr(attrs, 'formatCode') || '')
      .replace(/"[^"]*"/g, '')
      .replace(/\[[^\]]*\]/g, '')
      .replace(/\\./g, '');
    custom[attr(attrs, 'numFmtId')] = /[dmyhs]/i.test(code);
  });
  const block = xml.match(
    /<(?:\w+:)?cellXfs\b[^>]*>([\s\S]*?)<\/(?:\w+:)?cellXfs>/
  )?.[1];
  if (!block) return [];
  return [...block.matchAll(/<(?:\w+:)?xf\b([^>]*?)\/?>/g)].map(([, attrs]) => {
    const id = attr(attrs, 'numFmtId') || '0';
    return DATE_IDS.has(Number(id)) || !!custom[id];
  });
};

const pad = number => String(number).padStart(2, '0');
const excelDate = (serial, date1904) => {
  const days = serial + (date1904 ? 1462 : 0);
  const date = new Date(Math.round((days - 25569) * 86400) * 1000);
  if (Number.isNaN(date.getTime())) return String(serial);
  const day = `${pad(date.getUTCDate())}/${pad(date.getUTCMonth() + 1)}/${date.getUTCFullYear()}`;
  const time = `${pad(date.getUTCHours())}:${pad(date.getUTCMinutes())}`;
  if (Number.isInteger(serial)) return day;
  return serial < 1 ? time : `${day} ${time}`;
};

const plainNumber = text => {
  if (!String(text).trim()) return '';
  const number = Number(text);
  if (!Number.isFinite(number)) return text;
  return String(parseFloat(number.toPrecision(15)));
};

const columnIndex = ref => {
  const letters = String(ref || '').match(/^[A-Z]+/i)?.[0];
  if (!letters) return -1;
  return (
    [...letters.toUpperCase()].reduce(
      (sum, letter) => sum * 26 + letter.charCodeAt(0) - 64,
      0
    ) - 1
  );
};

const ROW = /<(?:\w+:)?row\b([^>]*?)(?:\/>|>([\s\S]*?)<\/(?:\w+:)?row>)/g;
const CELL = /<(?:\w+:)?c\b([^>]*?)(?:\/>|>([\s\S]*?)<\/(?:\w+:)?c>)/g;
const VALUE = /<(?:\w+:)?v(?:\s[^>]*)?>([\s\S]*?)<\/(?:\w+:)?v>/;

const cellText = (attrs, body, ctx) => {
  const type = attr(attrs, 't') || 'n';
  if (type === 'inlineStr') return textOf(body);
  const raw = body.match(VALUE)?.[1];
  if (raw === undefined || raw === '') return '';
  const value = decodeXml(raw);
  switch (type) {
    case 's':
      return ctx.strings[Number(value)] ?? '';
    case 'b':
      return value === '1' ? 'VERDADEIRO' : 'FALSO';
    case 'str':
    case 'e':
      return value;
    default: {
      const style = Number(attr(attrs, 's') || 0);
      const number = Number(value);
      if (ctx.dates[style] && Number.isFinite(number)) {
        return excelDate(number, ctx.date1904);
      }
      return plainNumber(value);
    }
  }
};

const sheetRows = (xml, ctx) => {
  const data = xml.match(
    /<(?:\w+:)?sheetData\b[^>]*>([\s\S]*?)<\/(?:\w+:)?sheetData>/
  )?.[1];
  if (!data) return [];
  const rows = [];
  [...data.matchAll(ROW)].forEach(([, rowAttrs, body = '']) => {
    const index = Number(attr(rowAttrs, 'r')) - 1;
    const row = [];
    let next = 0;
    [...body.matchAll(CELL)].forEach(([, attrs, cell = '']) => {
      const column = columnIndex(attr(attrs, 'r'));
      const position = column >= 0 ? column : next;
      next = position + 1;
      if (position < MAX_COLUMNS * 4)
        row[position] = cellText(attrs, cell, ctx);
    });
    if (Number.isFinite(index) && index >= rows.length) rows[index] = row;
    else rows.push(row);
    if (rows.length > MAX_ROWS + 50) {
      throw new SpreadsheetError('too_many_rows', { max: MAX_ROWS });
    }
  });
  return rows;
};

const readXlsx = async buffer => {
  const entries = readZip(buffer);
  const workbook = await readEntry(buffer, entries, 'xl/workbook.xml');
  if (!workbook) throw new SpreadsheetError('not_xlsx');
  const rels =
    (await readEntry(buffer, entries, 'xl/_rels/workbook.xml.rels')) || '';
  const targets = Object.fromEntries(
    [...rels.matchAll(/<(?:\w+:)?Relationship\s([^>]*?)\/?>/g)].map(
      ([, attrs]) => {
        const target = attr(attrs, 'Target') || '';
        return [
          attr(attrs, 'Id'),
          target.startsWith('/')
            ? target.slice(1)
            : `xl/${target.replace(/^\.\//, '')}`,
        ];
      }
    )
  );
  const sheets = [...workbook.matchAll(/<(?:\w+:)?sheet\s([^>]*?)\/?>/g)]
    .map(([, attrs]) => ({
      name: decodeXml(attr(attrs, 'name') || ''),
      path: targets[attr(attrs, 'id')],
      hidden: !!attr(attrs, 'state') && attr(attrs, 'state') !== 'visible',
    }))
    .filter(sheet => sheet.path && entries[sheet.path]);
  const visible = sheets.filter(sheet => !sheet.hidden);
  const list = visible.length ? visible : sheets;
  if (!list.length) throw new SpreadsheetError('empty');
  let shared = null;
  const context = async () => {
    if (!shared) {
      shared = {
        strings: sharedStrings(
          await readEntry(buffer, entries, 'xl/sharedStrings.xml')
        ),
        dates: dateStyles(await readEntry(buffer, entries, 'xl/styles.xml')),
        date1904: /date1904="(1|true)"/.test(workbook),
      };
    }
    return shared;
  };
  return list.map(sheet => ({
    name: sheet.name,
    read: async () =>
      sheetRows(await readEntry(buffer, entries, sheet.path), await context()),
  }));
};

// ---------- CSV ----------
const decodeText = buffer => {
  let text;
  try {
    text = new TextDecoder('utf-8', { fatal: true }).decode(buffer);
  } catch {
    text = new TextDecoder('windows-1252').decode(buffer);
  }
  return text.replace(/^\uFEFF/, '');
};

const detectDelimiter = text => {
  const counts = { ';': 0, ',': 0, '\t': 0 };
  let quoted = false;
  for (let index = 0; index < Math.min(text.length, 20000); index += 1) {
    const char = text[index];
    if (char === '"') quoted = !quoted;
    else if (!quoted && (char === '\n' || char === '\r')) break;
    else if (!quoted && char in counts) counts[char] += 1;
  }
  const [best, count] = Object.entries(counts).sort((a, b) => b[1] - a[1])[0];
  return count > 0 ? best : ',';
};

export const parseCsv = (text, delimiter = detectDelimiter(text)) => {
  const rows = [];
  let row = [];
  let cell = '';
  let quoted = false;
  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];
    if (quoted) {
      if (char === '"') {
        if (text[index + 1] === '"') {
          cell += '"';
          index += 1;
        } else {
          quoted = false;
        }
      } else {
        cell += char;
      }
    } else if (char === '"' && cell === '') {
      quoted = true;
    } else if (char === delimiter) {
      row.push(cell);
      cell = '';
    } else if (char === '\n' || char === '\r') {
      if (char === '\r' && text[index + 1] === '\n') index += 1;
      row.push(cell);
      rows.push(row);
      row = [];
      cell = '';
      if (rows.length > MAX_ROWS + 50) {
        throw new SpreadsheetError('too_many_rows', { max: MAX_ROWS });
      }
    } else {
      cell += char;
    }
  }
  if (cell !== '' || row.length) {
    row.push(cell);
    rows.push(row);
  }
  return rows;
};

// ---------- tabela: cabeçalho na primeira linha com texto ----------
const filled = value => String(value ?? '').trim() !== '';

export const toTable = rawRows => {
  // Array.from também passa pelas linhas vazias que o Excel pula (buracos na lista)
  const rows = Array.from(rawRows, row =>
    Array.from(row || [], value => String(value ?? '').trim())
  );
  const headerIndex = rows.findIndex(row => row.some(filled));
  if (headerIndex < 0) throw new SpreadsheetError('empty');
  const body = rows.slice(headerIndex + 1).filter(row => row.some(filled));
  if (!body.length) throw new SpreadsheetError('no_rows');
  if (body.length > MAX_ROWS) {
    throw new SpreadsheetError('too_many_rows', {
      max: MAX_ROWS,
      count: body.length,
    });
  }
  const lastFilled = row => {
    for (let index = row.length - 1; index >= 0; index -= 1) {
      if (filled(row[index])) return index;
    }
    return -1;
  };
  const width =
    Math.max(
      lastFilled(rows[headerIndex]),
      ...body.slice(0, 2000).map(lastFilled)
    ) + 1;
  if (width > MAX_COLUMNS) {
    throw new SpreadsheetError('too_many_columns', {
      max: MAX_COLUMNS,
      count: width,
    });
  }
  const columns = Array.from({ length: width }, (_, index) => {
    const label = rows[headerIndex][index] || '';
    return label || `Coluna ${index + 1}`;
  });
  return {
    columns,
    rows: body.map(row =>
      Array.from({ length: width }, (_, index) => row[index] || '')
    ),
  };
};

// [{ name, read: async () => linhas }] de um arquivo escolhido
export const openSpreadsheet = async file => {
  const name = String(file?.name || '').toLowerCase();
  const buffer = await file.arrayBuffer();
  if (/\.(csv|tsv|txt)$/.test(name)) {
    return [
      { name: file.name, read: async () => parseCsv(decodeText(buffer)) },
    ];
  }
  if (/\.(xlsx|xlsm)$/.test(name)) return readXlsx(buffer);
  if (/\.(xls|ods|numbers)$/.test(name))
    throw new SpreadsheetError('old_format');
  throw new SpreadsheetError('unknown_format');
};
