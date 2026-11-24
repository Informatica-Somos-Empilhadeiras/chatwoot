<script setup>
// OUTSIDER: ícones da empresa e de cada aplicativo nos blocos Microsoft e Google do menu e nas telas.
// name: microsoft | google | teams | outlook | onedrive | mcalendar | gmail | gcalendar | gdrive
defineProps({
  name: { type: String, required: true },
  size: { type: Number, default: 18 },
});

// o "31" do ícone da agenda do Google
const CALENDAR_DAY = '31';
</script>

<template>
  <svg
    :width="size"
    :height="size"
    viewBox="0 0 24 24"
    class="shrink-0"
    aria-hidden="true"
    :data-app-logo="name"
  >
    <template v-if="name === 'microsoft'">
      <rect x="1" y="1" width="10.5" height="10.5" fill="#f25022" />
      <rect x="12.5" y="1" width="10.5" height="10.5" fill="#7fba00" />
      <rect x="1" y="12.5" width="10.5" height="10.5" fill="#00a4ef" />
      <rect x="12.5" y="12.5" width="10.5" height="10.5" fill="#ffb900" />
    </template>
    <template v-else-if="name === 'google'">
      <path
        fill="#EA4335"
        d="M12 4.75c1.77 0 3.35.61 4.6 1.8l3.43-3.43C17.95 1.19 15.24 0 12 0 7.31 0 3.26 2.69 1.28 6.61l4 3.1C6.22 6.86 8.87 4.75 12 4.75z"
      />
      <path
        fill="#4285F4"
        d="M23.49 12.27c0-.79-.07-1.54-.19-2.27H12v4.51h6.47c-.29 1.48-1.14 2.73-2.4 3.58l3.86 3c2.26-2.09 3.56-5.17 3.56-8.82z"
      />
      <path
        fill="#FBBC05"
        d="M5.27 14.29A7.2 7.2 0 0 1 4.89 12c0-.8.14-1.57.38-2.29l-4-3.1A11.96 11.96 0 0 0 0 12c0 1.94.46 3.77 1.28 5.39l3.99-3.1z"
      />
      <path
        fill="#34A853"
        d="M12 24c3.24 0 5.96-1.07 7.95-2.91l-3.86-3c-1.08.72-2.45 1.16-4.09 1.16-3.13 0-5.78-2.11-6.73-4.96l-4 3.1C3.26 21.31 7.31 24 12 24z"
      />
    </template>
    <template v-else-if="name === 'teams'">
      <rect x="1" y="3" width="17" height="18" rx="4" fill="#5b5fc7" />
      <circle cx="19.5" cy="7" r="3" fill="#7b83eb" />
      <path d="M5.5 8h8v2h-3v8h-2v-8h-3z" fill="#fff" />
    </template>
    <template v-else-if="name === 'outlook'">
      <rect x="1" y="3" width="22" height="18" rx="4" fill="#0f6cbd" />
      <ellipse
        cx="9"
        cy="12"
        rx="3.6"
        ry="4.4"
        fill="none"
        stroke="#fff"
        stroke-width="2"
      />
      <path d="M15 9h5v6h-5z" fill="#cfe4fa" />
    </template>
    <template v-else-if="name === 'onedrive'">
      <path
        d="M6.5 19h11.2a4.3 4.3 0 0 0 .5-8.57A6.3 6.3 0 0 0 6.3 8.9 5.05 5.05 0 0 0 6.5 19z"
        fill="#1490df"
      />
    </template>
    <template v-else-if="name === 'mcalendar'">
      <rect x="2" y="3" width="20" height="19" rx="4" fill="#0f6cbd" />
      <path d="M2 9h20" stroke="#fff" stroke-width="1.6" />
      <path
        d="M7 1.5v4M17 1.5v4"
        stroke="#0f6cbd"
        stroke-width="2"
        stroke-linecap="round"
      />
      <rect x="6" y="12" width="4" height="3" rx=".8" fill="#fff" />
      <rect x="14" y="12" width="4" height="3" rx=".8" fill="#cfe4fa" />
      <rect x="6" y="16.5" width="4" height="3" rx=".8" fill="#cfe4fa" />
    </template>
    <template v-else-if="name === 'gmail'">
      <path
        d="M2 20V7l10 7.5L22 7v13h-4.5V11.5L12 15.6 6.5 11.5V20z"
        fill="#EA4335"
      />
      <path d="M2 7l10 7.5v1.1L2 8.2z" fill="#C5221F" />
      <path d="M2 20h4.5v-8.5L2 8.2z" fill="#4285F4" />
      <path d="M17.5 20H22V8.2l-4.5 3.3z" fill="#34A853" />
      <path d="M17.5 11.5L22 8.2V7l-4.5 3.3z" fill="#FBBC04" />
    </template>
    <template v-else-if="name === 'gcalendar'">
      <rect
        x="2.5"
        y="2.5"
        width="19"
        height="19"
        rx="3"
        fill="#fff"
        stroke="#4285F4"
        stroke-width="1.5"
      />
      <path d="M2.5 7.5h19" stroke="#4285F4" stroke-width="2" />
      <text
        x="12"
        y="18.5"
        text-anchor="middle"
        font-size="9"
        font-weight="700"
        fill="#4285F4"
        font-family="Arial, sans-serif"
      >
        {{ CALENDAR_DAY }}
      </text>
    </template>
    <template v-else-if="name === 'gdrive'">
      <path d="M8.2 2.5h7.6l7.2 12.4h-7.6z" fill="#FBBC04" />
      <path d="M8.2 2.5l3.8 6.6-7.6 13.2L.6 15.7z" fill="#34A853" />
      <path d="M4.4 22.3l3.8-7.4h14.8l-3.8 7.4z" fill="#4285F4" />
    </template>
    <circle v-else cx="12" cy="12" r="10" fill="currentColor" opacity=".3" />
  </svg>
</template>
