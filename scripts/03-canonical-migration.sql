-- ============================================================
-- PASSO 3: MIGRATION CANÔNICA COMPLETA
-- Execute TERCEIRO no Supabase Dashboard → SQL Editor
-- (após Passo 1 e 2)
-- ============================================================

-- ============================================================
-- 0. LIMPEZA PREVENTIVA (trigger antigo de services)
-- ============================================================
DROP TRIGGER IF EXISTS set_service_expiry_on_status_change ON public.services;

-- ============================================================
-- 1. TABELA: Fila persistente de limpeza do Storage
-- ============================================================
CREATE TABLE IF NOT EXISTS public.storage_cleanup_queue (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_id UUID NOT NULL REFERENCES public.services(id) ON DELETE CASCADE,
  bucket TEXT NOT NULL DEFAULT 'service-files',
  storage_path TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'dead_letter')),
  attempts INT NOT NULL DEFAULT 0,
  max_attempts INT NOT NULL DEFAULT 5,
  last_error TEXT,
  service_number INT,
  service_type TEXT,
  client_id UUID,
  worker_id UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  processed_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  lease_token TEXT,
  lease_expires_at TIMESTAMPTZ,
  error_details JSONB,
  retry_after TIMESTAMPTZ,
  idempotency_key TEXT NOT NULL UNIQUE
);

CREATE INDEX IF NOT EXISTS storage_cleanup_queue_status_idx
  ON public.storage_cleanup_queue (status, retry_after)
  WHERE status IN ('pending', 'failed');

CREATE INDEX IF NOT EXISTS storage_cleanup_queue_service_idx
  ON public.storage_cleanup_queue (service_id);

CREATE INDEX IF NOT EXISTS storage_cleanup_queue_idempotency_idx
  ON public.storage_cleanup_queue (idempotency_key);

CREATE INDEX IF NOT EXISTS storage_cleanup_queue_lease_idx
  ON public.storage_cleanup_queue (lease_token)
  WHERE lease_token IS NOT NULL;

DROP TRIGGER IF EXISTS set_updated_at ON public.storage_cleanup_queue;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'set_updated_at') THEN
    CREATE TRIGGER set_updated_at
      BEFORE UPDATE ON public.storage_cleanup_queue
      FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;
END $$;

ALTER TABLE public.storage_cleanup_queue ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Cleanup process pode ler pendentes"
  ON public.storage_cleanup_queue FOR SELECT
  TO service_role
  USING (status IN ('pending', 'failed'));

CREATE POLICY "Cleanup process pode inserir"
  ON public.storage_cleanup_queue FOR INSERT
  TO service_role
  WITH CHECK (TRUE);

CREATE POLICY "Cleanup process pode atualizar"
  ON public.storage_cleanup_queue FOR UPDATE
  TO service_role
  USING (TRUE);


-- ============================================================
-- 2. FUNÇÕES AUXILIARES (definidas ANTES das que as usam)
-- ============================================================

CREATE OR REPLACE FUNCTION public.create_service_summary(p_service_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET SEARCH_PATH = ''
AS $$
DECLARE
  v_service RECORD;
BEGIN
  SELECT service_number, created_at, service_address, service_type
  INTO v_service
  FROM public.services
  WHERE id = p_service_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  INSERT INTO public.service_history_summary (
    service_number, service_date, service_location, service_type
  ) VALUES (
    v_service.service_number, v_service.created_at, v_service.service_address, v_service.service_type
  )
  ON CONFLICT (service_number) DO NOTHING;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_service_summary(UUID) FROM PUBLIC, ANON, AUTHENTICATED;
GRANT EXECUTE ON FUNCTION public.create_service_summary(UUID) TO SERVICE_ROLE;

COMMENT ON FUNCTION public.create_service_summary(UUID) IS
  'Cria resumo histórico antes de excluir dados completos. Idempotente por service_number.';


CREATE OR REPLACE FUNCTION public.notify_expiring_services()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET SEARCH_PATH = ''
AS $$
DECLARE
  v_service RECORD;
BEGIN
  FOR v_service IN
    SELECT s.id, s.service_number, s.client_id, s.worker_id, s.expires_at
    FROM public.services s
    WHERE s.expires_at BETWEEN NOW() + INTERVAL '30 days' AND NOW() + INTERVAL '31 days'
      AND NOT EXISTS (
        SELECT 1 FROM public.notifications n
        WHERE n.resource_id = s.id
          AND n.type = 'service_expiring'
          AND n.created_at > NOW() - INTERVAL '31 days'
      )
  LOOP
    INSERT INTO public.notifications (user_id, type, title, message, resource_type, resource_id)
    VALUES (
      v_service.client_id, 'service_expiring', 'Serviço será excluído em 30 dias',
      'Os dados completos do serviço #' || v_service.service_number || ' serão excluídos em 30 dias. Baixe as informações se necessário.',
      'service', v_service.id
    );

    INSERT INTO public.notifications (user_id, type, title, message, resource_type, resource_id)
    VALUES (
      v_service.worker_id, 'service_expiring', 'Serviço será excluído em 30 dias',
      'Os dados completos do serviço #' || v_service.service_number || ' serão excluídos em 30 dias.',
      'service', v_service.id
    );
  END LOOP;
END;
$$;

COMMENT ON FUNCTION public.notify_expiring_services() IS
  'Notifica usuários sobre serviços que expiram em 30 dias (política de retenção).';


-- ============================================================
-- 3. FUNÇÕES DA FILA DE LIMPEZA (storage_cleanup_queue)
-- ============================================================

CREATE OR REPLACE FUNCTION public.enqueue_storage_cleanup(
  p_service_id UUID,
  p_service_number INT,
  p_service_type TEXT,
  p_client_id UUID,
  p_worker_id UUID
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET SEARCH_PATH = ''
AS $$
DECLARE
  v_count INT := 0;
  v_file RECORD;
  v_idempotency_key TEXT;
BEGIN
  FOR v_file IN
    SELECT storage_path
    FROM public.service_files
    WHERE service_id = p_service_id
  LOOP
    v_idempotency_key := p_service_id::TEXT || ':' || v_file.storage_path;

    INSERT INTO public.storage_cleanup_queue (
      service_id, bucket, storage_path,
      service_number, service_type, client_id, worker_id,
      idempotency_key
    ) VALUES (
      p_service_id, 'service-files', v_file.storage_path,
      p_service_number, p_service_type, p_client_id, p_worker_id,
      v_idempotency_key
    )
    ON CONFLICT (idempotency_key) DO NOTHING;

    GET DIAGNOSTICS v_count = ROW_COUNT;
  END LOOP;

  RETURN v_count;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.enqueue_storage_cleanup(UUID, INT, TEXT, UUID, UUID)
  FROM PUBLIC, ANON, AUTHENTICATED;
GRANT EXECUTE ON FUNCTION public.enqueue_storage_cleanup(UUID, INT, TEXT, UUID, UUID)
  TO SERVICE_ROLE;

COMMENT ON FUNCTION public.enqueue_storage_cleanup(UUID, INT, TEXT, UUID, UUID) IS
  'Enfileira arquivos de um serviço para limpeza do Storage. Retorna qtd enfileirada. Idempotente.';


CREATE OR REPLACE FUNCTION public.recover_expired_processing_items()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET SEARCH_PATH = ''
AS $$
DECLARE
  v_count INT := 0;
BEGIN
  WITH recovered AS (
    UPDATE public.storage_cleanup_queue
    SET status = 'pending',
        lease_token = NULL,
        lease_expires_at = NULL,
        attempts = GREATEST(attempts - 1, 0),
        updated_at = NOW()
    WHERE status = 'processing'
      AND lease_expires_at IS NOT NULL
      AND lease_expires_at < NOW()
    RETURNING id
  )
  SELECT COUNT(*) INTO v_count FROM recovered;

  RETURN v_count;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.recover_expired_processing_items()
  FROM PUBLIC, ANON, AUTHENTICATED;
GRANT EXECUTE ON FUNCTION public.recover_expired_processing_items()
  TO SERVICE_ROLE;

COMMENT ON FUNCTION public.recover_expired_processing_items() IS
  'Recupera itens presos em processing com lease expirado (10 min). Retorna qtd recuperada.';


CREATE OR REPLACE FUNCTION public.get_pending_storage_cleanup(
  p_limit INT DEFAULT 100
)
RETURNS SETOF public.storage_cleanup_queue
LANGUAGE plpgsql
SECURITY DEFINER
SET SEARCH_PATH = ''
AS $$
DECLARE
  v_item public.storage_cleanup_queue%ROWTYPE;
BEGIN
  PERFORM public.recover_expired_processing_items();

  FOR v_item IN
    SELECT *
    FROM public.storage_cleanup_queue
    WHERE status IN ('pending', 'failed')
      AND (retry_after IS NULL OR retry_after <= NOW())
      AND attempts < max_attempts
      AND (lease_expires_at IS NULL OR lease_expires_at > NOW())
    ORDER BY created_at ASC
    LIMIT p_limit
  LOOP
    UPDATE public.storage_cleanup_queue
    SET status = 'processing',
        attempts = attempts + 1,
        lease_token = GEN_RANDOM_UUID(),
        lease_expires_at = NOW() + INTERVAL '10 minutes',
        updated_at = NOW()
    WHERE id = v_item.id
      AND status IN ('pending', 'failed')
      AND (lease_token IS NULL OR lease_expires_at IS NULL OR lease_expires_at < NOW())
    RETURNING * INTO v_item;

    IF FOUND THEN
      RETURN NEXT v_item;
    END IF;
  END LOOP;
  RETURN;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_pending_storage_cleanup(INT)
  FROM PUBLIC, ANON, AUTHENTICATED;
GRANT EXECUTE ON FUNCTION public.get_pending_storage_cleanup(INT)
  TO SERVICE_ROLE;

COMMENT ON FUNCTION public.get_pending_storage_cleanup(INT) IS
  'Retorna itens pendentes para processamento, reservando com lease_token (10 min). Recupera processing expirados.';


CREATE OR REPLACE FUNCTION public.mark_storage_cleanup_completed(
  p_id UUID,
  p_lease_token TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET SEARCH_PATH = ''
AS $$
DECLARE
  v_row_count INT := 0;
BEGIN
  UPDATE public.storage_cleanup_queue
  SET status = 'completed',
      completed_at = NOW(),
      lease_token = NULL,
      lease_expires_at = NULL,
      processed_at = NOW(),
      updated_at = NOW()
  WHERE id = p_id
    AND status = 'processing'
    AND lease_token = p_lease_token
    AND lease_expires_at > NOW();

  GET DIAGNOSTICS v_row_count = ROW_COUNT;
  RETURN v_row_count > 0;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.mark_storage_cleanup_completed(UUID, TEXT)
  FROM PUBLIC, ANON, AUTHENTICATED;
GRANT EXECUTE ON FUNCTION public.mark_storage_cleanup_completed(UUID, TEXT)
  TO SERVICE_ROLE;

COMMENT ON FUNCTION public.mark_storage_cleanup_completed(UUID, TEXT) IS
  'Marca item como concluído validando lease_token e lease não expirado. Retorna true se atualizou.';


CREATE OR REPLACE FUNCTION public.mark_storage_cleanup_failed(
  p_id UUID,
  p_lease_token TEXT,
  p_error TEXT,
  p_details JSONB DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET SEARCH_PATH = ''
AS $$
DECLARE
  v_attempts INT;
  v_max_attempts INT;
  v_next_retry TIMESTAMPTZ;
BEGIN
  UPDATE public.storage_cleanup_queue
  SET attempts = attempts + 1,
      updated_at = NOW()
  WHERE id = p_id
    AND status = 'processing'
    AND lease_token = p_lease_token
    AND lease_expires_at > NOW()
  RETURNING attempts, max_attempts INTO v_attempts, v_max_attempts;

  IF NOT FOUND THEN
    RETURN FALSE;
  END IF;

  IF v_attempts >= v_max_attempts THEN
    UPDATE public.storage_cleanup_queue
    SET status = 'dead_letter',
        last_error = p_error,
        error_details = p_details,
        lease_token = NULL,
        lease_expires_at = NULL,
        updated_at = NOW()
    WHERE id = p_id;
  ELSE
    v_next_retry := NOW() + LEAST(INTERVAL '1 hour', INTERVAL '5 minutes' * POWER(2, v_attempts));
    UPDATE public.storage_cleanup_queue
    SET status = 'failed',
        last_error = p_error,
        error_details = p_details,
        lease_token = NULL,
        lease_expires_at = NULL,
        retry_after = v_next_retry,
        updated_at = NOW()
    WHERE id = p_id;
  END IF;

  RETURN TRUE;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.mark_storage_cleanup_failed(UUID, TEXT, TEXT, JSONB)
  FROM PUBLIC, ANON, AUTHENTICATED;
GRANT EXECUTE ON FUNCTION public.mark_storage_cleanup_failed(UUID, TEXT, TEXT, JSONB)
  TO SERVICE_ROLE;

COMMENT ON FUNCTION public.mark_storage_cleanup_failed(UUID, TEXT, TEXT, JSONB) IS
  'Marca item como falha validando lease_token e lease não expirado. Retorna true se atualizou. Backoff exponencial.';


-- ============================================================
-- 4. POLÍTICA DE RETENÇÃO + LIMPEZA PRINCIPAL
-- ============================================================

CREATE OR REPLACE FUNCTION public.set_service_expiry_on_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET SEARCH_PATH = ''
AS $$
BEGIN
  IF NEW.status IN ('completed', 'cancelled') AND OLD.status NOT IN ('completed', 'cancelled') THEN
    NEW.expires_at := NOW() + INTERVAL '12 months';
    IF NEW.status = 'completed' AND OLD.completed_at IS NULL THEN
      NEW.completed_at := NOW();
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_service_expiry_on_status_change ON public.services;
CREATE TRIGGER set_service_expiry_on_status_change
  BEFORE UPDATE ON public.services
  FOR EACH ROW EXECUTE FUNCTION public.set_service_expiry_on_status_change();

REVOKE EXECUTE ON FUNCTION public.set_service_expiry_on_status_change() FROM PUBLIC, ANON, AUTHENTICATED;

COMMENT ON FUNCTION public.set_service_expiry_on_status_change() IS
  'Define expires_at = NOW() + 12 meses quando status vai para completed/cancelled. Preserva completed_at.';


CREATE OR REPLACE FUNCTION public.cleanup_expired_services()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET SEARCH_PATH = ''
AS $$
DECLARE
  v_service RECORD;
  v_deleted_count INT := 0;
  v_error_count INT := 0;
  v_errors JSONB := '[]'::JSONB;
  v_queued_count INT := 0;
BEGIN
  PERFORM public.recover_expired_processing_items();

  FOR v_service IN
    SELECT id, service_number, service_type, client_id, worker_id
    FROM public.services
    WHERE expires_at < NOW()
    ORDER BY expires_at ASC
    LIMIT 100
  LOOP
    BEGIN
      PERFORM public.create_service_summary(v_service.id);

      v_queued_count := v_queued_count + public.enqueue_storage_cleanup(
        v_service.id, v_service.service_number, v_service.service_type,
        v_service.client_id, v_service.worker_id
      );

      DELETE FROM public.service_files WHERE service_id = v_service.id;
      DELETE FROM public.service_documents WHERE service_id = v_service.id;
      DELETE FROM public.service_records WHERE service_id = v_service.id;
      DELETE FROM public.notifications WHERE resource_id = v_service.id;

      UPDATE public.services
      SET service_address = '[excluído]', updated_at = NOW()
      WHERE id = v_service.id;

      v_deleted_count := v_deleted_count + 1;

    EXCEPTION WHEN OTHERS THEN
      v_error_count := v_error_count + 1;
      v_errors := v_errors || JSONB_BUILD_OBJECT(
        'service_id', v_service.id,
        'service_number', v_service.service_number,
        'error', SQLERRM
      );
    END;
  END LOOP;

  RETURN JSONB_BUILD_OBJECT(
    'deleted_count', v_deleted_count,
    'error_count', v_error_count,
    'errors', v_errors,
    'queued_files', v_queued_count,
    'timestamp', NOW()
  );
END;
$$;

COMMENT ON FUNCTION public.cleanup_expired_services() IS
  'Limpa serviços expirados: 7 dias para ativos, 12 meses para concluídos/cancelados. Enfileira arquivos para limpeza pela Edge Function. Idempotente.';


REVOKE ALL ON FUNCTION public.notify_expiring_services() FROM PUBLIC, ANON, AUTHENTICATED;
REVOKE ALL ON FUNCTION public.create_service_summary(UUID) FROM PUBLIC, ANON, AUTHENTICATED;
REVOKE ALL ON FUNCTION public.cleanup_expired_services() FROM PUBLIC, ANON, AUTHENTICATED;

GRANT EXECUTE ON FUNCTION public.notify_expiring_services() TO SERVICE_ROLE;
GRANT EXECUTE ON FUNCTION public.create_service_summary(UUID) TO SERVICE_ROLE;
GRANT EXECUTE ON FUNCTION public.cleanup_expired_services() TO SERVICE_ROLE;


-- ============================================================
-- 5. CONSTRAINT UNIQUE service_history_summary.service_number
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'service_history_summary_service_number_key'
      AND conrelid = 'public.service_history_summary'::REGCLASS
  ) THEN
    ALTER TABLE public.service_history_summary
    ADD CONSTRAINT service_history_summary_service_number_key UNIQUE (service_number);
  END IF;
END $$;


-- ============================================================
-- 6. CRON JOB (comentado - execute APÓS deploy Edge Function)
-- ============================================================
/*
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
    body := '{}'::JSONB
  );
  $$
);
*/


-- ============================================================
-- VERIFICAÇÃO FINAL
-- ============================================================
SELECT '=== VERIFICAÇÃO FINAL ===' AS step;

SELECT 'Funções' AS check_type, proname AS name
FROM pg_proc
WHERE proname IN (
  'enqueue_storage_cleanup', 'get_pending_storage_cleanup',
  'mark_storage_cleanup_completed', 'mark_storage_cleanup_failed',
  'recover_expired_processing_items', 'cleanup_expired_services',
  'notify_expiring_services', 'create_service_summary',
  'set_service_expiry_on_status_change'
)
UNION ALL
SELECT 'Trigger', trigger_name
FROM information_schema.triggers
WHERE trigger_name = 'set_service_expiry_on_status_change'
UNION ALL
SELECT 'Tabela', table_name
FROM information_schema.tables
WHERE table_name = 'storage_cleanup_queue'
UNION ALL
SELECT 'Policy', policyname
FROM pg_policies
WHERE tablename = 'storage_cleanup_queue'
UNION ALL
SELECT 'Constraint', conname
FROM pg_constraint
WHERE conrelid = 'public.service_history_summary'::REGCLASS
  AND conname = 'service_history_summary_service_number_key';

-- Testes rápidos
SELECT 'TESTE notify_expiring_services()' AS test;
SELECT public.notify_expiring_services();

SELECT 'TESTE cleanup_expired_services()' AS test;
SELECT public.cleanup_expired_services();

SELECT '=== PASSO 3 CONCLUÍDO ===' AS status;