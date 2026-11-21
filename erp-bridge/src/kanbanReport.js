import { config } from './config.js';
import { erpGet } from './erpClient.js';

// Relatorio de OS igual ao que o kanban de KPI imprime: dados da OS, check-in/out,
// produtos e o checklist com as fotos. So leitura, sob demanda; nada vai para disco.
const api = () => `${config.erpBaseUrl}/KanbanOrdemServico/api`;
const REPORT_TTL_MS = 5 * 60 * 1000;
const REPORT_CACHE_MAX = 300;
const IMAGE_TTL_MS = 30 * 60 * 1000;
const IMAGE_CACHE_MAX = 150;

const relatorios = new Map(); // `${empresa}:${codigo}` -> { at, data, logoCnpj }
const pendentes = new Map(); // single-flight: uma busca ao ERP por OS
const imagens = new Map(); // chave -> { at, type, body }

export class NaoEncontrado extends Error {}

export const codigoValido = codigo => /^\d+$/.test(String(codigo));
export const empresaValida = empresa => config.empresas.includes(empresa);
// Foto do checklist e sempre `${codigoOS}_${sequencia}` (campo CaminhoIMG).
export const refValida = (codigo, ref) => new RegExp(`^${codigo}_\\d+$`).test(String(ref));

const texto = v => String(v ?? '').trim();
const lista = v => (Array.isArray(v) ? v : []);
const juntar = (...partes) => partes.map(texto).filter(Boolean).join(' - ');

function guardar(mapa, chave, valor, max) {
  mapa.delete(chave);
  mapa.set(chave, valor);
  if (mapa.size > max) mapa.delete(mapa.keys().next().value);
}

// VALOR_INI e a leitura na chegada, VALOR_FIM na saida; PREFIXO/SUFIXO envolvem o valor.
function valores(linha) {
  const fmt = v => (texto(v) ? [linha.PREFIXO, v, linha.SUFIXO].map(texto).filter(Boolean).join(' ') : '');
  return { chegada: fmt(texto(linha.VALOR_INI) || linha.VALOR), saida: fmt(linha.VALOR_FIM) };
}

// Cada linha do checklist e uma foto ligada a um atributo; agrupa secao > atributo na ordem do ERP.
// (temImg vem 0 mesmo quando a foto existe, por isso o criterio e ter CaminhoIMG.)
function montarChecklist(codigo, empresa, linhas) {
  const ordem = l => [Number(l.ORDEM_SESSAO), Number(l.ORDEM_ATRIBUTO), Number(l.CodigoAnexo)];
  const ordenadas = [...linhas].sort((a, b) => {
    const [x, y] = [ordem(a), ordem(b)];
    return (x[0] - y[0]) || (x[1] - y[1]) || (x[2] - y[2]);
  });
  const secoes = new Map();
  for (const l of ordenadas) {
    if (!secoes.has(l.COD_SESSAO)) secoes.set(l.COD_SESSAO, { nome: texto(l.DESC_SESSAO), itens: new Map() });
    const { itens } = secoes.get(l.COD_SESSAO);
    if (!itens.has(l.COD_ATRIBUTO)) itens.set(l.COD_ATRIBUTO, { atributo: texto(l.DESC_ATRIBUTO), ...valores(l), fotos: [] });
    const ref = texto(l.CaminhoIMG);
    if (refValida(codigo, ref)) {
      itens.get(l.COD_ATRIBUTO).fotos.push(`/api/os/${codigo}/imagem/${ref}?empresa=${encodeURIComponent(empresa)}`);
    }
  }
  return [...secoes.values()].map(s => ({ nome: s.nome, itens: [...s.itens.values()] }));
}

function montar(codigo, empresa, { os, checkin, checklist, produtos }) {
  const o = lista(os)[0];
  const linhas = lista(checklist);
  return {
    codigo: Number(codigo),
    empresa,
    logo: texto(o.CPF_CNPJ) ? `/api/os/${codigo}/logo?empresa=${encodeURIComponent(empresa)}` : null,
    emissor: { nome: texto(o.NomeImpressao), telefone: texto(o.TelefoneImpressao), email: texto(o.EmailImpressao) },
    cliente: {
      nome: texto(o.NomeCliente),
      documento: texto(o.CPF_CNPJCliente),
      endereco: juntar(o.endereco, o.bairro),
      cidade: juntar(o.cidade, o.uf),
    },
    equipamento: {
      descricao: texto(o.DescricaoMaquina),
      marca: texto(o.marca),
      modelo: texto(o.modelo),
      serie: texto(o.nserie),
      horimetro: texto(o.Horimetro),
    },
    servico: {
      tipoAtendimento: texto(o.TipoAtendimento),
      classificacao: texto(o.ClasseOS),
      tecnico: texto(o.NomeTecnico),
      defeitos: texto(o.Defeitos),
    },
    avaliacao: texto(o.AvaliacaoTecnica),
    eventos: lista(checkin).map(e => ({
      tipo: texto(e.Tipo),
      observacoes: texto(e.Observacoes),
      checkIn: texto(e.dataHoraCheckIn),
      checkOut: texto(e.dataHoraCheckOut),
    })),
    produtos: lista(produtos).map(p => ({
      codigo: texto(p.CodigoProduto),
      descricao: texto(p.Descricao),
      unidade: texto(p.Unidade),
      quantidade: texto(p.Quantidade),
    })),
    familia: texto(linhas[0]?.DescricaoFamilia),
    checklist: montarChecklist(codigo, empresa, linhas),
  };
}

async function buscar(codigo, empresa) {
  const qs = `?CodigoOS=${codigo}&Empresa=${encodeURIComponent(empresa)}`;
  const get = nome => erpGet(`${api()}/${nome}${qs}`, 'application/json', res => res.json());
  const [os, checkin, checklist, produtos] = await Promise.all(
    ['DadosOS_PDF', 'DadosCheckIn_PDF', 'DadosCheckList_PDF', 'DadosProdutosOS_PDF'].map(get),
  );
  if (!lista(os).length) throw new NaoEncontrado(`OS ${codigo} nao encontrada em ${empresa}`);
  return { data: montar(codigo, empresa, { os, checkin, checklist, produtos }), logoCnpj: texto(os[0].CPF_CNPJ).replace(/\D/g, '') };
}

export async function relatorioOs(codigo, empresa) {
  const chave = `${empresa}:${codigo}`;
  const hit = relatorios.get(chave);
  if (hit && Date.now() - hit.at < REPORT_TTL_MS) return hit;
  if (!pendentes.has(chave)) {
    pendentes.set(chave, buscar(codigo, empresa)
      .then((r) => {
        const entrada = { at: Date.now(), ...r };
        guardar(relatorios, chave, entrada, REPORT_CACHE_MAX);
        return entrada;
      })
      .finally(() => pendentes.delete(chave)));
  }
  return pendentes.get(chave);
}

// Repassa a imagem do ERP; recusa qualquer resposta que nao seja imagem para a ponte
// nunca servir outro conteudo (HTML/JSON) com a origem dela.
async function binario(url, chave) {
  const hit = imagens.get(chave);
  if (hit && Date.now() - hit.at < IMAGE_TTL_MS) return hit;
  const img = await erpGet(url, 'image/*', async res => ({
    type: res.headers.get('content-type') || '',
    body: Buffer.from(await res.arrayBuffer()),
  }));
  if (!img.type.startsWith('image/')) throw new Error(`ERP devolveu ${img.type || 'conteudo vazio'} em vez de imagem`);
  const entrada = { at: Date.now(), ...img };
  guardar(imagens, chave, entrada, IMAGE_CACHE_MAX);
  return entrada;
}

export const fotoChecklist = (ref, empresa) =>
  binario(`${api()}/getimagemchecklistos/${ref}/${encodeURIComponent(empresa)}`, `foto:${empresa}:${ref}`);

// O logo vem do CNPJ do emissor que o proprio relatorio trouxe (nunca de um CNPJ vindo da URL).
export async function logoEmissor(codigo, empresa) {
  const { logoCnpj } = await relatorioOs(codigo, empresa);
  if (!logoCnpj) throw new NaoEncontrado('OS sem CNPJ do emissor');
  return binario(`${api()}/download-logo-empresa/${logoCnpj}`, `logo:${logoCnpj}`);
}
