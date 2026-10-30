<script setup>
// OUTSIDER: Configurações > Aparência (só administradores). Nome na aba, favicon, logo e papel de
// parede das conversas desta conta, com prévia antes de salvar. Vale para todos os agentes da conta.
import { ref, reactive, computed, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import BrandingAPI from 'dashboard/api/outsider/branding';
import SettingsLayout from 'dashboard/routes/dashboard/settings/SettingsLayout.vue';
import BaseSettingsHeader from 'dashboard/routes/dashboard/settings/components/BaseSettingsHeader.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { setBranding } from './useAccountBranding';

const IMAGE_KINDS = ['favicon', 'logo', 'wallpaper'];
const ACCEPT = 'image/png,image/jpeg,image/webp,image/gif';
const MAX_BYTES = { favicon: 2, logo: 3, wallpaper: 8 };

const { t } = useI18n();

const isLoading = ref(true);
const isSaving = ref(false);
const saved = ref(null);
const form = reactive({ title: '', wallpaperFit: 'cover', wallpaperDim: 60 });
// arquivo escolhido e ainda não salvo, ou "remover"
const pending = reactive({ favicon: null, logo: null, wallpaper: null });
const removing = reactive({ favicon: false, logo: false, wallpaper: false });
const previews = reactive({ favicon: null, logo: null, wallpaper: null });
const inputs = { favicon: ref(null), logo: ref(null), wallpaper: ref(null) };

const currentUrl = kind => {
  if (previews[kind]) return previews[kind];
  if (removing[kind]) return null;
  return saved.value?.[`${kind}_url`] || null;
};

const tabTitle = computed(() => form.title.trim() || 'Chatwoot');
const isDirty = computed(
  () =>
    !!saved.value &&
    ((saved.value.title || '') !== form.title.trim() ||
      saved.value.wallpaper_fit !== form.wallpaperFit ||
      saved.value.wallpaper_dim !== Number(form.wallpaperDim) ||
      IMAGE_KINDS.some(kind => pending[kind] || removing[kind]))
);

const wallpaperStyle = computed(() => {
  const url = currentUrl('wallpaper');
  const dim = Number(form.wallpaperDim) / 100;
  const image = url
    ? `linear-gradient(rgba(255,255,255,${dim}), rgba(255,255,255,${dim})), url("${url}")`
    : `linear-gradient(rgba(255,255,255,0.6), rgba(255,255,255,0.6)), url('/light.png')`;
  const tile = url && form.wallpaperFit === 'tile';
  return {
    backgroundImage: image,
    backgroundRepeat: tile ? 'repeat' : 'no-repeat',
    backgroundSize: tile ? 'auto, 210px auto' : 'cover',
    backgroundPosition: tile ? 'top left' : 'center',
  };
});

const fill = data => {
  saved.value = data;
  form.title = data.title || '';
  form.wallpaperFit = data.wallpaper_fit || 'cover';
  form.wallpaperDim = data.wallpaper_dim ?? 60;
  IMAGE_KINDS.forEach(kind => {
    if (previews[kind]) URL.revokeObjectURL(previews[kind]);
    previews[kind] = null;
    pending[kind] = null;
    removing[kind] = false;
  });
};

const pick = kind => inputs[kind].value?.click();

const onFile = (kind, event) => {
  const [file] = event.target.files || [];
  event.target.value = '';
  if (!file) return;
  if (file.size > MAX_BYTES[kind] * 1024 * 1024) {
    useAlert(t('OUTSIDER_TOOLS.BRANDING.TOO_BIG', { size: MAX_BYTES[kind] }));
    return;
  }
  if (previews[kind]) URL.revokeObjectURL(previews[kind]);
  pending[kind] = file;
  removing[kind] = false;
  previews[kind] = URL.createObjectURL(file);
};

const remove = kind => {
  if (previews[kind]) URL.revokeObjectURL(previews[kind]);
  previews[kind] = null;
  pending[kind] = null;
  removing[kind] = !!saved.value?.[`${kind}_url`];
};

const ERRORS = ['invalid_type', 'too_big', 'invalid_file'];

const save = async () => {
  isSaving.value = true;
  const body = new FormData();
  body.append('title', form.title.trim());
  body.append('wallpaper_fit', form.wallpaperFit);
  body.append('wallpaper_dim', String(form.wallpaperDim));
  IMAGE_KINDS.forEach(kind => {
    if (pending[kind]) body.append(kind, pending[kind]);
    if (removing[kind]) body.append(`remove_${kind}`, 'true');
  });
  try {
    const { data } = await BrandingAPI.update(body);
    fill(data);
    setBranding(data);
    useAlert(t('OUTSIDER_TOOLS.BRANDING.SAVED'));
  } catch (error) {
    const code = error?.response?.data?.error;
    useAlert(
      ERRORS.includes(code)
        ? t(`OUTSIDER_TOOLS.BRANDING.ERRORS.${code}`)
        : t('OUTSIDER_TOOLS.BRANDING.ERRORS.generic')
    );
  } finally {
    isSaving.value = false;
  }
};

onMounted(async () => {
  try {
    const { data } = await BrandingAPI.get();
    fill(data);
  } catch {
    useAlert(t('OUTSIDER_TOOLS.BRANDING.ERRORS.generic'));
  } finally {
    isLoading.value = false;
  }
});

onBeforeUnmount(() => {
  IMAGE_KINDS.forEach(kind => {
    if (previews[kind]) URL.revokeObjectURL(previews[kind]);
  });
});
</script>

<template>
  <SettingsLayout :is-loading="isLoading">
    <template #header>
      <BaseSettingsHeader
        :title="t('OUTSIDER_TOOLS.BRANDING.TITLE')"
        :description="t('OUTSIDER_TOOLS.BRANDING.DESCRIPTION')"
      >
        <template #actions>
          <Button
            :label="t('OUTSIDER_TOOLS.BRANDING.SAVE')"
            icon="i-lucide-check"
            :is-loading="isSaving"
            :disabled="!isDirty"
            @click="save"
          />
        </template>
      </BaseSettingsHeader>
    </template>

    <template #body>
      <div class="grid w-full gap-6 pb-10 lg:grid-cols-2">
        <!-- Nome e favicon -->
        <section
          class="flex flex-col gap-4 p-5 border rounded-xl border-n-weak bg-n-solid-1"
        >
          <div>
            <h3 class="text-base font-medium text-n-slate-12">
              {{ t('OUTSIDER_TOOLS.BRANDING.TAB_SECTION') }}
            </h3>
            <p class="text-sm text-n-slate-11">
              {{ t('OUTSIDER_TOOLS.BRANDING.TAB_HINT') }}
            </p>
          </div>
          <!-- prévia da aba do navegador -->
          <div class="flex items-end h-12 px-3 pt-2 rounded-lg bg-n-alpha-2">
            <div
              class="flex items-center gap-2 px-3 py-2 text-xs rounded-t-lg shadow-sm w-60 bg-n-solid-1 text-n-slate-12"
            >
              <img
                :src="currentUrl('favicon') || '/favicon-32x32.png'"
                class="object-contain size-4 shrink-0"
              />
              <span class="truncate">{{ tabTitle }}</span>
              <Icon icon="i-lucide-x" class="ml-auto size-3 text-n-slate-10" />
            </div>
          </div>
          <Input
            v-model="form.title"
            :label="t('OUTSIDER_TOOLS.BRANDING.TAB_TITLE')"
            placeholder="Chatwoot"
            :message="t('OUTSIDER_TOOLS.BRANDING.TAB_TITLE_HINT')"
          />
          <div class="flex items-center gap-4">
            <span
              class="flex items-center justify-center border rounded-lg size-14 border-n-weak bg-n-alpha-1"
            >
              <img
                :src="currentUrl('favicon') || '/favicon-32x32.png'"
                class="object-contain size-8"
              />
            </span>
            <div class="flex flex-col gap-1">
              <span class="text-sm font-medium text-n-slate-12">
                {{ t('OUTSIDER_TOOLS.BRANDING.FAVICON') }}
              </span>
              <span class="text-xs text-n-slate-11">
                {{ t('OUTSIDER_TOOLS.BRANDING.FAVICON_HINT') }}
              </span>
              <div class="flex gap-2 mt-1">
                <Button
                  :label="t('OUTSIDER_TOOLS.BRANDING.CHOOSE')"
                  icon="i-lucide-upload"
                  xs
                  faded
                  @click="pick('favicon')"
                />
                <Button
                  v-if="currentUrl('favicon')"
                  :label="t('OUTSIDER_TOOLS.BRANDING.REMOVE')"
                  xs
                  ghost
                  ruby
                  @click="remove('favicon')"
                />
              </div>
            </div>
            <input
              :ref="inputs.favicon"
              type="file"
              class="hidden"
              :accept="ACCEPT"
              @change="onFile('favicon', $event)"
            />
          </div>
        </section>

        <!-- Logo -->
        <section
          class="flex flex-col gap-4 p-5 border rounded-xl border-n-weak bg-n-solid-1"
        >
          <div>
            <h3 class="text-base font-medium text-n-slate-12">
              {{ t('OUTSIDER_TOOLS.BRANDING.LOGO') }}
            </h3>
            <p class="text-sm text-n-slate-11">
              {{ t('OUTSIDER_TOOLS.BRANDING.LOGO_HINT') }}
            </p>
          </div>
          <div class="flex items-center gap-4">
            <span
              class="flex items-center justify-center p-2 border rounded-lg size-20 border-n-weak bg-n-alpha-1"
            >
              <img
                v-if="currentUrl('logo')"
                :src="currentUrl('logo')"
                class="object-contain max-w-full max-h-full"
              />
              <Icon
                v-else
                icon="i-lucide-image"
                class="size-6 text-n-slate-9"
              />
            </span>
            <div class="flex gap-2">
              <Button
                :label="t('OUTSIDER_TOOLS.BRANDING.CHOOSE')"
                icon="i-lucide-upload"
                xs
                faded
                @click="pick('logo')"
              />
              <Button
                v-if="currentUrl('logo')"
                :label="t('OUTSIDER_TOOLS.BRANDING.REMOVE')"
                xs
                ghost
                ruby
                @click="remove('logo')"
              />
            </div>
            <input
              :ref="inputs.logo"
              type="file"
              class="hidden"
              :accept="ACCEPT"
              @change="onFile('logo', $event)"
            />
          </div>
        </section>

        <!-- Papel de parede -->
        <section
          class="flex flex-col gap-4 p-5 border rounded-xl border-n-weak bg-n-solid-1 lg:col-span-2"
        >
          <div>
            <h3 class="text-base font-medium text-n-slate-12">
              {{ t('OUTSIDER_TOOLS.BRANDING.WALLPAPER') }}
            </h3>
            <p class="text-sm text-n-slate-11">
              {{ t('OUTSIDER_TOOLS.BRANDING.WALLPAPER_HINT') }}
            </p>
          </div>
          <div class="grid gap-5 md:grid-cols-[minmax(0,1fr)_16rem]">
            <!-- prévia da conversa -->
            <div
              class="flex flex-col justify-end h-64 gap-2 p-4 overflow-hidden border rounded-lg border-n-weak"
              :style="wallpaperStyle"
            >
              <div
                class="self-start max-w-[70%] px-3 py-2 text-sm rounded-xl rounded-bl-sm bg-white text-slate-900 shadow-sm"
              >
                {{ t('OUTSIDER_TOOLS.BRANDING.PREVIEW_IN') }}
              </div>
              <div
                class="self-end max-w-[70%] px-3 py-2 text-sm rounded-xl rounded-br-sm bg-[#d9fdd3] text-slate-900 shadow-sm"
              >
                {{ t('OUTSIDER_TOOLS.BRANDING.PREVIEW_OUT') }}
              </div>
            </div>
            <div class="flex flex-col gap-4">
              <div class="flex flex-wrap gap-2">
                <Button
                  :label="t('OUTSIDER_TOOLS.BRANDING.CHOOSE_IMAGE')"
                  icon="i-lucide-upload"
                  sm
                  faded
                  @click="pick('wallpaper')"
                />
                <Button
                  v-if="currentUrl('wallpaper')"
                  :label="t('OUTSIDER_TOOLS.BRANDING.RESTORE_DEFAULT')"
                  sm
                  ghost
                  ruby
                  @click="remove('wallpaper')"
                />
              </div>
              <input
                :ref="inputs.wallpaper"
                type="file"
                class="hidden"
                :accept="ACCEPT"
                @change="onFile('wallpaper', $event)"
              />
              <div class="flex flex-col gap-2">
                <span class="text-sm font-medium text-n-slate-12">
                  {{ t('OUTSIDER_TOOLS.BRANDING.FIT') }}
                </span>
                <div class="flex gap-2">
                  <Button
                    v-for="fit in ['cover', 'tile']"
                    :key="fit"
                    :label="t(`OUTSIDER_TOOLS.BRANDING.FITS.${fit}`)"
                    xs
                    :faded="form.wallpaperFit !== fit"
                    :slate="form.wallpaperFit !== fit"
                    @click="form.wallpaperFit = fit"
                  />
                </div>
              </div>
              <label class="flex flex-col gap-2">
                <span class="text-sm font-medium text-n-slate-12">
                  {{
                    t('OUTSIDER_TOOLS.BRANDING.DIM', {
                      value: form.wallpaperDim,
                    })
                  }}
                </span>
                <input
                  v-model.number="form.wallpaperDim"
                  type="range"
                  min="0"
                  max="90"
                  step="5"
                  class="w-full accent-n-brand"
                />
                <span class="text-xs text-n-slate-11">
                  {{ t('OUTSIDER_TOOLS.BRANDING.DIM_HINT') }}
                </span>
              </label>
            </div>
          </div>
        </section>
        <p class="text-xs text-n-slate-10 lg:col-span-2">
          {{ t('OUTSIDER_TOOLS.BRANDING.LOGIN_NOTE') }}
        </p>
      </div>
    </template>
  </SettingsLayout>
</template>
