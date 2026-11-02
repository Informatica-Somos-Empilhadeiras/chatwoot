# OUTSIDER: central de telefonia (Entrega 22). Asterisk 20 (versão de suporte longo do Ubuntu 24.04) com a
# configuração mínima deste diretório; o resto (operadora, ramais) vem do Chatwoot pelo entrypoint.sh.
# Entrega 26: ffmpeg (áudios das URAs em 8 kHz) e espeak-ng (lê os textos da URA sem a voz da OpenAI).
FROM ubuntu:24.04

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends asterisk asterisk-modules curl ca-certificates \
    ffmpeg espeak-ng \
  && rm -rf /var/lib/apt/lists/* /etc/asterisk/*

COPY asterisk/ /etc/asterisk/
COPY entrypoint.sh /usr/local/bin/central-entrypoint
RUN chmod +x /usr/local/bin/central-entrypoint

ENTRYPOINT ["/usr/local/bin/central-entrypoint"]
