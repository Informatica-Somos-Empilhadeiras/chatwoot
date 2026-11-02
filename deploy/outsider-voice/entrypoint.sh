#!/bin/bash
# OUTSIDER: central de telefonia (Entrega 22). Busca a configuração no Chatwoot, sobe o Asterisk e, a cada
# 30 s, confere se a configuração mudou (recarrega na hora) e conta ao Chatwoot como está: registro na
# operadora e ramais conectados.
#
# Entrega 26: a cada 30 s também traz os áudios das URAs (baixa o áudio ou, sem a voz da OpenAI no Chatwoot, lê
# o texto com o espeak-ng) e, a cada 5 s, manda ao Chatwoot os recados gravados na URA.
#
# VOICE_URL: endereço da central no Chatwoot, ex. http://127.0.0.1:3000/outsider/voice/central/1
# OUTSIDER_VOICE_TOKEN: o mesmo token do .env.production do Chatwoot
set -u

: "${VOICE_URL:?Defina VOICE_URL}"
: "${OUTSIDER_VOICE_TOKEN:?Defina OUTSIDER_VOICE_TOKEN}"
export VOICE_URL VOICE_TOKEN="${OUTSIDER_VOICE_TOKEN}"
CONF="${ASTERISK_CONF:-/etc/asterisk}"
ASTERISK="${ASTERISK_BIN:-asterisk}"
INTERVAL="${SYNC_INTERVAL:-30}"
SOUNDS="${OUTSIDER_SOUNDS:-/var/lib/outsider-voice/sounds}"
VOICEMAIL="/var/spool/asterisk/outsider-voicemail"

log() { echo "[central] $*"; }

# baixa um arquivo do Chatwoot; devolve 0 só quando ele mudou
sync_file() {
  local name="$1" file="$CONF/$2"
  if ! curl -fsS --max-time 10 -H "X-Voice-Token: ${VOICE_TOKEN}" "${VOICE_URL}/${name}" -o "${file}.new"; then
    log "não consegui buscar ${name} no Chatwoot; sigo com a configuração atual"
    rm -f "${file}.new"
    return 1
  fi
  if cmp -s "${file}.new" "${file}"; then
    rm -f "${file}.new"
    return 1
  fi
  mv "${file}.new" "${file}"
  log "${name} atualizado"
  return 0
}

report() {
  local registration extensions
  registration=$("$ASTERISK" -rx "pjsip show registrations" 2>/dev/null | grep -oE 'Registered|Unregistered|Rejected|Stopped|Retrying' | head -1)
  extensions=$("$ASTERISK" -rx "pjsip show contacts" 2>/dev/null \
    | awk '$1 == "Contact:" && $2 ~ /^[1-5][0-9][0-9]\// && $4 != "Unavail" { split($2, aor, "/"); print aor[1] }' | sort -u | paste -sd, -)
  curl -fsS --max-time 10 -H "X-Voice-Token: ${VOICE_TOKEN}" --data-urlencode "registration=${registration}" \
    --data-urlencode "extensions=${extensions}" "${VOICE_URL}/status" >/dev/null || log "não consegui avisar o Chatwoot"
}

# áudios das URAs: uma linha "nome|audio" ou "nome|tts|texto em base64" por áudio (Outsider::Voice::IvrPrompts).
# Cada áudio vira outsider/<nome>.wav em 8 kHz; o que saiu da lista é apagado.
sync_prompts() {
  local list name kind text tmp keep
  list=$(curl -fsS --max-time 10 -H "X-Voice-Token: ${VOICE_TOKEN}" "${VOICE_URL}/prompts") || return
  keep=" beep "
  while IFS='|' read -r name kind text; do
    [[ "$name" =~ ^[a-f0-9]{20}$ ]] || continue
    keep="${keep}${name} "
    [ -s "$SOUNDS/$name.wav" ] && continue
    tmp=$(mktemp -d)
    if [ "$kind" = "tts" ]; then
      printf '%s' "$text" | base64 -d > "$tmp/text" && espeak-ng -v pt-br -s 150 -f "$tmp/text" -w "$tmp/source" 2>/dev/null
    else
      curl -fsS --max-time 40 -H "X-Voice-Token: ${VOICE_TOKEN}" "${VOICE_URL}/prompt?name=${name}" -o "$tmp/source"
    fi
    if [ -s "$tmp/source" ] && ffmpeg -nostdin -loglevel error -y -i "$tmp/source" -ar 8000 -ac 1 -c:a pcm_s16le "$tmp/out.wav"; then
      mv "$tmp/out.wav" "$SOUNDS/$name.wav" && log "áudio da URA ${name} pronto"
    else
      log "não consegui preparar o áudio ${name}; tento de novo depois"
    fi
    rm -rf "$tmp"
  done <<< "$list"
  for file in "$SOUNDS"/*.wav; do
    [ -e "$file" ] || continue
    name=$(basename "$file" .wav)
    [[ "$keep" == *" $name "* ]] || rm -f "$file"
  done
}

# recados da URA: o arquivo parado há 10 s terminou de gravar. Sai da fila quando o Chatwoot responde (mesmo que
# recuse); falha de rede tenta de novo. Recado esquecido há mais de 7 dias é apagado.
upload_voicemails() {
  local file code
  for file in "$VOICEMAIL"/*.wav; do
    [ -e "$file" ] || continue
    [ $(( $(date +%s) - $(stat -c %Y "$file") )) -ge 10 ] || continue
    code=$(curl -sS --max-time 60 -o /dev/null -w '%{http_code}' -H "X-Voice-Token: ${VOICE_TOKEN}" \
      -F "linkedid=$(basename "$file" .wav)" -F "file=@${file};type=audio/wav" "${VOICE_URL}/voicemail")
    case "$code" in
      2*|4*) rm -f "$file" ;;
      *) log "não consegui enviar o recado $(basename "$file"); tento de novo" ;;
    esac
  done
  find "$VOICEMAIL" -name '*.wav' -mtime +7 -delete
}

stop() {
  log "parando"
  "$ASTERISK" -rx "core stop now" >/dev/null 2>&1
  exit 0
}
trap stop TERM INT

# pasta dos áudios das URAs dentro dos sons do Asterisk (outsider/<nome>), o bipe do recado e a fila de recados
mkdir -p "$SOUNDS" "$VOICEMAIL" /usr/share/asterisk/sounds
ln -sfn "$SOUNDS" /usr/share/asterisk/sounds/outsider
[ -s "$SOUNDS/beep.wav" ] || ffmpeg -nostdin -loglevel error -y -f lavfi -i "sine=frequency=1000:duration=0.4" -ar 8000 -ac 1 -c:a pcm_s16le "$SOUNDS/beep.wav"
chown -R asterisk:asterisk "$VOICEMAIL" "$SOUNDS"

touch "$CONF/pjsip_generated.conf" "$CONF/extensions_generated.conf"
sync_file pjsip pjsip_generated.conf
sync_file extensions extensions_generated.conf
sync_prompts

"$ASTERISK" -f -U asterisk -G asterisk -vvv &
PID=$!
log "Asterisk no ar (pid ${PID})"

(
  while kill -0 "$PID" 2>/dev/null; do
    sleep 5
    upload_voicemails
  done
) &

while kill -0 "$PID" 2>/dev/null; do
  sleep "$INTERVAL" & wait $!
  sync_file pjsip pjsip_generated.conf && "$ASTERISK" -rx "module reload res_pjsip.so" >/dev/null
  sync_file extensions extensions_generated.conf && "$ASTERISK" -rx "dialplan reload" >/dev/null
  sync_prompts
  report
done
wait "$PID"
