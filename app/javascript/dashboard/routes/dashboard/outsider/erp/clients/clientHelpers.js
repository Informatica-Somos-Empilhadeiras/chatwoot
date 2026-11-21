// OUTSIDER: ajudas do "Cadastrar cliente no ERP" (ErpClientDialog): CPF/CNPJ (o CNPJ pode ser o alfanumérico da
// Receita), máscaras e o preenchimento a partir do contato do Chatwoot. O servidor confere tudo de novo
// (Outsider::Erp::ClientForm); aqui é só para avisar na hora.

export const UFS = [
  'AC',
  'AL',
  'AP',
  'AM',
  'BA',
  'CE',
  'DF',
  'ES',
  'GO',
  'MA',
  'MT',
  'MS',
  'MG',
  'PA',
  'PB',
  'PR',
  'PE',
  'PI',
  'RJ',
  'RN',
  'RS',
  'RO',
  'RR',
  'SC',
  'SP',
  'SE',
  'TO',
];

export const cleanDocument = value =>
  String(value || '')
    .toUpperCase()
    .replace(/[^0-9A-Z]/g, '');

const checkDigit = (numbers, weights) => {
  const rest =
    numbers.reduce((sum, number, index) => sum + number * weights[index], 0) %
    11;
  return rest < 2 ? 0 : 11 - rest;
};

const isCpf = value => {
  if (!/^\d{11}$/.test(value) || new Set(value).size === 1) return false;
  const digits = [...value].map(Number);
  return [9, 10].every(
    size =>
      checkDigit(
        digits.slice(0, size),
        Array.from({ length: size }, (_, index) => size + 1 - index)
      ) === digits[size]
  );
};

// cada caractere vale o código ASCII menos 48 (0-9 continuam 0-9; A = 17)
const isCnpj = value => {
  if (!/^[0-9A-Z]{12}\d{2}$/.test(value) || new Set(value).size === 1)
    return false;
  const numbers = [...value].map(char => char.charCodeAt(0) - 48);
  const weights = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
  return (
    checkDigit(numbers.slice(0, 12), weights) === numbers[12] &&
    checkDigit(numbers.slice(0, 13), [6, ...weights]) === numbers[13]
  );
};

export const isValidDocument = value => {
  const clean = cleanDocument(value);
  return clean.length === 11 ? isCpf(clean) : isCnpj(clean);
};

// "12.345.678/0001-90" ou "123.456.789-01" conforme vai digitando
export const maskDocument = (value, person) => {
  const clean = cleanDocument(value).slice(0, person === 'F' ? 11 : 14);
  const parts =
    person === 'F'
      ? [
          [0, 3, ''],
          [3, 6, '.'],
          [6, 9, '.'],
          [9, 11, '-'],
        ]
      : [
          [0, 2, ''],
          [2, 5, '.'],
          [5, 8, '.'],
          [8, 12, '/'],
          [12, 14, '-'],
        ];
  return parts
    .map(([start, end, separator]) =>
      clean.length > start ? separator + clean.slice(start, end) : ''
    )
    .join('');
};

export const maskCep = value => {
  const digits = String(value || '')
    .replace(/\D/g, '')
    .slice(0, 8);
  return digits.length > 5
    ? `${digits.slice(0, 5)}-${digits.slice(5)}`
    : digits;
};

// telefone do contato (+5562999990000) no jeito do Brasil: "(62) 99999-0000"
export const formatPhone = value => {
  let digits = String(value || '').replace(/\D/g, '');
  if (digits.startsWith('55') && digits.length >= 12) digits = digits.slice(2);
  if (digits.length === 11)
    return `(${digits.slice(0, 2)}) ${digits.slice(2, 7)}-${digits.slice(7)}`;
  if (digits.length === 10)
    return `(${digits.slice(0, 2)}) ${digits.slice(2, 6)}-${digits.slice(6)}`;
  return String(value || '');
};

const isMobile = phone => /^\(\d{2}\) 9\d{4}-\d{4}$/.test(phone);

export const EMPTY_CLIENT = () => ({
  person: 'J',
  documento: '',
  nome: '',
  apelido: '',
  rg_ie: '',
  telefone: '',
  celular: '',
  email: '',
  cep: '',
  endereco: '',
  numero: '',
  bairro: '',
  cidade: '',
  uf: '',
  referencia: '',
  vendedor: 0,
  contato_nome: '',
  contato_telefone: '',
  contato_email: '',
  observacoes: '',
  copiar_endereco: true,
});

// o contato do Chatwoot vira o começo do cadastro: com empresa, pessoa jurídica (a pessoa entra como contato);
// sem empresa, pessoa física com o nome dele
export const fromContact = contact => {
  const form = EMPTY_CLIENT();
  if (!contact) return form;
  const company = String(
    contact.additional_attributes?.company_name || ''
  ).trim();
  const phone = formatPhone(contact.phone_number);
  const email = String(contact.email || '').trim();
  const address = contact.additional_attributes || {};
  Object.assign(form, {
    person: company ? 'J' : 'F',
    nome: company || String(contact.name || '').trim(),
    [isMobile(phone) ? 'celular' : 'telefone']: phone,
    email,
    cidade: String(address.city || '').trim(),
  });
  if (company) {
    Object.assign(form, {
      contato_nome: String(contact.name || '').trim(),
      contato_telefone: phone,
      contato_email: email,
    });
  }
  return form;
};
