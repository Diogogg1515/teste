# DEPLOY EDGE FUNCTION: cleanup-services

## Via Supabase Dashboard (Recomendado)
1. Acesse: https://supabase.com/dashboard/project/<SEU_PROJECT>/functions
2. Clique "Create a new function" → Nome: `cleanup-services`
3. Cole o conteúdo de `supabase/functions/cleanup-services/index.ts`
4. Deploy

## Configurar Cron (pg_cron)
No SQL Editor, execute:
```sql
-- Habilita pg_cron (se não estiver)
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Agenda execução diária às 03:00 UTC
SELECT cron.schedule(
  'cleanup-services-daily',
  '0 3 * * *',  -- 03:00 UTC = 00:00 BRT / 23:00 BRT-1
  $$
  SELECT net.http_post(
    url := 'https://<SEU_PROJECT>.supabase.co/functions/v1/cleanup-services',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  );
  $$
);
```

## Verificar agendamento
```sql
SELECT * FROM cron.job WHERE jobname = 'cleanup-services-daily';
```