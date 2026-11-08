// OUTSIDER: visualizador de documentos dentro do Chatwoot, só para ler (FileViewer.vue, montado uma vez no
// OutsiderGlobal.vue). openFileViewer recebe o arquivo pronto (Teams já traz o endereço da Microsoft);
// openAttachmentInViewer pede ao servidor o endereço temporário de um anexo de conversa.
// file: { name, extension, size, kind: pdf|office|text|image|video|none, reason, viewUrl, downloadUrl, editUrl }
import { reactive } from 'vue';
import FileViewsAPI from 'dashboard/api/outsider/fileViews';
import {
  extensionOf,
  fileNameOf,
} from 'dashboard/helper/outsider/documentFile';

export const fileViewer = reactive({
  open: false,
  loading: false,
  error: '',
  file: null,
});

let ticket = 0;

export const closeFileViewer = () => {
  ticket += 1;
  Object.assign(fileViewer, {
    open: false,
    loading: false,
    error: '',
    file: null,
  });
};

export const openFileViewer = file => {
  ticket += 1;
  Object.assign(fileViewer, { open: true, loading: false, error: '', file });
};

// abre já com o nome na tela e completa quando o servidor responde
export const openFileViewerWith = async (base, loader) => {
  ticket += 1;
  const mine = ticket;
  Object.assign(fileViewer, {
    open: true,
    loading: true,
    error: '',
    file: { ...base },
  });
  try {
    const file = await loader();
    if (mine === ticket)
      Object.assign(fileViewer, { loading: false, file: { ...base, ...file } });
  } catch (error) {
    if (mine !== ticket) return;
    Object.assign(fileViewer, {
      loading: false,
      error: error?.response?.data?.error || 'load',
    });
  }
};

export const openAttachmentInViewer = attachment => {
  const base = {
    name: fileNameOf(attachment),
    extension: extensionOf(attachment),
    size: attachment.fileSize ?? attachment.file_size ?? 0,
    downloadUrl: attachment.dataUrl || attachment.data_url || '',
    kind: 'none',
  };
  return openFileViewerWith(base, async () => {
    const { data } = await FileViewsAPI.show(attachment.id);
    return {
      name: data.name || base.name,
      extension: data.extension || base.extension,
      size: data.size ?? base.size,
      kind: data.kind,
      reason: data.reason,
      viewUrl: data.view_url,
      downloadUrl: data.download_url || base.downloadUrl,
    };
  });
};
