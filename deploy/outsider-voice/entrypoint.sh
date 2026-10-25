#!/bin/bash
# OUTSIDER: central de telefonia (Entrega 22). Busca a configuração no Chatwoot, sobe o Asterisk e, a cada
# 30 s, confere se a configuração mudou (recarrega na hora) e conta ao Chatwoot como está: registro na
# operadora e ramais conectados.
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

stop() {
  log "parando"
  "$ASTERISK" -rx "core stop now" >/dev/null 2>&1
  exit 0
}
trap stop TERM INT

touch "$CONF/pjsip_generated.conf" "$CONF/extensions_generated.conf"
sync_file pjsip pjsip_generated.conf
sync_file extensions extensions_generated.conf

"$ASTERISK" -f -U asterisk -G asterisk -vvv &
PID=$!
log "Asterisk no ar (pid ${PID})"

while kill -0 "$PID" 2>/dev/null; do
  sleep "$INTERVAL" & wait $!
  sync_file pjsip pjsip_generated.conf && "$ASTERISK" -rx "module reload res_pjsip.so" >/dev/null
  sync_file extensions extensions_generated.conf && "$ASTERISK" -rx "dialplan reload" >/dev/null
  report
done
wait "$PID"
