# STRUCTURE.md — Estrutura Real do Repositório souza.l

Documentação da estrutura de pastas **como existe atualmente** (não idealizada). Atualize quando a estrutura mudar.

---

## Raiz

```
souza.l/
├── .env.local                 # Segredos locais (NÃO versionado)
├── .env.example               # Template de variáveis (versionado)
├── .gitignore
├── AGENTS.md                  # Regras para agentes de IA
├── CLAUDE.md                  # Guia do projeto (regras de produto/segurança)
├── README.md                  # Documentação pública (Next.js padrão)
├── STRUCTURE.md               # Este arquivo
├── eslint.config.mjs
├── next.config.ts
├── package.json
├── package-lock.json
├── postcss.config.mjs
├── playwright.config.ts       # Config Playwright (raiz)
└── tsconfig.json              (se existir)
```

---

## `app/` — App Router (Next.js 16)

```
app/
├── api/
│   ├── documents/
│   │   └── [id]/
│   │       └── download/
│   │           └── route.ts          # Download de laudos (signed URL)
│   └── services/
│       └── [id]/
│           └── export/
│               └── route.ts          # Export TXT/JSON do serviço
├── auth/
│   └── callback/
│       └── route.ts                  # Callback OAuth Supabase
├── cadastro/
│   ├── actions.ts                    # Server action: signup
│   ├── page.tsx
│   └── signup-form.tsx
├── login/
│   ├── actions.ts                    # Server action: login
│   ├── login-form.tsx
│   └── page.tsx
├── recuperar-senha/
│   ├── actions.ts
│   ├── page.tsx
│   └── reset-form.tsx
├── atualizar-senha/
│   ├── actions.ts
│   ├── page.tsx
│   └── update-form.tsx
├── convite/
│   └── [token]/
│       ├── accept-form.tsx
│       ├── actions.ts
│       └── page.tsx
├── convites/
│   ├── actions.ts
│   └── page.tsx
├── pedidos/
│   └── novo/
│       ├── actions.ts
│       ├── invite-form.tsx
│       └── page.tsx
├── clientes/
│   └── page.tsx                      # Lista de clientes (worker)
├── servicos/
│   └── [id]/
│       ├── actions.ts                # addRecord, changeStatus
│       ├── laudo-actions.ts          # requestLaudo, generateLaudoAction
│       ├── page.tsx                  # Página principal do serviço
│       └── record-form.tsx           # Form de registro (cliente/worker)
├── notificacoes/
│   ├── actions.ts
│   └── page.tsx
├── painel/
│   ├── actions.ts                    # logout
│   └── page.tsx                      # Dashboard (cliente + worker)
├── agenda/
│   ├── actions.ts
│   ├── page.tsx
│   ├── nova/
│   │   ├── page.tsx
│   │   └── visit-form.tsx
│   └── [id]/
│       ├── page.tsx
│       ├── reschedule-form.tsx
│       └── calendario/
│           └── route.ts
├── admin/
│   └── page.tsx                      # Placeholder (redireciona worker)
├── p/
│   └── [slug]/
│       └── page.tsx                  # Perfil público do profissional
├── globals.css
├── layout.tsx
└── page.tsx                          # Landing page pública
```

---

## `components/` — Componentes React

```
components/
├── ui/                               # Genéricos (Button, Input, Modal, Card, StatusBadge)
│   └── (arquivos não listados individualmente)
├── servicos/
│   └── service-list.tsx              # Lista de serviços (usada no painel)
├── clientes/
│   └── (não implementado ainda)
├── notificacoes/
│   ├── notification-item.tsx
│   └── notifications-badge.tsx
├── gallery/
│   ├── lightbox.tsx
│   └── photo-gallery.tsx
├── client-code/
│   └── copy-button.tsx
├── agenda/
│   ├── visit-status-dot.tsx
│   └── visit-question.tsx
├── profile-card.tsx
├── whatsapp-button.tsx
└── copy-button.tsx
```

---

## `lib/` — Lógica Compartilhada (Server/Client)

```
lib/
├── supabase/
│   ├── client.ts                     # createBrowserClient (browser)
│   ├── server.ts                     # createServerClient (server actions)
│   └── proxy.ts                      # Refresh token via proxy
├── auth/
│   ├── get-user.ts                   # getCurrentUser() — lê profiles.role
│   ├── require-role.ts               # Helper para exigir role específica
│   └── safe-next.ts                  # Utilitários Next.js seguros
├── services/
│   ├── detail.ts                     # getService, listRecords, getCounterpart
│   ├── list.ts                       # listMyServices
│   ├── requests.ts                   # listPendingRequests
│   ├── format.ts                     # formatDateTime, formatCurrency
│   └── status.ts                     # STATUS_LABELS, STATUS_DOT, RECORDS_OPEN, STATUS_ACTIONS
├── clients/
│   └── list.ts                       # listMyClients
├── notifications/
│   └── count.ts                      # countUnreadNotifications
├── documents/
│   ├── laudo-template.tsx            # Template React do PDF (React-PDF)
│   ├── generate-laudo.tsx            # Geração server-side do laudo
│   ├── list.ts                       # listServiceDocuments
│   └── export-service.ts             # Export TXT/JSON
├── agenda/
│   ├── form.ts
│   ├── ics.ts
│   ├── phone.ts
│   ├── time.ts
│   ├── types.ts
│   └── visits.ts
├── ui/
│   └── colors.ts
├── worker-info.ts                    # Info do profissional (landing page)
└── (outros arquivos utilitários)
```

---

## `supabase/` — Banco de Dados e Funções

```
supabase/
├── migrations/
│   ├── 20261002000001_base_schema.sql
│   ├── 20261002000002_access_rules.sql
│   ├── 20261003000003_worker_profiles.sql
│   ├── 20261004000005_service_invites.sql
│   ├── 20261004000006_service_page_support.sql
│   ├── 20261004000007_storage_bucket.sql
│   ├── 20261004000008_storage_policies.sql
│   ├── 20261004000009_service_files_insert_policy.sql
│   ├── 20261004000010_service_files_checks.sql
│   ├── 20261005000011_service_files_caption.sql
│   ├── 20261009000012_quote_visits_schema.sql
│   ├── 20261009000013_service_files_caption_grant.sql
│   ├── 20261009000001_retention_cleanup.sql
│   ├── 20261009000014_fix_service_history_unique.sql
│   ├── 20261010000001_remove_test_set_role.sql
│   └── 20261011000001_retention_12_months.sql
├── functions/                        # Edge Functions (existente, não no CLAUDE.md original)
│   └── (arquivos não listados)
└── config.toml                       (se existir)
```

---

## `tests/` — Testes E2E (Playwright)

```
tests/
├── package.json                      # Projeto Playwright separado
├── playwright.config.ts              # (se existir, senão usa raiz)
├── e2e/
│   └── fluxo-completo.spec.ts        # Fluxo V1 completo
├── README.md                         # Documentação de execução e isolamento
├── .env.example                      # Template variáveis de teste
└── .env.test                         # Variáveis reais (NÃO versionado)
```

---

## `public/` — Assets Estáticos

```
public/
├── file.svg
├── globe.svg
├── next.svg
├── vercel.svg
└── window.svg
```

---

## `types/` — Tipos TypeScript Compartilhados

*(Pasta existe conforme CLAUDE.md; verificar se há arquivos)*

---

## `validations/` — Validações (Zod/outros)

*(Pasta existe conforme CLAUDE.md; verificar se há arquivos)*

---

## `utils/` — Utilitários Gerais

*(Pasta existe conforme CLAUDE.md; verificar se há arquivos)*

---

## Tabelas do Banco (resumo do schema)

| Tabela | Propósito | RLS |
|--------|-----------|-----|
| `profiles` | Usuários (client, worker, admin) | ✅ Próprio perfil |
| `services` | Serviços centrais | ✅ Participantes |
| `service_requests` | Pedidos de serviço | ✅ Participantes |
| `service_records` | Registros (cliente/worker) | ✅ Participantes + autor próprio |
| `service_files` | Arquivos (fotos, docs) | ✅ Participantes |
| `notifications` | Notificações internas | ✅ Próprias |
| `service_documents` | Laudos, exports | ✅ Participantes |
| `service_history_summary` | Resumo histórico (retenção) | ❌ Sem policy = só server |
| `audit_logs` | Auditoria | ❌ Sem policy = só server |
| `worker_profiles` | Perfil público do profissional | ✅ Publicados + próprio |
| `service_invites` | Convites por link | ✅ Worker próprio |
| `quote_visits` | Visitas de orçamento (agenda) | ✅ Worker próprio |

---

## Buckets Storage

| Bucket | Público | Limite | Tipos | Políticas |
|--------|---------|--------|-------|-----------|
| `service-files` | ❌ | 10 MB | image/jpeg, png, webp | Insert/Select por `service_id` + status |

---

## Variáveis de Ambiente (produção/dev)

| Variável | Obrigatória | Onde usada |
|----------|-------------|------------|
| `NEXT_PUBLIC_SUPABASE_URL` | ✅ | `lib/supabase/client.ts`, `server.ts` |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | ✅ | `lib/supabase/client.ts`, `server.ts` |
| `NEXT_PUBLIC_SITE_URL` | ✅ | `app/page.tsx`, laudo-actions |
| `SUPABASE_SERVICE_ROLE_KEY` | Server only | Edge Functions, admin scripts |

---

## Variáveis de Teste (`tests/.env.test`)

| Variável | Obrigatória | Descrição |
|----------|-------------|-----------|
| `NEXT_PUBLIC_SUPABASE_URL` | ✅ | URL do projeto Supabase **dedicado a testes** |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | ✅ | Anon key do projeto de testes |
| `TEST_SUPABASE_PROJECT_ID` | ✅ | Project ID (ex.: `abcdefgh123456`) — barreira de segurança |
| `NEXT_PUBLIC_SITE_URL` | ✅ | `http://localhost:3000` |
| `BASE_URL` | ✅ | `http://localhost:3000` |
| `WORKER_EMAIL` | ✅ | Email do worker de testes (role=worker no projeto de testes) |
| `WORKER_PASSWORD` | ✅ | Senha do worker de testes |

---

## Observações Importantes

1. **`supabase/functions/` existe** mas não estava listado no `CLAUDE.md` original — Edge Functions para retenção/limpeza.
2. **Pastas `types/`, `validations/`, `utils/`** referenciadas no CLAUDE.md podem estar vazias ou não existir fisicamente — verificar antes de usar.
3. **`app/clientes/[id]/page.tsx` não existe** — detalhe do cliente pendente (ver CLAUDE.md ordem de desenvolvimento).
4. **`app/admin/` é placeholder** — redireciona worker; dashboard admin real não implementado.
5. **Testes E2E** usam `playwright.config.ts` na raiz; `tests/package.json` é projeto separado para dependências de teste.

---

*Atualizado: 2026-10-12 — Reflete estado real do repositório no `git status` e inspeção de arquivos.*