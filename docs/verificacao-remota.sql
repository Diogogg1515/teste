-- ============================================================
-- souza.l - Consultas para verificação remota no SQL Editor do Supabase
-- ============================================================
-- Execute estas consultas no SQL Editor do Dashboard Supabase.
-- Não use comandos psql como \df, \d+, \df+ - eles não funcionam no Editor.
-- ============================================================

-- -------------------------------------------------------------------
-- 1. FUNÇÃO VULNERÁVEL set_test_role - DEVE RETORNAR 0 LINHAS
-- -------------------------------------------------------------------
SELECT
  proname AS function_name,
  pg_get_function_arguments(oid) AS arguments,
  proacl AS acl
FROM pg_proc
WHERE proname = 'set_test_role'
  AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');


-- -------------------------------------------------------------------
-- 2. HISTÓRICO DE MIGRATIONS APLICADAS
-- -------------------------------------------------------------------
SELECT
  version,
  name,
  executed_at,
  execution_time_ms
FROM supabase_migrations.schema_migrations
ORDER BY version;


-- -------------------------------------------------------------------
-- 3. TABELA quote_visits - SCHEMA COMPLETO
-- -------------------------------------------------------------------
SELECT
  column_name,
  data_type,
  is_nullable,
  column_default,
  character_maximum_length
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'quote_visits'
ORDER BY ordinal_position;


-- Índices da quote_visits
SELECT
  indexname,
  indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'quote_visits';


-- Triggers da quote_visits
SELECT
  tgname AS trigger_name,
  tgfoid::regproc AS function_name,
  tgtype,
  tgenabled
FROM pg_trigger
WHERE tgrelid = 'public.quote_visits'::regclass
  AND NOT tgisinternal;


-- Políticas RLS da quote_visits
SELECT
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'quote_visits';


-- Privilégios da quote_visits
SELECT
  grantee,
  privilege_type,
  is_grantable
FROM information_schema.table_privileges
WHERE table_schema = 'public'
  AND table_name = 'quote_visits'
ORDER BY grantee, privilege_type;


-- -------------------------------------------------------------------
-- 4. GRANTS DA TABELA service_files - DEVE INCLUIR 'caption'
-- -------------------------------------------------------------------
SELECT
  grantee,
  privilege_type,
  column_name
FROM information_schema.column_privileges
WHERE table_schema = 'public'
  AND table_name = 'service_files'
  AND grantee = 'authenticated'
ORDER BY column_name;


-- -------------------------------------------------------------------
-- 5. FUNÇÕES DE RETENÇÃO - DEVEM EXISTIR E SER EXECUTÁVEIS POR service_role
-- -------------------------------------------------------------------
SELECT
  p.proname AS function_name,
  pg_get_function_arguments(p.oid) AS arguments,
  pg_get_functiondef(p.oid) AS definition,
  p.proacl AS acl
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'notify_expiring_services',
    'create_service_summary',
    'cleanup_expired_services',
    'set_service_expiry_on_status_change'
  )
ORDER BY p.proname;


-- Verifica grants específicos para service_role
SELECT
  p.proname AS function_name,
  r.rolname AS grantee,
  'EXECUTE' AS privilege_type
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
JOIN pg_authid r ON r.oid = ANY(p.proacl) -- simplificado; ver proacl para detalhes
WHERE n.nspname = 'public'
  AND p.proname IN (
    'notify_expiring_services',
    'create_service_summary',
    'cleanup_expired_services',
    'set_service_expiry_on_status_change'
  );


-- -------------------------------------------------------------------
-- 6. VERIFICAÇÃO DA TABELA services - expires_at E status
-- -------------------------------------------------------------------
SELECT
  status,
  count(*) AS total,
  min(expires_at) AS expires_at_min,
  max(expires_at) AS expires_at_max,
  min(completed_at) AS completed_at_min,
  max(completed_at) AS completed_at_max
FROM public.services
GROUP BY status
ORDER BY status;


-- Serviços concluídos/cancelados sem expires_at ajustado (devem ter 12 meses)
SELECT
  id,
  service_number,
  status,
  completed_at,
  expires_at,
  (expires_at - now()) AS tempo_ate_expiracao
FROM public.services
WHERE status IN ('completed', 'cancelled')
  AND expires_at < (now() + interval '11 months')
ORDER BY expires_at;


-- -------------------------------------------------------------------
-- 7. VERIFICAÇÃO DA CONSTRAINT ÚNICA service_history_summary
-- -------------------------------------------------------------------
SELECT
  conname AS constraint_name,
  contype,
  pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid = 'public.service_history_summary'::regclass
  AND contype = 'u';


-- -------------------------------------------------------------------
-- 8. SERVICE FILES - POLÍTICA DE INSERT E CHECKS
-- -------------------------------------------------------------------
SELECT
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'service_files'
  AND policyname = 'Participante pode enviar arquivo';


-- Checks da service_files
SELECT
  conname AS constraint_name,
  pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid = 'public.service_files'::regclass
  AND contype = 'c';


-- -------------------------------------------------------------------
-- 9. TESTE DA FUNÇÃO cleanup_expired_services (DRY RUN - NÃO EXECUTA)
-- -------------------------------------------------------------------
-- Apenas mostra o que seria feito - NÃO EXECUTA A LIMPEZA REAL
-- Descomente a linha abaixo para testar (cuidado em produção!):
-- SELECT public.cleanup_expired_services();


-- -------------------------------------------------------------------
-- 10. RESUMO DE VERIFICAÇÃO RÁPIDA
-- -------------------------------------------------------------------
SELECT
  'set_test_role removida' AS check,
  CASE WHEN EXISTS (
    SELECT 1 FROM pg_proc WHERE proname = 'set_test_role'
  ) THEN '❌ FALHA - ainda existe' ELSE '✅ OK' END AS status
UNION ALL
SELECT
  'quote_visits existe',
  CASE WHEN EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'quote_visits'
  ) THEN '✅ OK' ELSE '❌ FALHA - não existe' END
UNION ALL
SELECT
  'caption grant em service_files',
  CASE WHEN EXISTS (
    SELECT 1 FROM information_schema.column_privileges
    WHERE table_schema = 'public'
      AND table_name = 'service_files'
      AND grantee = 'authenticated'
      AND column_name = 'caption'
      AND privilege_type = 'INSERT'
  ) THEN '✅ OK' ELSE '❌ FALHA - caption não concedido' END
UNION ALL
SELECT
  'Retenção 12 meses (trigger)',
  CASE WHEN EXISTS (
    SELECT 1 FROM pg_proc WHERE proname = 'set_service_expiry_on_status_change'
  ) THEN '✅ OK' ELSE '❌ FALHA - trigger não existe' END
UNION ALL
SELECT
  'notify_expiring_services (30 dias)',
  CASE WHEN EXISTS (
    SELECT 1 FROM pg_proc WHERE proname = 'notify_expiring_services'
  ) THEN '✅ OK' ELSE '❌ FALHA' END
UNION ALL
SELECT
  'cleanup_expired_services',
  CASE WHEN EXISTS (
    SELECT 1 FROM pg_proc WHERE proname = 'cleanup_expired_services'
  ) THEN '✅ OK' ELSE '❌ FALHA' END
UNION ALL
SELECT
  'service_history_summary unique constraint',
  CASE WHEN EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.service_history_summary'::regclass
      AND contype = 'u'
  ) THEN '✅ OK' ELSE '❌ FALHA' END;