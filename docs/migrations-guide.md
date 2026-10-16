# Guia de Migrations — souza.l

## Estado Atual (2026-10-18)

### Migration Canônica Única (APLICAR ESTA)

| Arquivo | Descrição |
|---------|-----------|
| **`20261018000001_retention_final_canonical.sql`** | **CANÔNICA FINAL** - Substitui TODAS as migrations de retenção/limpeza/cron |

### Migrations Base (manter - não mexer)

| Ordem | Arquivo | Descrição |
|-------|---------|-----------|
| 1 | `20261002000001_base_schema.sql` | Schema base (tabelas, FKs, índices) |
| 2 | `20261002000002_access_rules.sql` | RLS policies base |
| 3 | `20261003000003_worker_profiles.sql` | Perfis de trabalhador |
| 4 | `20261004000005_service_invites.sql` | Convites de serviço |
| 5 | `20261004000006_service_page_support.sql` | Suporte página serviço |
| 6 | `20261004000007_storage_bucket.sql` | Bucket storage |
| 7 | `20261004000008_storage_policies.sql` | Policies storage |
| 8 | `20261004000009_service_files_insert_policy.sql` | Insert policy service_files |
| 9 | `20261004000010_service_files_checks.sql` | Checks service_files |
| 10 | `20261005000011_service_files_caption.sql` | Caption service_files |
| 11 | `20261009000013_service_files_caption_grant.sql` | Grant caption |
| 12 | `20261009000014_fix_service_history_unique.sql` | Unique constraint service_number |
| 13 | `20261010000001_remove_test_set_role.sql` | Remove vulnerabilidade set_test_role |
| 14 | `20261013000001_pdf_support.sql` | Suporte PDF/laudos |
| 15 | **`20261018000001_retention_final_canonical.sql`** | **CANÔNICA FINAL** |

---

### Migrations LEGACY (NÃO APLICAR — substituídas pela canônica)

| Arquivo | Motivo |
|---------|--------|
| `20261009000001_retention_cleanup.sql` | Substituída pela canônica (erro: referencia create_service_summary inexistente) |
| `20261011000001_retention_12_months.sql` | Substituída pela canônica |
| `20261013000002_retention_fixed.sql` | Substituída pela canônica |
| `20261015000001_storage_cleanup_queue.sql` | Substituída pela canônica |
| `20261016000001_storage_cleanup_recovery.sql` | Substituída pela canônica |
| `20261017000001_cleanup_services_cron.sql` | Substituída pela canônica (cron está comentado na canônica) |

> **Mantenha no histórico** para rastreabilidade, mas **não execute** em banco novo.

---

### Migration FORA DA V1 (decisão pendente)

| Arquivo | Status |
|---------|--------|
| `20261003000004_bootstrap_quote_visits.sql` | **FORA DA V1** — CLAUDE.md lista "agenda complexa" como fora do escopo |
| `20261009000012_quote_visits_schema.sql` | **FORA DA V1** — Tabelas/funções de agendamento de visitas |

**Decisão recomendada:** Remover código (`rm -rf app/agenda lib/agenda`) e criar migration para dropar `quote_visits`. Ver `docs/decision-quote-visits.md`.

---

## Como Aplicar no BANCO ORIGINAL (Produção)

### Opção A: Script Mestre Único (recomendado)
```bash
# 1. Abra Supabase Dashboard → SQL Editor do projeto ORIGINAL
# 2. Copie TODO o conteúdo de:
#    scripts/cleanup-and-apply-canonical.sql
# 3. Cole no SQL Editor e execute (pode rodar tudo de uma vez)
```

O script mestre faz em ordem:
1. **Verifica/remove vulnerabilidade** `set_test_role`
2. **Audita contas suspeitas** worker/admin
3. **Limpa objetos legados** (triggers, policies antigas)
4. **Aplica canônica completa** (tabela, funções, trigger, grants, constraint)
5. **Verifica tudo** no final

### Opção B: Passo a Passo (se preferir controlar)

**Passo 1 - Vulnerabilidade:**
```sql
-- No SQL Editor
SELECT proname, pg_get_functiondef(oid) FROM pg_proc WHERE proname = 'set_test_role';
-- Se retornar linhas:
REVOKE EXECUTE ON FUNCTION public.set_test_role(uuid, public.user_role) FROM authenticated;
DROP FUNCTION IF EXISTS public.set_test_role(uuid, public.user_role);
```

**Passo 2 - Canônica:**
```sql
-- Copie e execute: supabase/migrations/20261018000001_retention_final_canonical.sql
```

---

## Como Aplicar em Banco NOVO (Testes/Staging)

```bash
# Reset completo (apaga tudo e reaplica do zero na ordem correta)
supabase db reset

# OU se já tem estrutura base e só quer a canônica:
# No SQL Editor, execute: supabase/migrations/20261018000001_retention_final_canonical.sql
```

---

## Configuração do Cron (APÓS deploy da Edge Function)

A canônica inclui o cron **comentado**. Após deploy da Edge Function:

```sql
-- No SQL Editor, execute (substitua <PROJECT_REF>):
SELECT cron.schedule(
  'cleanup-services-daily',
  '0 3 * * *',
  $$
  SELECT net.http_post(
    url := 'https://<PROJECT_REF>.supabase.co/functions/v1/cleanup-services',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  );
  $$
);
```

Verifique:
```sql
SELECT * FROM cron.job WHERE jobname = 'cleanup-services-daily';
```

---

## Verificação Pós-Aplicação (execute no SQL Editor)

```sql
-- 1. Funções principais (devem retornar 9 linhas)
SELECT proname FROM pg_proc WHERE proname IN (
  'enqueue_storage_cleanup', 'get_pending_storage_cleanup',
  'mark_storage_cleanup_completed', 'mark_storage_cleanup_failed',
  'recover_expired_processing_items', 'cleanup_expired_services',
  'notify_expiring_services', 'create_service_summary',
  'set_service_expiry_on_status_change'
);

-- 2. Trigger ativo
SELECT * FROM information_schema.triggers WHERE trigger_name = 'set_service_expiry_on_status_change';

-- 3. Tabela da fila
SELECT * FROM information_schema.tables WHERE table_name = 'storage_cleanup_queue';

-- 4. RLS policies (3 policies)
SELECT * FROM pg_policies WHERE tablename = 'storage_cleanup_queue';

-- 5. Constraint unique
SELECT conname, contype FROM pg_constraint WHERE conrelid = 'public.service_history_summary'::regclass;

-- 6. Testes funcionais rápidos
SELECT public.notify_expiring_services();  -- não deve erro
SELECT public.cleanup_expired_services();  -- retorna jsonb com deleted_count=0 se não houver expirados
```

**Resultado esperado:**
- 9 funções
- 1 trigger
- 1 tabela `storage_cleanup_queue`
- 3 policies (select/insert/update para service_role)
- 1 constraint unique `service_history_summary_service_number_key`

---

## Resumo do que a Canônica Final Inclui

✅ **Tabela `storage_cleanup_queue`** com:
- Lease token (10 min) para evitar processamento duplicado
- Backoff exponencial (5min → 10min → 20min → 40min → 1h max)
- Dead letter após 5 tentativas
- Idempotência por `service_id:storage_path`
- RLS apenas para `service_role`
- Índices otimizados

✅ **RPCs da fila** (todas `security definer`, grants só `service_role`):
- `enqueue_storage_cleanup` - enfileira arquivos idempotente
- `get_pending_storage_cleanup` - busca + reserva atômica com lease
- `mark_storage_cleanup_completed` - valida lease_token
- `mark_storage_cleanup_failed` - valida lease + backoff
- `recover_expired_processing_items` - recupera processing órfãos

✅ **Retenção + Limpeza principal**:
- Trigger `set_service_expiry_on_status_change` (12 meses p/ completed/cancelled)
- `notify_expiring_services` (aviso 30 dias)
- `create_service_summary` (idempotente, definido ANTES de cleanup)
- `cleanup_expired_services` (lote 100, enfileira Storage, limpa BD, JSON result)

✅ **Grants corretos**: apenas `service_role` (Edge Function)

✅ **Constraint unique** `service_history_summary.service_number`

✅ **Cron comentado** (configurar após deploy Edge Function)

---

## Próximos Passos

1. **Execute** `scripts/cleanup-and-apply-canonical.sql` no banco original
2. **Confirme** verificação final (9 funções, 1 trigger, 1 tabela, 3 policies, 1 constraint)
3. **Deploy** Edge Function `cleanup-services` no Dashboard
4. **Configure** cron (descomente e execute bloco cron com `<PROJECT_REF>` real)
5. **Teste** E2E com banco de teste dedicado (`supabase db reset` + `tests/.env.test`)