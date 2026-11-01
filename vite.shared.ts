import path from 'path';

export const aliases = {
  // OUTSIDER: visualizador de mídia no estilo WhatsApp no lugar da galeria do Chatwoot
  // (precisa vir antes de "dashboard"; o original continua no mesmo caminho)
  'dashboard/components/widgets/conversation/components/GalleryView.vue':
    path.resolve(
      './app/javascript/dashboard/components-next/outsider/mediaViewer/MediaViewer.vue'
    ),
  vue: 'vue/dist/vue.esm-bundler.js',
  components: path.resolve('./app/javascript/dashboard/components'),
  next: path.resolve('./app/javascript/dashboard/components-next'),
  v3: path.resolve('./app/javascript/v3'),
  dashboard: path.resolve('./app/javascript/dashboard'),
  helpers: path.resolve('./app/javascript/shared/helpers'),
  shared: path.resolve('./app/javascript/shared'),
  survey: path.resolve('./app/javascript/survey'),
  widget: path.resolve('./app/javascript/widget'),
  assets: path.resolve('./app/javascript/dashboard/assets'),
};

export const vueOptions = {
  template: {
    compilerOptions: {
      isCustomElement: (tag: string) => ['ninja-keys'].includes(tag),
    },
  },
};
