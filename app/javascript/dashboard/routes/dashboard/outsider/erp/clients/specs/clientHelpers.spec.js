import {
  isValidDocument,
  maskDocument,
  maskCep,
  formatPhone,
  fromContact,
} from '../clientHelpers';

describe('clientHelpers', () => {
  it('checks CPF and CNPJ digits, including the alphanumeric CNPJ', () => {
    expect(isValidDocument('529.982.247-25')).toBe(true);
    expect(isValidDocument('111.111.111-11')).toBe(false);
    expect(isValidDocument('11.222.333/0001-81')).toBe(true);
    expect(isValidDocument('11.222.333/0001-80')).toBe(false);
    expect(isValidDocument('12.ABC.345/01DE-35')).toBe(true);
  });

  it('masks while typing', () => {
    expect(maskDocument('11222333000181', 'J')).toBe('11.222.333/0001-81');
    expect(maskDocument('1122', 'J')).toBe('11.22');
    expect(maskDocument('52998224725', 'F')).toBe('529.982.247-25');
    expect(maskCep('74000000')).toBe('74000-000');
    expect(formatPhone('+5562999990000')).toBe('(62) 99999-0000');
  });

  it('starts a company registration from a contact with a company name', () => {
    const form = fromContact({
      name: 'Gilmar',
      phone_number: '+5562999990000',
      email: 'gilmar@acme.com',
      additional_attributes: { company_name: 'ACME Ltda', city: 'Goiânia' },
    });
    expect(form).toMatchObject({
      person: 'J',
      nome: 'ACME Ltda',
      celular: '(62) 99999-0000',
      contato_nome: 'Gilmar',
      cidade: 'Goiânia',
    });
    expect(
      fromContact({ name: 'Ana', phone_number: '+556233334444' })
    ).toMatchObject({ person: 'F', nome: 'Ana', telefone: '(62) 3333-4444' });
  });
});
