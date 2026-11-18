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

## Escrita de campos de OS (parcial, confirmada por captura)

Endpoints reais capturados do app oficial (edição de OS existente). Habilite com `WRITE_ENABLED=true`.

| Operação | Endpoint | Body |
|---|---|---|
| Trocar substatus | `PUT /KanbanOrdemServico/api/UpdateSubStatusOS/{CodigoOS}` + `PUT .../GravaHistoricoSubStatusOS/{CodigoOS}` | `{SubStatus, listaEmpresas, Empresa}` / `{SubStatusAntigo, SubStatusNovo, listaEmpresas, idUsuario, Empresa}` |
| Atualizar defeitos | `PUT /KanbanOrdemServico/api/UpdateDefeitos/{CodigoOS}` | `{Defeitos, listaEmpresas, Empresa}` |

Rotas do bridge (gated por `WRITE_ENABLED`):
- `PUT /api/os/:codigo/substatus` → `{subStatusNovo, subStatusAntigo, empresa}` (faz o par Update + GravaHistorico)
- `PUT /api/os/:codigo/campo/:campo` → `{valor, empresa}` (campos confirmados; hoje: `Defeitos`)

> **Limite conhecido:** criar/editar a OS inteira e excluir OS **não** existem nesta API web — só no sistema desktop (que escreve direto no MySQL). Outros campos (`Observacoes`, `Previsao`, `Tecnico`…) têm cada um seu `Update<Campo>`; o nome exato precisa ser **confirmado por captura** antes de entrar em `src/erpWrite.js` (a nomenclatura varia: `UpdateSubStatusOS` vs `UpdateDefeitos`). **Teste sempre numa OS segura/homologação antes de produção.**

## Status e próximas fases

- [x] **Fase 1:** espelho read-only de OS (`valoresDash`), com cache e matching.
- [x] **Fase 3a:** escrita de campos de OS existente (substatus, defeitos) — confirmada por captura, gated.
- [ ] **Fase 2:** orçamentos — endpoint encontrado: `cotacaoDesempenho/api/valoresDash` (`CodigoOrcamento`, `OrdemServico`, `Status`, `ValorTotal`).
- [ ] **Fase 3b:** mais campos de update (confirmar cada endpoint por captura); criar/excluir OS depende do desktop ou de endpoint sancionado da Inntegra.
- [ ] **Fase 4:** agendamento → Teams (Microsoft Graph) / Google Agenda + aviso aos envolvidos (cliente via Chatwoot/WhatsApp).
