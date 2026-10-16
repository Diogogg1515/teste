# AGENTS.md — Regras de Atuação para Agentes de IA no souza.l

Este documento define as regras obrigatórias para qualquer agente de IA operando neste repositório. Leia integralmente antes de iniciar qualquer tarefa.

---

## 1. Hierarquia e Consulta Obrigatória

1. **CLAUDE.md** é a fonte de verdade do produto (regras de negócio, stack, segurança, ordem de desenvolvimento).
2. Este **AGENTS.md** complementa com regras de processo, Git, segurança operacional e limites de atuação.
3. Em caso de conflito, **CLAUDE.md prevalece** para regras de produto/segurança; **AGENTS.md prevalece** para processo de trabalho dos agentes.
4. Antes de qualquer tarefa, releia ambos os arquivos. Não presuma que conhece o estado atual.

---

## 2. Preservação de Alterações Preexistentes

- `git status` e `git diff` devem ser verificados **no início** de cada sessão.
- **Nunca** descarte, sobrescreva ou reescreva alterações staged/unstaged do usuário sem autorização explícita.
- Ao editar arquivos, use `Edit` (não `Write`) para preservar histórico e contexto.
- Commits do usuário são intocáveis; novos commits só com autorização.

---

## 3. Comandos Destrutivos e Operações Remotas

**Proibidos sem autorização explícita do usuário:**

| Categoria | Exemplos |
|-----------|----------|
| Dados remotos | `DELETE`, `TRUNCATE`, `UPDATE` em tabelas Supabase; upload/deleção no Storage; execução de RPCs que mutam estado |
| Migrações | `supabase migration up`, `db push`, aplicação de SQL DDL/DML |
| Build/Deploy | `vercel deploy`, `npm run build` em produção, push para branches protegidas |
| Git destrutivo | `git reset --hard`, `git push --force`, `git rebase -i` em histórico compartilhado |
| Testes E2E | `npm test` / `playwright test` contra ambiente não isolado (ver Fase 2 de testes) |

**Permitidos (leitura/validação):**
- `git status`, `git diff`, `git log`
- `npm run lint`, `npx tsc --noEmit`
- Leitura de arquivos, `grep`, `glob`
- SQL `SELECT` via MCP/ferramentas de leitura

---

## 4. Arquivos Críticos — Regras Específicas

| Tipo | Regra |
|------|-------|
| **Migrations** (`supabase/migrations/*.sql`) | Nunca modificar migrations já aplicadas. Novas migrations: nome incremental, descrição clara, idempotentes quando possível. |
| **RLS / Policies** | Toda tabela nova **deve** ter `enable row level security` e policies antes de qualquer código frontend. Testar isolamento (cliente A não acessa serviço do cliente B). |
| **RPCs / Funções DB** | `security definer`, `set search_path = ''`, revogar execução de `public, anon, authenticated` por padrão; grant apenas para roles necessárias. |
| **Autenticação** | Só via Supabase Auth. Papel (`role`) **sempre** lido de `profiles.role` no server (`getCurrentUser`). Nunca confiar em metadata do cliente. |
| **Storage** | Bucket `service-files` **privado**. Políticas por `service_id` na pasta. Arquivos acessados apenas via signed URLs. |
| **Segredos** | `SUPABASE_SERVICE_ROLE_KEY` **apenas** em variáveis de ambiente server-side. Nunca em `NEXT_PUBLIC_*`, nunca no navegador, nunca no Git. `.env*` no `.gitignore`. |

---

## 5. Padrões de Código e Arquitetura

- **Stack**: Next.js 16 (App Router) + React 19 + TypeScript + Tailwind CSS + Supabase (Auth, Postgres, Storage, RLS).
- **Server Actions** para mutações; `lib/supabase/server.ts` para cliente server; `lib/supabase/client.ts` para cliente browser.
- **Validação server-side** obrigatória (tamanhos, tipos, estado do serviço, UUIDs). Frontend valida UX, backend valida segurança.
- **Componentes**: UI genéricos em `components/ui/`; negócio em `components/servicos/`, `components/clientes/`, etc.
- **Tipos**: `types/` para tipos compartilhados; inferir do Supabase quando possível.
- **Nomenclatura**: PascalCase componentes, camelCase funções/variáveis, kebab-case arquivos/pastas, `snake_case` colunas SQL.

---

## 6. Testes, Lint, TypeScript, Build

| Comando | Propósito |
|---------|-----------|
| `npm run lint` | ESLint (Next.js config) — deve passar sem erros |
| `npx tsc --noEmit` | Type-check — deve passar sem erros |
| `npm run build` | Build de produção — validar antes de deploy |
| `npm test` | Playwright E2E — **só** com ambiente isolado configurado (ver `tests/README.md`) |

- Testes unitários: não configurados; adicionar se necessário com `vitest` ou `jest`.
- Testes E2E: `tests/e2e/` — exigem projeto Supabase dedicado, variáveis em `tests/.env.test`, barreira de segurança ativa.

---

## 7. Trabalho Paralelo, Branches e Conflitos

- **Uma tarefa por branch** — nome: `tipo/descricao-curta` (ex.: `feat/laudo-pdf`, `fix/rls-policies`).
- **Não trabalhar na `main`** — sempre branch nova a partir de `origin/main` atualizada.
- **Agentes paralelos**: cada um em branch própria; comunicação via PR/comentários, não sobrescrita de arquivos.
- **Conflitos**: resolver localmente antes de PR; não forçar push.
- **PRs**: descrição clara, referenciar issue/tarefa, checklist de teste manual (conforme CLAUDE.md).

---

## 8. Distinção Obrigatória: Planejamento vs. Execução vs. Verificação

Em toda resposta final, apresente claramente:

| Seção | Conteúdo |
|-------|----------|
| **Planejado** | O que seria feito (abordagem, arquivos alvo) |
| **Executado** | Arquivos realmente criados/modificados, com diff resumido |
| **Verificado** | Comandos rodados (`lint`, `type-check`), leituras de confirmação, testes manuais simulados |
| **Riscos Pendentes** | O que depende de ação humana, configuração manual, ou decisão de produto |

Não misture intenção com realidade. "Vou criar X" ≠ "Criei X".

---

## 9. Formato do Relatório Final

Ao concluir uma tarefa, apresente:

```markdown
## Arquivos Modificados
- `caminho/arquivo.ts` — criado/modificado — justificativa

## Resumo das Regras/Alterações
- Regra 1: ...
- Regra 2: ...

## Complementaridade AGENTS.md ↔ CLAUDE.md
- AGENTS.md foca em processo/segurança operacional
- CLAUDE.md foca em produto/segurança de dados
- Referências cruzadas nas seções relevantes

## Estrutura Documentada ↔ Real
- Pastas listadas em STRUCTURE.md conferidas com `ls -la`
- Diferenças anotadas (ex.: `supabase/functions/` não previsto no CLAUDE.md)

## Verificações Realizadas
- `npm run lint` — OK
- `npx tsc --noEmit` — OK
- Leitura de arquivos modificados — confirmado

## Não Verificado / Pendente
- Testes E2E (ambiente não configurado)
- Deploy (não autorizado)
- Migrações (não aplicadas)
```

---

## 10. Limites Rígidos — Nunca Faça

- ❌ Inventar regras de produto não documentadas no CLAUDE.md
- ❌ Alterar schema do banco sem migration versionada
- ❌ Desabilitar RLS ou policies "temporariamente"
- ❌ Compartilhar/printar segredos, tokens, chaves, cookies
- ❌ Assumir que `localhost` isola o backend
- ❌ Executar testes E2E sem barreira de isolamento ativa
- ❌ Fazer commit/push sem autorização
- ❌ Apagar arquivos do usuário (`.env.local`, relatórios, docs)

---

*Este documento deve ser lido em conjunto com `CLAUDE.md` e `STRUCTURE.md`.*
*Última atualização: 2026-10-12*