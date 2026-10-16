-- ============================================================
-- souza.l - Migration: remoção de função de teste set_test_role
-- ============================================================
-- Esta migration remove a vulnerabilidade crítica de escalação de privilégios
-- introduzida pela migration 20261009000013_test_set_role.sql
-- 
-- A função permitia que QUALQUER usuário autenticado alterasse o papel
-- de QUALQUER usuário (incluindo a si mesmo) para 'admin' ou 'worker'.
-- ============================================================

-- Revoga execução se a função existir
do $$
begin
  if exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where p.proname = 'set_test_role'
      and n.nspname = 'public'
  ) then
    revoke all on function public.set_test_role(uuid, public.user_role) from public, anon, authenticated;
    drop function public.set_test_role(uuid, public.user_role);
  end if;
end $$;

-- Confirmação
comment on table public.profiles is 'Perfis de usuários. Papel alterado apenas por fluxos autorizados no servidor.';