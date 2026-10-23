// OUTSIDER: localização do WhatsApp.
// A Evolution grava a localização recebida (ou enviada) como texto, no idioma dela:
//   *Localização:*\n\n_Latitude:_ -16.68 \n_Longitude:_ -49.25 \n_Nome:_ ...\n_Endereço:_ ...\n_URL:_ https://...
// Nome e endereço só vêm quando o pin tem. Nas recebidas a marcação vem trocada ("**Localização:**",
// "*Latitude:*"; ver whatsappText.js). Nos grupos, o texto começa com quem enviou. A enviada
// pelo Chatwoot (botão Localização) traz os dados prontos em content_attributes.outsider_location.
// Daqui sai o local que o Message.vue desenha com o LocationCard.vue, e as contas do mapa.
import { FIELD, splitTypedContent, typeHeaderRegex } from './whatsappText';

const HEADER = typeHeaderRegex('Localiza[çc][ãa]o|Location|Ubicaci[óo]n');
const TILE_SIZE = 256;
const TILE_URL = 'https://tile.openstreetmap.org';

const fieldOf = label => {
  const key = label.trim().toLowerCase();
  if (key.startsWith('lat')) return 'latitude';
  if (key.startsWith('lon')) return 'longitude';
  if (/^(nom|name)/.test(key)) return 'name';
  if (/^(end|addr|dir)/.test(key)) return 'address';
  return null;
};

const toNumber = value => {
  const number = Number(String(value ?? '').replace(',', '.'));
  return value !== '' && value !== null && Number.isFinite(number)
    ? number
    : null;
};

const validPoint = place =>
  place &&
  place.latitude !== null &&
  place.longitude !== null &&
  Math.abs(place.latitude) <= 90 &&
  Math.abs(place.longitude) <= 180;

// devolve null quando o texto não é uma localização (aí fica a bolha de texto normal)
export const parseLocationText = content => {
  const { header, body } = splitTypedContent(content, HEADER);
  const lines = body ? body.split('\n').map(line => line.trim()) : [];
  if (!lines.length || !HEADER.test(lines[0])) return null;

  const place = { latitude: null, longitude: null, name: '', address: '' };
  const valid = lines.slice(1).every(line => {
    if (!line) return true;
    const match = line.match(FIELD);
    if (!match) return false;
    const field = fieldOf(match[1]);
    if (field === 'latitude' || field === 'longitude') {
      place[field] = toNumber(match[2].trim());
    } else if (field) {
      place[field] = match[2].trim();
    }
    return true;
  });
  return valid && validPoint(place) ? { header, ...place } : null;
};

export const locationOf = ({ content, contentAttributes } = {}) => {
  const sent = contentAttributes?.outsiderLocation;
  if (sent) {
    const place = {
      latitude: toNumber(sent.latitude),
      longitude: toNumber(sent.longitude),
      name: sent.name || '',
      address: sent.address || '',
    };
    if (validPoint(place)) {
      return { header: splitTypedContent(content, HEADER).header, ...place };
    }
  }
  return parseLocationText(content);
};

// Texto curto para a lista de conversas: "📍 Somos - Matriz" no lugar de "Localização: Latitude: ..."
export const locationPreview = ({ content, contentAttributes } = {}) => {
  const place = locationOf({ content, contentAttributes });
  if (!place) return null;
  const label =
    splitTypedContent(content, HEADER)
      .body.split('\n')[0]
      .replace(/[*:]/g, '')
      .trim() || 'Localização';
  return `📍 ${place.name || place.address || label}`;
};

export const isLocationMessage = props =>
  !props.private && !props.attachments?.length && !!locationOf(props);

export const googleMapsUrl = ({ latitude, longitude }) =>
  `https://www.google.com/maps/search/?api=1&query=${latitude},${longitude}`;

export const wazeUrl = ({ latitude, longitude }) =>
  `https://waze.com/ul?ll=${latitude},${longitude}&navigate=yes`;

export const formatCoordinates = ({ latitude, longitude }) =>
  `${Number(latitude).toFixed(6)}, ${Number(longitude).toFixed(6)}`;

// Pedaços (tiles) do OpenStreetMap que cobrem um quadro width x height com o ponto no meio
export const mapTiles = ({ latitude, longitude, width, height, zoom = 16 }) => {
  const scale = TILE_SIZE * 2 ** zoom;
  const radians = (latitude * Math.PI) / 180;
  const pointX = ((longitude + 180) / 360) * scale;
  const pointY =
    ((1 - Math.log(Math.tan(radians) + 1 / Math.cos(radians)) / Math.PI) / 2) *
    scale;
  const left = pointX - width / 2;
  const top = pointY - height / 2;
  const count = 2 ** zoom;
  const tiles = [];
  for (
    let y = Math.floor(top / TILE_SIZE);
    y <= Math.floor((top + height) / TILE_SIZE);
    y += 1
  ) {
    for (
      let x = Math.floor(left / TILE_SIZE);
      x <= Math.floor((left + width) / TILE_SIZE);
      x += 1
    ) {
      if (y >= 0 && y < count) {
        const wrappedX = ((x % count) + count) % count;
        tiles.push({
          key: `${zoom}/${x}/${y}`,
          url: `${TILE_URL}/${zoom}/${wrappedX}/${y}.png`,
          left: Math.round(x * TILE_SIZE - left),
          top: Math.round(y * TILE_SIZE - top),
        });
      }
    }
  }
  return tiles;
};

// Ponto que fica dx, dy pixels do ponto dado num mapa com este zoom (clique no mapa para ajustar o pin)
export const movePoint = ({ latitude, longitude, dx, dy, zoom = 16 }) => {
  const scale = TILE_SIZE * 2 ** zoom;
  const radians = (latitude * Math.PI) / 180;
  const x = ((longitude + 180) / 360) * scale + dx;
  const y =
    ((1 - Math.log(Math.tan(radians) + 1 / Math.cos(radians)) / Math.PI) / 2) *
      scale +
    dy;
  const lng = (x / scale) * 360 - 180;
  const lat =
    (Math.atan(Math.sinh(Math.PI * (1 - (2 * y) / scale))) * 180) / Math.PI;
  return {
    latitude: Number(lat.toFixed(6)),
    longitude: Number((((lng + 540) % 360) - 180).toFixed(6)),
  };
};
