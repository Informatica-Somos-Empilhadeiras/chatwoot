// OUTSIDER (Maps): contas do "Mapa dos agendamentos" (routes/dashboard/outsider/apps/map), fora da tela para testar:
// carregar a Maps JavaScript API uma vez, juntar os pins próximos conforme o zoom e montar a ordem das paradas da rota.

let loading = null;

// a Maps JavaScript API com a chave da conta (Configurações > Google > Google Maps); uma vez por página
export const loadGoogleMaps = key => {
  if (window.google?.maps?.Map) return Promise.resolve(window.google.maps);
  if (loading) return loading;
  loading = new Promise((resolve, reject) => {
    const callback = `outsiderMapsReady${Date.now()}`;
    window[callback] = () => {
      delete window[callback];
      resolve(window.google.maps);
    };
    const script = document.createElement('script');
    script.src = `https://maps.googleapis.com/maps/api/js?key=${encodeURIComponent(key)}&v=weekly&language=pt-BR&region=BR&callback=${callback}`;
    script.async = true;
    script.onerror = () => {
      loading = null;
      reject(new Error('maps_load_failed'));
    };
    document.head.appendChild(script);
  });
  return loading;
};

// Junta os pontos que ficam a menos de `radius` pixels uns dos outros na tela (grade do tamanho do raio, como o
// agrupamento do Google). toPixel(point) => { x, y } no zoom atual. Devolve [{ points, latitude, longitude }].
export const clusterize = (points, toPixel, radius = 56) => {
  const cells = new Map();
  points.forEach(point => {
    const { x, y } = toPixel(point);
    const key = `${Math.floor(x / radius)}:${Math.floor(y / radius)}`;
    if (!cells.has(key)) cells.set(key, []);
    cells.get(key).push(point);
  });
  return [...cells.values()].map(list => ({
    points: list,
    latitude: list.reduce((sum, p) => sum + p.latitude, 0) / list.length,
    longitude: list.reduce((sum, p) => sum + p.longitude, 0) / list.length,
  }));
};

// distância em linha reta (km), só para escolher a ordem; o caminho de verdade vem do Google
export const distanceKm = (a, b) => {
  const rad = value => (value * Math.PI) / 180;
  const dLat = rad(b.latitude - a.latitude);
  const dLng = rad(b.longitude - a.longitude);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(a.latitude)) *
      Math.cos(rad(b.latitude)) *
      Math.sin(dLng / 2) ** 2;
  return 6371 * 2 * Math.asin(Math.sqrt(h));
};

// Ordem das paradas de um dia: as que têm hora marcada ficam na ordem do horário; as sem hora (agendadas só com a data)
// entram onde menos aumentam o caminho (inserção mais barata). stops: [{ latitude, longitude, start, all_day }]
export const orderStops = stops => {
  const fixed = stops
    .filter(stop => !stop.all_day)
    .sort((a, b) => String(a.start).localeCompare(String(b.start)));
  const loose = stops.filter(stop => stop.all_day);
  const route = [...fixed];
  loose.forEach(stop => {
    if (!route.length) {
      route.push(stop);
      return;
    }
    let best = route.length;
    let bestCost = distanceKm(route[route.length - 1], stop);
    for (let index = 0; index < route.length; index += 1) {
      const before = route[index - 1];
      const after = route[index];
      const cost = before
        ? distanceKm(before, stop) +
          distanceKm(stop, after) -
          distanceKm(before, after)
        : distanceKm(stop, after);
      if (cost < bestCost) {
        bestCost = cost;
        best = index;
      }
    }
    route.splice(best, 0, stop);
  });
  return route;
};
