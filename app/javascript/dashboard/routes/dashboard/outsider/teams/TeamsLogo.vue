<script setup>
// OUTSIDER: marca do Microsoft Teams (roxo) usada no menu, na área Teams e nas Configurações.
defineProps({ size: { type: Number, default: 18 } });
</script>

<template>
  <svg
    :width="size"
    :height="size"
    viewBox="0 0 24 24"
    class="shrink-0"
    aria-hidden="true"
  >
    <rect x="1" y="3" width="17" height="18" rx="4" fill="#5059C9" />
    <circle cx="19" cy="7" r="3" fill="#7B83EB" />
    <path
      d="M15.5 11h7a1 1 0 0 1 1 1v4.5a4 4 0 0 1-4 4h-.5a3.5 3.5 0 0 1-3.5-3.5z"
      fill="#7B83EB"
    />
    <path d="M5 8h9v2.4h-3.3V18H8.3v-7.6H5z" fill="#fff" />
  </svg>
</template>
