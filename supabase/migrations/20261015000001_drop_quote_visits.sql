-- ============================================================
-- souza.l - Migration: Remove quote_visits (agenda) - FORA DA V1
-- ============================================================
-- Conforme CLAUDE.md linha 149: "agenda complexa" listada como FORA DA V1
-- Esta migration remove a funcionalidade completa de quote_visits
-- ============================================================

-- 1. Revogar privilégios das funções
revoke execute on function public.list_my_visits() from anon, authenticated;
revoke execute on function public.get_visit(uuid) from anon, authenticated;
revoke execute on function public.update_visit_status(uuid, public.visit_status) from anon, authenticated;
revoke execute on function public.reschedule_visit(uuid, timestamptz) from anon, authenticated;
revoke execute on function public.delete_visit(uuid) from anon, authenticated;

-- 2. Dropar funções
drop function if exists public.list_my_visits();
drop function if exists public.get_visit(uuid);
drop function if exists public.update_visit_status(uuid, public.visit_status);
drop function if exists public.reschedule_visit(uuid, timestamptz);
drop function if exists public.delete_visit(uuid);

-- 3. Dropar trigger
drop trigger if exists set_updated_at on public.quote_visits;

-- 4. Dropar tabela (cascata remove policies, índices, constraints, tipo enum)
drop table if exists public.quote_visits;

-- 5. Dropar tipo enum (se não for usado em outra tabela)
drop type if exists public.visit_status;

-- ============================================================
-- FIM - quote_visits removido completamente
-- ============================================================