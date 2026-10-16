-- ============================================================
-- SOUZA.L - SCRIPT DE LIMPEZA E HARDENING DO BANCO REMOTO
-- Execute no Supabase Dashboard → SQL Editor
-- ============================================================

-- 1️⃣ VERIFICAR SE set_test_role() EXISTE (vulnerabilidade crítica)
SELECT proname, pg_get_functiondef(oid) AS definition
FROM pg_proc
WHERE proname = 'set_test_role';

-- 2️⃣ SE A QUERY ACIMA RETORNOU LINHAS, EXECUTE ESTE BLOCO:
-- revoke execute on function public.set_test_role(uuid, public.user_role) from authenticated;
-- drop function if exists public.set_test_role(uuid, public.user_role);

-- 3️⃣ AUDITORIA DE CONTAS SUSPEITAS (worker/admin promovidas indevidamente)
SELECT
  id,
  name,
  role,
  created_at,
  updated_at,
  EXTRACT(EPOCH FROM (updated_at - created_at))/60 AS minutes_diff
FROM profiles
WHERE role IN ('worker', 'admin')
  AND updated_at > created_at + INTERVAL '5 minutes'
ORDER BY updated_at DESC;

-- 4️⃣ APLICAR CONSTRAINT UNIQUE EM service_history_summary.service_number
-- (Migration 20261009000014 já criada, mas precisa ser aplicada no banco remoto)
ALTER TABLE service_history_summary
ADD CONSTRAINT service_history_summary_service_number_key UNIQUE (service_number);

-- 5️⃣ VERIFICAÇÃO PÓS-APLICAÇÃO
SELECT
  conname AS constraint_name,
  contype AS type,
  pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid = 'service_history_summary'::regclass;

-- ============================================================
-- APÓS EXECUTAR: Confirmar que tudo passou antes de prosseguir
-- ============================================================