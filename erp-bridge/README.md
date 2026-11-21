# erp-bridge — Espelho read-only ERP (Mais Pratico) → Chatwoot

Microserviço independente que mostra as **Ordens de Servico** do contato **dentro da conversa do Chatwoot**, via **Dashboard App** (iframe no painel lateral).

Princípios de arquitetura (combinados com o time):
- **Espelha, não guarda.** Nada é persistido no Chatwoot. O serviço busca ao vivo na API do ERP.
- **Bom-cidadão com o ERP.** Cache curto em memória (TTL configurável): várias aberturas de painel = no máximo 1 chamada por TTL. **Single-flight**: se N painéis abrem com o cache frio, só **1** requisição vai ao ERP (as demais aguardam a mesma). Timeout + 1 retry com backoff + "stale-while-error". User-Agent identificável (`somos-chatwoot-bridge`) — **não mascaramos tráfego**.
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

## Relatório da OS com fotos (igual ao kanban de KPI)

Cada OS no painel tem o link **Relatório**, que abre `relatorio.html` numa aba nova com o mesmo conteúdo do PDF do kanban (cliente/equipamento, serviço, check-in/out, avaliação técnica, produtos e o checklist com as fotos) e o botão **Imprimir / Salvar PDF**. Só leitura, sem gravar nada em disco.

| Rota do bridge | Vem do ERP (GET) |
|---|---|
| `GET /api/os/:codigo/relatorio?empresa=` | `DadosOS_PDF`, `DadosCheckIn_PDF`, `DadosCheckList_PDF`, `DadosProdutosOS_PDF` (`?CodigoOS=&Empresa=`) |
| `GET /api/os/:codigo/imagem/:ref?empresa=` | `getimagemchecklistos/{ref}/{empresa}` — `ref` é o `CaminhoIMG` do checklist (`{CodigoOS}_{n}`) |
| `GET /api/os/:codigo/logo?empresa=` | `download-logo-empresa/{CNPJ do emissor que veio no relatório}` |

- Cache em memória: relatório 5 min por OS (single-flight), imagens 30 min (até 150). Abrir o mesmo relatório várias vezes = 1 ida ao ERP.
- A empresa precisa estar em `ERP_EMPRESAS` e a `ref` tem que ser da própria OS; a ponte recusa qualquer resposta do ERP que não seja imagem. Assim ela não vira proxy aberto do ERP.
- No modo exemplo (`MOCK=true`) o relatório responde 409, porque não há dados de exemplo para ele.

## Escrita de campos de OS (parcial, confirmada por captura)

Endpoints reais capturados do app oficial (edição de OS existente). Habilite com `WRITE_ENABLED=true`.

| Operação | Endpoint | Body |
|---|---|---|
| Trocar substatus | `PUT /KanbanOrdemServico/api/UpdateSubStatusOS/{CodigoOS}` + `PUT .../GravaHistoricoSubStatusOS/{CodigoOS}` | `{SubStatus, listaEmpresas, Empresa}` / `{SubStatusAntigo, SubStatusNovo, listaEmpresas, idUsuario, Empresa}` |
| Atualizar defeitos | `PUT /KanbanOrdemServico/api/UpdateDefeitos/{CodigoOS}` | `{Defeitos, listaEmpresas, Empresa}` |

Rotas do bridge (gated por `WRITE_ENABLED`):
- `PUT /api/os/:codigo/substatus` → `{subStatusNovo, subStatusAntigo, empresa}` (faz o par Update + GravaHistorico)
- `PUT /api/os/:codigo/campo/:campo` → `{valor, empresa}` (campos confirmados; hoje: `Defeitos`)

### Adicionar mais campos sem probing (self-service)

Cada campo tem seu próprio `Update<Campo>` e a nomenclatura varia (`UpdateSubStatusOS` vs `UpdateDefeitos`), então nada é chutado. Para ligar um campo novo:

1. No app oficial, edite **aquele campo** de uma OS com o **DevTools → Network** aberto.
2. Veja o nome do endpoint na requisição `PUT` (ex.: `UpdateObservacoes`).
3. Adicione uma linha no `.env`: `ERP_UPDATE_FIELDS="Observacoes:UpdateObservacoes"` (vírgula separa vários).

Pronto — `PUT /api/os/:cod/campo/Observacoes` passa a funcionar, sem mexer em código. Confira os campos ativos em `GET /healthz` (`camposUpdate`).

> **Limite conhecido:** criar/editar a OS inteira e excluir OS **não** existem nesta API web — só no sistema desktop (que escreve direto no MySQL). **Teste sempre numa OS segura/homologação antes de produção.**

## Status e próximas fases

- [x] **Fase 1:** espelho read-only de OS (`valoresDash`), com cache e matching.
- [x] **Fase 3a:** escrita de campos de OS existente (substatus, defeitos) — confirmada por captura, gated.
- [x] **Relatório da OS com fotos** do checklist (mesmo conteúdo do PDF do kanban de KPI), imprimível.
- [ ] **Fase 2:** orçamentos — endpoint encontrado: `cotacaoDesempenho/api/valoresDash` (`CodigoOrcamento`, `OrdemServico`, `Status`, `ValorTotal`).
- [ ] **Fase 3b:** mais campos de update (confirmar cada endpoint por captura); criar/excluir OS depende do desktop ou de endpoint sancionado da Inntegra.
- [ ] **Fase 4:** agendamento → Teams (Microsoft Graph) / Google Agenda + aviso aos envolvidos (cliente via Chatwoot/WhatsApp).
