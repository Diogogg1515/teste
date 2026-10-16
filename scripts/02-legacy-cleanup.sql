-- ============================================================
-- PASSO 2: LIMPEZA DE OBJETOS LEGADOS
-- Execute SEGUNDO no Supabase Dashboard → SQL Editor
-- (após Passo 1 confirmar vulnerabilidade tratada)
-- ============================================================

SELECT 'LIMPEZA OBJETOS LEGADOS' AS step;

-- Remove triggers legados de retenção
DROP TRIGGER IF EXISTS set_service_expiry_on_status_change ON public.services;

-- Remove policies legadas da storage_cleanup_queue (SE tabela existir)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'storage_cleanup_queue') THEN
    DROP POLICY IF EXISTS "Cleanup process pode ler pendentes" ON public.storage_cleanup_queue;
    DROP POLICY IF EXISTS "Cleanup process pode inserir" ON public.storage_cleanup_queue;
    DROP POLICY IF EXISTS "Cleanup process pode atualizar" ON public.storage_cleanup_queue;
    DROP TRIGGER IF EXISTS set_updated_at ON public.storage_cleanup_queue;
  END IF;
END $$;

SELECT '=== PASSO 2 CONCLUÍDO ===' AS status;