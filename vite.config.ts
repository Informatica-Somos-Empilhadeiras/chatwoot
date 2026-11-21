import { defineConfig } from 'vite';
import ruby from 'vite-plugin-ruby';
import vue from '@vitejs/plugin-vue';
import { aliases, vueOptions } from './vite.shared';
import yaml from '@rollup/plugin-yaml';

export default defineConfig({
  plugins: [ruby(), vue(vueOptions), yaml()],
  // OUTSIDER: sem os mapas de depuração (sourcemaps) o build de produção cai de ~5,2 GB para ~3,6 GB de memória e cabe
  // no servidor; VITE_SOURCEMAP=true liga de novo
  build: { sourcemap: process.env.VITE_SOURCEMAP === 'true' },
  css: {
    preprocessorOptions: {
      scss: {
        api: 'modern-compiler',
      },
    },
  },
  resolve: { alias: aliases },
});
