-- ============================================================
-- SOUZA.L - AUDITORIA COMPLETA BANCO ORIGINAL (PENTE FINO)
-- Execute no Supabase Dashboard → SQL Editor do projeto ORIGINAL
-- ============================================================

-- ============================================================
-- 1. TABELAS BASE (schema original)
-- ============================================================
SELECT '=== 1. TABELAS BASE ===' AS section;

SELECT table_name, table_type
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN (
    'profiles', 'services', 'service_requests', 'service_records',
    'service_files', 'notifications', 'service_documents',
    'service_history_summary', 'audit_logs', 'storage_cleanup_queue'
  )
ORDER BY table_name;

-- Verifica colunas críticas
SELECT '--- Colunas services ---' AS check;
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'services'
  AND column_name IN ('id', 'service_number', 'status', 'expires_at', 'completed_at', 'service_address', 'client_id', 'worker_id', 'service_type', 'created_at', 'updated_at')
ORDER BY ordinal_position;

SELECT '--- Colunas service_history_summary ---' AS check;
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'service_history_summary'
ORDER BY ordinal_position;

-- ============================================================
-- 2. CONSTRAINTS E ÍNDICES
-- ============================================================
SELECT '=== 2. CONSTRAINTS ===' AS section;

SELECT conname AS constraint_name, contype AS type, conrelid::regclass AS table_name, pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid IN (
  'public.services'::regclass,
  'public.service_history_summary'::regclass,
  'public.service_files'::regclass,
  'public.storage_cleanup_queue'::regclass
)
ORDER BY conrelid::regclass::text, contype DESC;

SELECT '--- Unique service_history_summary.service_number ---' AS check;
SELECT conname, contype, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'public.service_history_summary'::regclass
  AND conname = 'service_history_summary_service_number_key';

-- ============================================================
-- 3. TRIGGERS
-- ============================================================
SELECT '=== 3. TRIGGERS ===' AS section;

SELECT trigger_name, event_manipulation, event_object_table, action_timing, action_statement
FROM information_schema.triggers
WHERE trigger_schema = 'public'
  AND trigger_name IN (
    'set_service_expiry_on_status_change',
    'set_updated_at'
  )
ORDER BY event_object_table, trigger_name;

-- ============================================================
-- 4. FUNÇÕES (RPCs) - Todas as 9 esperadas
-- ============================================================
SELECT '=== 4. FUNÇÕES RPC (9 esperadas) ===' AS section;

SELECT proname AS function_name,
       pg_get_function_identity_arguments(oid) AS arguments,
       prosrc IS NOT NULL AS has_body,
       prosecdef AS security_definer
FROM pg_proc
WHERE proname IN (
  'enqueue_storage_cleanup',
  'get_pending_storage_cleanup',
  'mark_storage_cleanup_completed',
  'mark_storage_cleanup_failed',
  'recover_expired_processing_items',
  'cleanup_expired_services',
  'notify_expiring_services',
  'create_service_summary',
  'set_service_expiry_on_status_change'
)
ORDER BY proname;

-- Verifica grants (apenas service_role)
SELECT '--- Grants das funções ---' AS check;
SELECT p.proname, r.rolname, has_function_privilege(r.oid, p.oid, 'EXECUTE') AS can_execute
FROM pg_proc p
JOIN pg_roles r ON r.rolname IN ('service_role', 'authenticated', 'anon', 'postgres')
WHERE p.proname IN (
  'enqueue_storage_cleanup', 'get_pending_storage_cleanup',
  'mark_storage_cleanup_completed', 'mark_storage_cleanup_failed',
  'recover_expired_processing_items', 'cleanup_expired_services',
  'notify_expiring_services', 'create_service_summary',
  'set_service_expiry_on_status_change'
)
ORDER BY p.proname, r.rolname;

-- ============================================================
-- 5. POLÍTICAS RLS
-- ============================================================
SELECT '=== 5. POLÍTICAS RLS ===' AS section;

SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN (
    'services', 'service_requests', 'service_records',
    'service_files', 'notifications', 'service_documents',
    'service_history_summary', 'audit_logs', 'profiles',
    'storage_cleanup_queue'
  )
ORDER BY tablename, policyname;

-- Verifica RLS habilitado
SELECT '--- RLS habilitado por tabela ---' AS check;
SELECT c.relname AS table_name, c.relrowsecurity AS rls_enabled
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN (
    'services', 'service_requests', 'service_records',
    'service_files', 'notifications', 'service_documents',
    'service_history_summary', 'audit_logs', 'profiles',
    'storage_cleanup_queue'
  )
ORDER BY c.relname;

-- ============================================================
-- 6. STORAGE_CLEANUP_QUEUE - Verificação detalhada
-- ============================================================
SELECT '=== 6. STORAGE_CLEANUP_QUEUE DETALHADO ===' AS section;

SELECT '--- Estrutura ---' AS check;
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'storage_cleanup_queue'
ORDER BY ordinal_position;

SELECT '--- Índices ---' AS check;
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public' AND tablename = 'storage_cleanup_queue'
ORDER BY indexname;

SELECT '--- Policies ---' AS check;
SELECT policyname, cmd, roles, qual
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'storage_cleanup_queue';

SELECT '--- Trigger updated_at ---' AS check;
SELECT trigger_name, action_statement
FROM information_schema.triggers
WHERE trigger_schema = 'public' AND event_object_table = 'storage_cleanup_queue';

-- ============================================================
-- 7. VULNERABILIDADE set_test_role
-- ============================================================
SELECT '=== 7. VULNERABILIDADE set_test_role ===' AS section;

SELECT proname, pg_get_functiondef(oid) AS definition
FROM pg_proc
WHERE proname = 'set_test_role';

-- ============================================================
-- 8. CONTAS SUSPEITAS (worker/admin)
-- ============================================================
SELECT '=== 8. CONTAS SUSPEITAS ===' AS section;

SELECT id, name, role, created_at, updated_at,
       EXTRACT(EPOCH FROM (updated_at - created_at))/60 AS minutes_diff
FROM profiles
WHERE role IN ('worker', 'admin')
  AND updated_at > created_at + INTERVAL '5 minutes'
ORDER BY updated_at DESC;

-- ============================================================
-- 9. EDGE FUNCTION + CRON
-- ============================================================
SELECT '=== 9. CRON JOB ===' AS section;

SELECT jobid, schedule, command, active, jobname
FROM cron.job
WHERE jobname = 'cleanup-services-daily';

-- ============================================================
-- 10. TESTES FUNCIONAIS RÁPIDOS
-- ============================================================
SELECT '=== 10. TESTES FUNCIONAIS ===' AS section;

SELECT 'TESTE notify_expiring_services()' AS test;
SELECT public.notify_expiring_services();

SELECT 'TESTE cleanup_expired_services()' AS test;
SELECT public.cleanup_expired_services();

SELECT 'TESTE enqueue_storage_cleanup (precisa service_id real)' AS test;
-- SELECT public.enqueue_storage_cleanup('<SERVICE_ID_EXISTENTE>', 1, 'tipo', '<CLIENT_ID>', '<WORKER_ID>');

-- ============================================================
-- 11. MIGRATIONS APLICADAS (histórico)
-- ============================================================
SELECT '=== 11. MIGRATIONS HISTÓRICO ===' AS section;

-- Verifica estrutura real da tabela
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'supabase_migrations' AND table_name = 'schema_migrations';

-- Dados (ajuste conforme colunas reais)
SELECT *
FROM supabase_migrations.schema_migrations
WHERE version LIKE '2026%'
ORDER BY version;

-- ============================================================
-- 12. RESUMO ESPERADO vs REAL
-- ============================================================
SELECT '=== 12. CHECKLIST FINAL ===' AS section;

-- Contadores
SELECT
  (SELECT count(*) FROM pg_proc WHERE proname IN (
    'enqueue_storage_cleanup', 'get_pending_storage_cleanup',
    'mark_storage_cleanup_completed', 'mark_storage_cleanup_failed',
    'recover_expired_processing_items', 'cleanup_expired_services',
    'notify_expiring_services', 'create_service_summary',
    'set_service_expiry_on_status_change'
  )) AS funcoes_rpc_esperadas_9,

  (SELECT count(*) FROM information_schema.triggers
   WHERE trigger_schema = 'public'
     AND trigger_name = 'set_service_expiry_on_status_change') AS trigger_expiry_1,

  (SELECT count(*) FROM information_schema.tables
   WHERE table_schema = 'public' AND table_name = 'storage_cleanup_queue') AS tabela_queue_1,

  (SELECT count(*) FROM pg_policies
   WHERE schemaname = 'public' AND tablename = 'storage_cleanup_queue') AS policies_queue_3,

  (SELECT count(*) FROM pg_constraint
   WHERE conrelid = 'public.service_history_summary'::regclass
     AND conname = 'service_history_summary_service_number_key') AS constraint_unique_1,

  (SELECT count(*) FROM pg_proc WHERE proname = 'set_test_role') AS vulnerabilidade_0_esperado,

  (SELECT count(*) FROM cron.job WHERE jobname = 'cleanup-services-daily' AND active) AS cron_ativo_1;