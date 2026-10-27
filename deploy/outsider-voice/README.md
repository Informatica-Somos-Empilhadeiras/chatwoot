# Central de telefonia (Asterisk) do CRM

Esta pasta tem a central de ligações do CRM. Ela roda no mesmo servidor do Chatwoot, em um contêiner, e:

- liga o telefone do navegador dos vendedores (ramais 201, 202...) à operadora;
- recebe a configuração pronta do Chatwoot a cada 30 segundos: dados da operadora, números e ramais
  (Telefonia > Configurações, no menu lateral). Não há nada para editar aqui;
- pergunta ao Chatwoot, a cada ligação, para quem tocar ou com qual número sair, e avisa quando atendeu e
  quando terminou (Telefonia > Painel e Ligações).

```
navegador do vendedor ──wss──> Cloudflare ──> central :8088 (WebSocket)
navegador do vendedor <──áudio UDP 10000-10099──> central
operadora (SIP 5060 + áudio) <──> central ──http──> Chatwoot (127.0.0.1:3000)
```

## 1. O que pedir à operadora

- **Tronco SIP** (não um PABX na nuvem), com áudio G.711 (PCMA/alaw ou PCMU/ulaw).
- **Autenticação**: usuário e senha (registro) ou pelo IP do servidor. Se for pelo IP, informe `69.6.250.129`.
- **Dados da conta**: servidor (domínio ou IP), porta, transporte (UDP ou TCP), usuário e senha.
- **Endereços IP** de onde eles mandam as ligações (sinalização e áudio).
- **Números (DID)** de cada estado. Peça para **poder sair com qualquer um dos números** (escolher o número
  de origem/BINA em cada ligação), porque cada vendedor liga com o número do seu estado.
- **Formato de discagem**: DDD + número, 0 + DDD + número, ou 55 + DDD + número.

Quando chegar o e-mail com os dados, cole o texto em **Telefonia > Configurações > Central e ramais > Dados da operadora**
e clique em **Preencher com o texto**. Confira os campos e salve.

## 2. Token da central

No servidor, gere um token e coloque no `.env.production` do Chatwoot:

```bash
cd /opt/apps/chatwoot
echo "OUTSIDER_VOICE_TOKEN=$(openssl rand -hex 32)" >> .env.production
```

Recrie o Chatwoot para ele ler o token: `docker compose up -d rails sidekiq`.

## 3. Contêiner da central

Acrescente ao `docker-compose.yaml` do Chatwoot. Troque `1` pelo número da conta: ele aparece em
Telefonia > Configurações, no item "VOICE_URL".

```yaml
  central:
    build: https://github.com/Informatica-Somos-Empilhadeiras/chatwoot.git#feat/tudo-junto:deploy/outsider-voice
    network_mode: host
    restart: unless-stopped
    env_file: .env.production
    environment:
      VOICE_URL: http://127.0.0.1:3000/outsider/voice/central/1
    logging:
      options:
        max-size: 10m
        max-file: '3'
```

Notas sobre esse bloco:

- **`network_mode: host`**: a central usa as portas do servidor direto, sem a rede do Docker no meio do áudio.
- **Porta 3000 do Chatwoot**: a central fala com o Chatwoot por `127.0.0.1:3000`, então essa porta precisa
  estar publicada para o próprio servidor. Por exemplo, `127.0.0.1:3000:3000` no serviço `rails`.
- **Sem acesso ao GitHub pelo servidor**: copie esta pasta para lá e use `build: ./outsider-voice`.

Suba a central e veja o começo do log:

```bash
docker compose up -d --build central
docker compose logs -f central   # deve mostrar "pjsip atualizado" e "Asterisk no ar"
```

## 4. Endereço para o navegador (Cloudflare)

O telefone do navegador precisa de um endereço `wss://` com certificado. Use o mesmo túnel da Cloudflare do
Chatwoot.

1. **No túnel**, crie um nome público, por exemplo `voz.suaempresa.com.br`, apontando para
   `http://host.docker.internal:8088`.
   - No painel da Cloudflare: Zero Trust > Networks > Tunnels > Public hostname.
   - Ou no `config.yml` do cloudflared, numa regra de `ingress`.
2. **No serviço do cloudflared** (no compose), acrescente:

   ```yaml
       extra_hosts:
         - host.docker.internal:host-gateway
   ```

3. **No Chatwoot**, em Telefonia > Configurações, em "Endereço da central para o navegador", coloque
   `wss://voz.suaempresa.com.br/ws`.

## 5. Firewall (ufw)

```bash
# WebSocket só para o cloudflared (rede interna do Docker), nunca para a internet
sudo ufw allow from 172.16.0.0/12 to any port 8088 proto tcp
# áudio dos navegadores e da operadora (já liberado)
sudo ufw allow 10000:10099/udp
# SIP só da operadora: um comando para cada IP que ela informar
sudo ufw allow from IP_DA_OPERADORA to any port 5060 proto udp
```

Se a operadora usar TCP, troque `udp` por `tcp` na última regra.

## 6. Configurar no CRM e testar

Em **Telefonia > Configurações** (menu lateral):

1. Ligue a **Telefonia**.
2. Preencha:
   - **IP público** do servidor: `69.6.250.129`;
   - **endereço `wss://`** do passo 4;
   - **dados da operadora**;
   - **números por estado**;
   - **ramal e estado** de cada vendedor.
3. Salve.
4. Em até 30 segundos, o quadro do topo mostra **Central conectada** e **Registrada na operadora**.

Para testar, cada vendedor:

- vê o **telefone** no rodapé do menu lateral, com ponto verde quando está pronto;
- usa **Testar áudio**: ouve a própria voz de volta, o que confere microfone, fone e internet;
- liga para um colega pelo ramal (ex.: 202) e depois para um celular.

As metas de ligação ficam em **Telefonia > Configurações > Metas de ligação**. O acompanhamento fica em
**Telefonia > Painel** (metas, números do dia e do mês, quem está em ligação) e **Telefonia > Ligações**
(perdidas para retornar e histórico).

Na ligação, **Conferência** inclui até mais 4 pessoas (ramal ou número de fora). Quem incluiu junta as vozes
no próprio navegador, então a central não muda: se essa pessoa desligar, a conferência acaba para todos.
**Gravar** grava a conversa no navegador e guarda o arquivo na ligação do cliente (Telefonia > Ligações),
cerca de 15 MB por hora; dá para desligar em Telefonia > Configurações. O painel e os relatórios usam o fuso
escolhido em Telefonia > Configurações (Brasília se ninguém mudar).

## Problemas comuns

| O que aparece | O que fazer |
| --- | --- |
| "A central ainda não se conectou" | Veja `docker compose logs central`. Confira `VOICE_URL` (número da conta) e se o token é o mesmo do Chatwoot. |
| "Falta o OUTSIDER_VOICE_TOKEN" | Faltou o passo 2, ou o Chatwoot não foi recriado depois dele. |
| Telefone com ponto vermelho "Sem conexão com a central" | Confira o endereço `wss://` (passo 4) e a regra da porta 8088 no ufw. |
| Liga, mas sem áudio | Confira as portas 10000-10099/udp e o IP público em Telefonia > Configurações. |
| "A operadora recusou o usuário ou a senha" | Confira usuário, usuário de autenticação e senha com a operadora. |
| Ligação da operadora não chega | Libere o IP da operadora na porta 5060 e confira os IPs em Telefonia > Configurações. |

Comandos úteis dentro da central:

```bash
docker compose exec central asterisk -rx "pjsip show contacts"        # ramais conectados
docker compose exec central asterisk -rx "pjsip show registrations"   # registro na operadora
docker compose exec central asterisk -rx "core show channels"         # ligações em andamento
```
