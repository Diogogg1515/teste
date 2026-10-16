-- ============================================================
-- souza.l - Migration: Configuração do Cron para cleanup-services
-- ============================================================
-- Habilita pg_cron + pg_net e agenda execução diária da Edge Function
-- Execute APÓS deploy da Edge Function cleanup-services no Dashboard
-- ============================================================

-- 1. Habilita extensões necessárias (superuser required - fazer no Dashboard SQL Editor)
-- CREATE EXTENSION IF NOT EXISTS pg_cron;
-- CREATE EXTENSION IF NOT EXISTS pg_net;

-- NOTA: No Supabase, pg_cron e pg_net já vêm pré-instalados.
-- Apenas o agendamento abaixo precisa ser executado.

-- 2. Agenda execução diária às 03:00 UTC (00:00 BRT / 23:00 BRT-1)
-- Substitua <PROJECT_REF> pelo seu project reference do Supabase
-- Ex: abcdefghijklmnop.supabase.co → project_ref = abcdefghijklmnop
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

-- 3. Verificar agendamento
-- SELECT * FROM cron.job WHERE jobname = 'cleanup-services-daily';

-- 4. Para remover (se necessário)
-- SELECT cron.unschedule('cleanup-services-daily');

-- ============================================================
-- INSTRUÇÕES DE DEPLOY:
-- ============================================================
-- 1. Deploy da Edge Function no Dashboard:
--    https://supabase.com/dashboard/project/<SEU_PROJECT>/functions
--    Nome: cleanup-services
--    Conteúdo: supabase/functions/cleanup-services/index.ts
--
-- 2. No SQL Editor, execute ESTA migration APÓS o deploy da function
--    (substitua <PROJECT_REF> pelo valor real)
--
-- 3. Confirme com:
--    SELECT * FROM cron.job WHERE jobname = 'cleanup-services-daily';
-- ============================================================