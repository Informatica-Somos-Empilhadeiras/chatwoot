// OUTSIDER: números e tempos do telefone na tela (Entrega 22): "(62) 99999-8888", "0800 123 4567", "3:07".
export const formatPhone = value => {
  let digits = String(value || '').replace(/\D/g, '');
  if (digits.length <= 4) return digits;
  if (/^(0800|0300)\d{7}$/.test(digits)) {
    return `${digits.slice(0, 4)} ${digits.slice(4, 7)} ${digits.slice(7)}`;
  }
  if ([12, 13].includes(digits.length) && digits.startsWith('55')) {
    digits = digits.slice(2);
  }
  if ([11, 12].includes(digits.length) && digits.startsWith('0')) {
    digits = digits.slice(1);
  }
  if (digits.length === 11) {
    return `(${digits.slice(0, 2)}) ${digits.slice(2, 7)}-${digits.slice(7)}`;
  }
  if (digits.length === 10) {
    return `(${digits.slice(0, 2)}) ${digits.slice(2, 6)}-${digits.slice(6)}`;
  }
  if (digits.length === 8) return `${digits.slice(0, 4)}-${digits.slice(4)}`;
  return digits;
};

export const formatDuration = totalSeconds => {
  const seconds = Math.max(0, Math.round(totalSeconds || 0));
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const rest = String(seconds % 60).padStart(2, '0');
  if (hours) return `${hours}:${String(minutes).padStart(2, '0')}:${rest}`;
  return `${minutes}:${rest}`;
};

// tempo somado do mês: "11 h 39 min" ou "45 min"
export const formatTalkTime = totalSeconds => {
  const minutes = Math.round((totalSeconds || 0) / 60);
  const hours = Math.floor(minutes / 60);
  return hours ? `${hours} h ${minutes % 60} min` : `${minutes} min`;
};
