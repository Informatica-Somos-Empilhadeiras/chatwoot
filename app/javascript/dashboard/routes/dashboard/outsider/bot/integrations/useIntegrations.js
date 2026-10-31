// OUTSIDER: conexões e planilhas da conta, carregadas uma vez e usadas pelo editor do bot (listas dos
// blocos, resumos e avisos) e pelas abas Conexões e Planilhas, que recarregam depois de mudar algo.
import { reactive } from 'vue';
import BotConnectionsAPI from 'dashboard/api/outsider/botConnections';
import BotDatasetsAPI from 'dashboard/api/outsider/botDatasets';

const state = reactive({
  connections: [],
  datasets: [],
  loaded: false,
  loading: false,
  failed: false,
});

let pending = null;

export const loadIntegrations = (force = false) => {
  if (pending && !force) return pending;
  state.loading = true;
  pending = Promise.all([BotConnectionsAPI.get(), BotDatasetsAPI.get()])
    .then(([connections, datasets]) => {
      state.connections = connections.data.payload;
      state.datasets = datasets.data.payload;
      state.loaded = true;
      state.failed = false;
    })
    .catch(() => {
      state.failed = true;
      pending = null;
    })
    .finally(() => {
      state.loading = false;
    });
  return pending;
};

export const useIntegrations = () => state;

export const connectionsOf = kind =>
  state.connections.filter(connection => connection.kind === kind);
