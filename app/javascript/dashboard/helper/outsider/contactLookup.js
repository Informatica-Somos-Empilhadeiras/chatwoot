// OUTSIDER: acha o contato do Chatwoot de um número de telefone (cartão de contato do WhatsApp).
// Busca pelos 8 últimos dígitos e compara sem o 9º dígito dos celulares do Brasil, porque o mesmo
// número aparece com e sem ele. O resultado fica guardado por número enquanto a página está aberta.
import ContactAPI from 'dashboard/api/contacts';

const cache = new Map();

export const comparableNumber = phone => {
  const digits = String(phone || '').replace(/\D/g, '');
  if (digits.length === 13 && digits.startsWith('55') && digits[4] === '9') {
    return digits.slice(0, 4) + digits.slice(5);
  }
  return digits;
};

const search = async digits => {
  const { data } = await ContactAPI.search(digits.slice(-8));
  const key = comparableNumber(digits);
  return (
    (data.payload || []).find(
      contact =>
        contact.phone_number && comparableNumber(contact.phone_number) === key
    ) || null
  );
};

export const findContactByPhone = phone => {
  const digits = String(phone || '').replace(/\D/g, '');
  if (digits.length < 8) return Promise.resolve(null);
  const key = comparableNumber(digits);
  if (!cache.has(key)) {
    cache.set(
      key,
      search(digits).catch(() => {
        cache.delete(key);
        return null;
      })
    );
  }
  return cache.get(key);
};

export const rememberContact = contact => {
  if (contact?.phone_number) {
    cache.set(comparableNumber(contact.phone_number), Promise.resolve(contact));
  }
};
