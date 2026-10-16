-- ============================================================
-- souza.l - Migration Bootstrap: quote_visits para resolver dependência service_invites → quote_visits
-- ============================================================
-- Cria o schema de quote_visits de forma IDEMPOTENTE antes da migration 05 precisar dele.
-- Em instalação limpa: tabela criada antes da 05 → 05 executa normalmente.
-- Em banco existente (já com 12 aplicada): todas as operações são no-op segura.
-- IMPORTANTE:
--   * Cópia EXATA da definição da migration 12 (20261009000012)
--   * Todas as operações usam verificações de existência para idempotência
--   * Preserva RLS, privilégios, funções, triggers e constraints IDÊNTICOS à migration 12
--   * NÃO duplica definições: cria apenas se não existir
--   * NÃO afeta ON CONFLICT (service_number) em service/service_history_summary
-- ============================================================

-- 1. Tipo enum visit_status (idempotente via DO block)
do $$
begin
  if not exists (select 1 from pg_type where typname = 'visit_status') then
    create type public.visit_status as enum ('scheduled', 'done', 'not_done');
  end if;
end $$;

-- 2. Tabela principal (cópia literal da migration 12, com IF NOT EXISTS)
create table if not exists public.quote_visits (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  client_name text not null,
  phone text,
  address text not null,
  scheduled_at timestamptz not null,
  notes text,
  status public.visit_status not null default 'scheduled',
  answered_at timestamptz,
  service_id uuid references public.services (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint quote_visits_client_name_length
    check (char_length(btrim(client_name)) between 2 and 100),
  constraint quote_visits_address_length
    check (char_length(btrim(address)) between 5 and 300),
  constraint quote_visits_phone_format
    check (phone is null or phone ~ '^[0-9]{10,15}$'),
  constraint quote_visits_notes_length
    check (notes is null or char_length(notes) <= 500)
);

-- 3. Trigger set_updated_at (função já existe na migration 01)
do $$
begin
  if not exists (
    select 1 from pg_trigger
    where tgname = 'set_updated_at' and tgrelid = 'public.quote_visits'::regclass
  ) then
    create trigger set_updated_at before update on public.quote_visits
      for each row execute function public.set_updated_at();
  end if;
end $$;

-- 4. Função + trigger quote_visits_set_answered_at
do $$
begin
  if not exists (select 1 from pg_proc where proname = 'quote_visits_set_answered_at') then
    create function public.quote_visits_set_answered_at()
    returns trigger
    language plpgsql
    security definer
    set search_path = ''
    as $func$
    begin
      if new.status in ('done', 'not_done') and old.status = 'scheduled' then
        new.answered_at := now();
      elsif new.status = 'scheduled' and old.status in ('done', 'not_done') then
        new.answered_at := null;
      end if;
      return new;
    end;
    $func$;
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgname = 'quote_visits_set_answered_at' and tgrelid = 'public.quote_visits'::regclass
  ) then
    create trigger quote_visits_set_answered_at
      before update on public.quote_visits
      for each row execute function public.quote_visits_set_answered_at();
  end if;
end $$;

-- 5. Índices (verificação via pg_indexes)
do $$
begin
  if not exists (select 1 from pg_indexes where indexname = 'quote_visits_worker_idx') then
    create index quote_visits_worker_idx on public.quote_visits (worker_id, scheduled_at desc);
  end if;
  if not exists (select 1 from pg_indexes where indexname = 'quote_visits_status_idx') then
    create index quote_visits_status_idx on public.quote_visits (status);
  end if;
end $$;

-- 6. RLS + Policies (verificação por nome em pg_policies)
do $$
begin
  -- Habilita RLS se não estiver ativo
  if not exists (
    select 1 from pg_tables
    where tablename = 'quote_visits' and schemaname = 'public' and rowsecurity
  ) then
    alter table public.quote_visits enable row level security;
  end if;

  -- Policy: Profissional le as proprias visitas
  if not exists (
    select 1 from pg_policies
    where policyname = 'Profissional le as proprias visitas' and tablename = 'quote_visits'
  ) then
    create policy "Profissional le as proprias visitas"
    on public.quote_visits for select
    to authenticated
    using (worker_id = (select auth.uid()));
  end if;

  -- Policy: Profissional cria visitas
  if not exists (
    select 1 from pg_policies
    where policyname = 'Profissional cria visitas' and tablename = 'quote_visits'
  ) then
    create policy "Profissional cria visitas"
    on public.quote_visits for insert
    to authenticated
    with check (worker_id = (select auth.uid()));
  end if;

  -- Policy: Profissional atualiza as proprias visitas (CORRIGIDA: remove subconsulta redundante)
  if not exists (
    select 1 from pg_policies
    where policyname = 'Profissional atualiza as proprias visitas' and tablename = 'quote_visits'
  ) then
    create policy "Profissional atualiza as proprias visitas"
    on public.quote_visits for update
    to authenticated
    using (worker_id = (select auth.uid()))
    with check (worker_id = (select auth.uid()));
  end if;

  -- Policy: Profissional apaga as proprias visitas
  if not exists (
    select 1 from pg_policies
    where policyname = 'Profissional apaga as proprias visitas' and tablename = 'quote_visits'
  ) then
    create policy "Profissional apaga as proprias visitas"
    on public.quote_visits for delete
    to authenticated
    using (worker_id = (select auth.uid()));
  end if;
end $$;

-- 7. Privilegios (segunda camada de proteção - idempotente via revoke/grant explícito)
do $$
begin
  revoke all on public.quote_visits from anon, authenticated;
  grant select, insert, update, delete on public.quote_visits to authenticated;
  grant update (client_name, phone, address, scheduled_at, notes, status, answered_at)
    on public.quote_visits to authenticated;
end $$;