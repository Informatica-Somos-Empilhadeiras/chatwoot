// OUTSIDER: estado e região de cada DDD do Brasil, para escolher quem vê um status.
// O servidor manda a área de cada contato: o DDD ('62'), 'foreign' ou 'unknown'.

export const FOREIGN = 'foreign';
export const UNKNOWN = 'unknown';

export const REGIONS = [
  { key: 'N', states: ['AC', 'AP', 'AM', 'PA', 'RO', 'RR', 'TO'] },
  { key: 'NE', states: ['AL', 'BA', 'CE', 'MA', 'PB', 'PE', 'PI', 'RN', 'SE'] },
  { key: 'CO', states: ['DF', 'GO', 'MT', 'MS'] },
  { key: 'SE', states: ['ES', 'MG', 'RJ', 'SP'] },
  { key: 'S', states: ['PR', 'RS', 'SC'] },
];

export const STATE_NAMES = {
  AC: 'Acre',
  AL: 'Alagoas',
  AP: 'Amapá',
  AM: 'Amazonas',
  BA: 'Bahia',
  CE: 'Ceará',
  DF: 'Distrito Federal',
  ES: 'Espírito Santo',
  GO: 'Goiás',
  MA: 'Maranhão',
  MT: 'Mato Grosso',
  MS: 'Mato Grosso do Sul',
  MG: 'Minas Gerais',
  PA: 'Pará',
  PB: 'Paraíba',
  PR: 'Paraná',
  PE: 'Pernambuco',
  PI: 'Piauí',
  RJ: 'Rio de Janeiro',
  RN: 'Rio Grande do Norte',
  RS: 'Rio Grande do Sul',
  RO: 'Rondônia',
  RR: 'Roraima',
  SC: 'Santa Catarina',
  SP: 'São Paulo',
  SE: 'Sergipe',
  TO: 'Tocantins',
};

// DDD => [estado, cidade principal da área]. O 61 cobre o DF e o entorno em Goiás.
export const DDDS = {
  11: ['SP', 'São Paulo'],
  12: ['SP', 'São José dos Campos'],
  13: ['SP', 'Santos'],
  14: ['SP', 'Bauru'],
  15: ['SP', 'Sorocaba'],
  16: ['SP', 'Ribeirão Preto'],
  17: ['SP', 'São José do Rio Preto'],
  18: ['SP', 'Presidente Prudente'],
  19: ['SP', 'Campinas'],
  21: ['RJ', 'Rio de Janeiro'],
  22: ['RJ', 'Campos dos Goytacazes'],
  24: ['RJ', 'Volta Redonda'],
  27: ['ES', 'Vitória'],
  28: ['ES', 'Cachoeiro de Itapemirim'],
  31: ['MG', 'Belo Horizonte'],
  32: ['MG', 'Juiz de Fora'],
  33: ['MG', 'Governador Valadares'],
  34: ['MG', 'Uberlândia'],
  35: ['MG', 'Poços de Caldas'],
  37: ['MG', 'Divinópolis'],
  38: ['MG', 'Montes Claros'],
  41: ['PR', 'Curitiba'],
  42: ['PR', 'Ponta Grossa'],
  43: ['PR', 'Londrina'],
  44: ['PR', 'Maringá'],
  45: ['PR', 'Foz do Iguaçu'],
  46: ['PR', 'Francisco Beltrão'],
  47: ['SC', 'Joinville'],
  48: ['SC', 'Florianópolis'],
  49: ['SC', 'Chapecó'],
  51: ['RS', 'Porto Alegre'],
  53: ['RS', 'Pelotas'],
  54: ['RS', 'Caxias do Sul'],
  55: ['RS', 'Santa Maria'],
  61: ['DF', 'Brasília e entorno'],
  62: ['GO', 'Goiânia'],
  63: ['TO', 'Palmas'],
  64: ['GO', 'Rio Verde'],
  65: ['MT', 'Cuiabá'],
  66: ['MT', 'Rondonópolis'],
  67: ['MS', 'Campo Grande'],
  68: ['AC', 'Rio Branco'],
  69: ['RO', 'Porto Velho'],
  71: ['BA', 'Salvador'],
  73: ['BA', 'Ilhéus'],
  74: ['BA', 'Juazeiro'],
  75: ['BA', 'Feira de Santana'],
  77: ['BA', 'Vitória da Conquista'],
  79: ['SE', 'Aracaju'],
  81: ['PE', 'Recife'],
  82: ['AL', 'Maceió'],
  83: ['PB', 'João Pessoa'],
  84: ['RN', 'Natal'],
  85: ['CE', 'Fortaleza'],
  86: ['PI', 'Teresina'],
  87: ['PE', 'Petrolina'],
  88: ['CE', 'Juazeiro do Norte'],
  89: ['PI', 'Picos'],
  91: ['PA', 'Belém'],
  92: ['AM', 'Manaus'],
  93: ['PA', 'Santarém'],
  94: ['PA', 'Marabá'],
  95: ['RR', 'Boa Vista'],
  96: ['AP', 'Macapá'],
  97: ['AM', 'Coari'],
  98: ['MA', 'São Luís'],
  99: ['MA', 'Imperatriz'],
};

export const stateOfArea = area => DDDS[area]?.[0] || null;

const sum = (counts, areas) =>
  areas.reduce((total, area) => total + (counts[area] || 0), 0);

// Árvore região > estado > DDD só com o que tem contato, cada nó com as áreas que cobre.
// DDDs que não existem (número digitado errado) entram em "Outros", junto com os de fora do Brasil.
export const buildAreaTree = counts => {
  const regions = REGIONS.map(region => {
    const states = region.states
      .map(uf => {
        const ddds = Object.keys(DDDS)
          .filter(ddd => DDDS[ddd][0] === uf && counts[ddd])
          .map(ddd => ({
            key: ddd,
            ddd,
            city: DDDS[ddd][1],
            areas: [ddd],
            count: counts[ddd],
          }));
        const areas = ddds.map(item => item.key);
        return { key: uf, uf, name: STATE_NAMES[uf], ddds, areas };
      })
      .filter(state => state.areas.length)
      .map(state => ({ ...state, count: sum(counts, state.areas) }));
    const areas = states.flatMap(state => state.areas);
    return { key: region.key, states, areas, count: sum(counts, areas) };
  }).filter(region => region.count);

  const others = Object.keys(counts).filter(
    area => area !== UNKNOWN && !DDDS[area]
  );
  return {
    regions,
    others: { areas: others, count: sum(counts, others) },
    unknown: { areas: [UNKNOWN], count: counts[UNKNOWN] || 0 },
  };
};

export const areaLabel = area => {
  if (DDDS[area]) return `${area} · ${DDDS[area][0]}`;
  return null;
};
