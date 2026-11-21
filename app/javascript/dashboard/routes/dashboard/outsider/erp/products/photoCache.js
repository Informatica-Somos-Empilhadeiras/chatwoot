// OUTSIDER: as fotos dos produtos vêm do Nextcloud pela API (com a autenticação do Chatwoot), então o <img> recebe um
// endereço local (blob:). A mesma foto serve a grade da aba Produtos, o carrossel e a busca do orçamento sem baixar de
// novo; as mais antigas saem quando passa de MAX.
import ErpAPI from 'dashboard/api/outsider/erp';

const MAX = 60;
const cache = new Map();

export const photoUrl = (company, code, id) => {
  const key = `${company}:${code}:${id}`;
  const cached = cache.get(key);
  if (cached) {
    cache.delete(key);
    cache.set(key, cached);
    return cached;
  }
  const promise = ErpAPI.productPhoto(company, code, id).then(response =>
    URL.createObjectURL(response.data)
  );
  promise.catch(() => cache.delete(key));
  cache.set(key, promise);
  while (cache.size > MAX) {
    const [oldKey, old] = cache.entries().next().value;
    cache.delete(oldKey);
    old.then(URL.revokeObjectURL, () => {});
  }
  return promise;
};

// a imagem em PNG, o formato que a área de transferência aceita em todos os navegadores
export const pngBlob = async url => {
  const blob = await (await fetch(url)).blob();
  if (blob.type === 'image/png') return blob;
  const bitmap = await createImageBitmap(blob);
  const canvas = document.createElement('canvas');
  canvas.width = bitmap.width;
  canvas.height = bitmap.height;
  canvas.getContext('2d').drawImage(bitmap, 0, 0);
  return new Promise((resolve, reject) => {
    canvas.toBlob(png => (png ? resolve(png) : reject(new Error('png'))));
  });
};

// classes da grade conforme a quantidade: 1 foto ocupa tudo; com mais, as colunas aumentam e as fotos diminuem
export const gridLayout = count => {
  if (count <= 1) return { grid: 'grid-cols-1', cell: 'h-80' };
  if (count === 2) return { grid: 'grid-cols-2', cell: 'h-60' };
  if (count === 3) return { grid: 'grid-cols-3', cell: 'h-48' };
  if (count === 4) return { grid: 'grid-cols-2', cell: 'h-44' };
  if (count <= 6) return { grid: 'grid-cols-3', cell: 'h-36' };
  return { grid: 'grid-cols-3 lg:grid-cols-4', cell: 'h-28' };
};
