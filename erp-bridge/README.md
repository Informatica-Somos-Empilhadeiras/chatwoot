# erp-bridge — Espelho read-only ERP (Mais Pratico) → Chatwoot

Microserviço independente que mostra as **Ordens de Servico** do contato **dentro da conversa do Chatwoot**, via **Dashboard App** (iframe no painel lateral).

Princípios de arquitetura (combinados com o time):
- **Espelha, não guarda.** Nada é persistido no Chatwoot. O serviço busca ao vivo na API do ERP.
- **Bom-cidadão com o ERP.** Cache curto em memória (TTL configurável): várias aberturas de painel = no máximo 1 chamada por TTL. Timeout + 1 retry com backoff + "stale-while-error". User-Agent identificável (`somos-chatwoot-bridge`) — **não mascaramos tráfego**.
- **Leve.** Postgres/Redis do Chatwoot não são tocados; o trabalho fica aqui.

## Rodar

```bash
cd erp-bridge
cp .env.example .env
npm install
npm start           # sobe em http://localhost:4000 (MOCK=true por padrao)
```

Teste rápido (modo mock, sem ERP):

```bash
curl "http://localhost:4000/api/os?codigoCliente=716"
curl "http://localhost:4000/api/os?os=951"
```

Para apontar no ERP real: no `.env`, `MOCK=false`, preencha `ERP_DEVICE_ID` (pegue um válido no DevTools do dashboard) e confira `ERP_EMPRESAS`.

## Registrar no Chatwoot (Dashboard App)

Super Admin / Conta → **Integrações → Apps do Dashboard** → novo app apontando para a URL pública deste serviço (ex.: `https://erp-bridge.suaempresa.com.br/panel.html`). O Chatwoot embute no painel da conversa e envia o contexto do contato via `postMessage`.

## Casamento contato ↔ OS

O `valoresDash` **não retorna CNPJ/telefone** — só `CodigoCliente` e `Nome`. Então:
- **Confiável:** grave o `CodigoCliente` do ERP no contato como atributo custom `erp_codigo_cliente`. O painel casa por ele.
- **Reforço:** busca por nome (aproximada) e busca manual por nº de OS / nome.

## Status e próximas fases

- [x] **Fase 1 (esta):** espelho read-only de OS (API `valoresDash`), com cache e matching.
- [ ] **Fase 2:** orçamentos — depende de **capturar o endpoint de orçamento** (não apareceu no HAR) ou leitura via banco on-prem.
- [ ] **Fase 3:** escrita (criar/editar OS e orçamento) — depende de **endpoint de escrita sancionado pela Inntegra**. Ver `docs/`.
- [ ] **Fase 4:** agendamento → Teams (Microsoft Graph) / Google Agenda + aviso aos envolvidos (cliente via Chatwoot/WhatsApp).

> Este serviço só faz **GET** no ERP. Qualquer escrita será adicionada apenas sobre endpoint autorizado.
