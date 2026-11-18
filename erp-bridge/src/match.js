function norm(s) {
  return String(s || '')
    .normalize('NFD').replace(/[̀-ͯ]/g, '')
    .toUpperCase().trim();
}

// Filtra a lista de OS para um contato.
// Preferencia: CodigoCliente exato (confiavel). Reforco: nome contem.
// Busca direta por numero de OS tem prioridade.
export function matchOsForContact(list, { codigoCliente, nome, os } = {}) {
  if (os) {
    const n = Number(os);
    return list.filter(o => Number(o.CodigoOS) === n);
  }
  if (codigoCliente) {
    const cc = Number(codigoCliente);
    return list.filter(o => Number(o.CodigoCliente) === cc);
  }
  if (nome) {
    const alvo = norm(nome);
    if (alvo.length < 3) return [];
    return list.filter(o => {
      const c = norm(o.Nome);
      return c.includes(alvo) || alvo.includes(c);
    });
  }
  return []; // sem identificador => nada (a UI oferece busca manual)
}
