// OUTSIDER: imagens de um modelo de proposta no editor (Entrega 17): cabeçalho e rodapé (do modelo ou, no
// modelo padrão, as que vêm com o CRM), a proporção de cada um para desenhar a folha e o endereço das
// imagens do modelo (elementos soltos e blocos de imagem), inclusive as recém-enviadas, que só passam a
// valer no modelo quando ele é salvo. As imagens padrão do CRM são baixadas uma vez por página aberta.
import { computed, ref, unref, watch } from 'vue';
import CrmAPI from 'dashboard/api/outsider/crm';

const defaults = {};

const loadDefault = slot => {
  if (!defaults[slot]) {
    defaults[slot] = CrmAPI.getProposalTemplateDefaultImage(slot)
      .then(({ data }) => URL.createObjectURL(data))
      .catch(() => {
        delete defaults[slot];
        return '';
      });
  }
  return defaults[slot];
};

const ratioOf = url =>
  new Promise(resolve => {
    if (!url) {
      resolve(0);
      return;
    }
    const image = new Image();
    image.onload = () =>
      resolve(
        image.naturalWidth ? image.naturalHeight / image.naturalWidth : 0
      );
    image.onerror = () => resolve(0);
    image.src = url;
  });

export const useTemplateImages = templateRef => {
  const defaultUrls = ref({ header: '', footer: '' });
  const ratios = ref({ header: 0, footer: 0 });
  const uploaded = ref({});

  const template = computed(() => unref(templateRef) || {});
  const usesDefault = computed(
    () => !!template.value.content?.default_letterhead
  );

  const slotUrl = slot =>
    template.value[`${slot}_image_url`] ||
    (usesDefault.value ? defaultUrls.value[slot] : '');
  const headerUrl = computed(() => slotUrl('header'));
  const footerUrl = computed(() => slotUrl('footer'));

  watch(
    () => [
      usesDefault.value,
      template.value.header_image_url,
      template.value.footer_image_url,
    ],
    () => {
      ['header', 'footer'].forEach(async slot => {
        if (!usesDefault.value || template.value[`${slot}_image_url`]) return;
        const url = await loadDefault(slot);
        defaultUrls.value = { ...defaultUrls.value, [slot]: url };
      });
    },
    { immediate: true }
  );

  // altura do cabeçalho e do rodapé na folha, pela proporção da imagem
  watch(
    () => [headerUrl.value, footerUrl.value],
    ([header, footer]) => {
      ratioOf(header).then(ratio => {
        ratios.value = { ...ratios.value, header: ratio };
      });
      ratioOf(footer).then(ratio => {
        ratios.value = { ...ratios.value, footer: ratio };
      });
    },
    { immediate: true }
  );

  const imageUrls = computed(() => ({
    ...Object.fromEntries(
      (template.value.layout_images || []).map(image => [image.id, image.url])
    ),
    ...uploaded.value,
  }));

  const remember = (id, url) => {
    uploaded.value = { ...uploaded.value, [id]: url };
  };

  return { headerUrl, footerUrl, ratios, imageUrls, remember };
};
