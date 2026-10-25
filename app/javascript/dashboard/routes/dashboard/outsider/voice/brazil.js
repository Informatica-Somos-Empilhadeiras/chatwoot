// OUTSIDER: estados e DDDs (Entrega 22): o número da linha e o vendedor ficam ligados a um estado; o DDD
// sugere o estado quando alguém digita ou cola um número.
export const STATES =
  'AC AL AP AM BA CE DF ES GO MA MT MS MG PA PB PR PE PI RJ RN RS RO RR SC SP SE TO'.split(
    ' '
  );

const DDD_STATES = {
  SP: [11, 12, 13, 14, 15, 16, 17, 18, 19],
  RJ: [21, 22, 24],
  ES: [27, 28],
  MG: [31, 32, 33, 34, 35, 37, 38],
  PR: [41, 42, 43, 44, 45, 46],
  SC: [47, 48, 49],
  RS: [51, 53, 54, 55],
  DF: [61],
  GO: [62, 64],
  TO: [63],
  MT: [65, 66],
  MS: [67],
  AC: [68],
  RO: [69],
  BA: [71, 73, 74, 75, 77],
  SE: [79],
  PE: [81, 87],
  AL: [82],
  PB: [83],
  RN: [84],
  CE: [85, 88],
  PI: [86, 89],
  PA: [91, 93, 94],
  AM: [92, 97],
  RR: [95],
  AP: [96],
  MA: [98, 99],
};

const BY_DDD = Object.fromEntries(
  Object.entries(DDD_STATES).flatMap(([state, ddds]) =>
    ddds.map(ddd => [ddd, state])
  )
);

// DDD + número (como o Chatwoot guarda: sem 0, sem 55); vazio se não parece número brasileiro
export const nationalNumber = value => {
  let digits = String(value || '').replace(/\D/g, '');
  if ([12, 13].includes(digits.length) && digits.startsWith('55')) {
    digits = digits.slice(2);
  }
  if ([11, 12].includes(digits.length) && digits.startsWith('0')) {
    digits = digits.slice(1);
  }
  return /^[1-9][1-9]\d{8,9}$/.test(digits) ? digits : '';
};

export const stateForNumber = value => {
  const number = nationalNumber(value);
  return number ? BY_DDD[Number(number.slice(0, 2))] || '' : '';
};
