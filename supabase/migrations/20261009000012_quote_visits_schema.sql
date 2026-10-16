-- ============================================================
-- souza.l - Migration 12: schema de visitas de orçamento (agenda)
-- ============================================================
-- RODAR UMA VEZ, no SQL Editor do Supabase (cole tudo e clique em Run).
--
-- O que e: tabela para agendar visitas de orçamento (apenas trabalhador).
-- Status: scheduled, done, no_show, rescheduled, cancelled.
-- FK para services: quando vira serviço, preenche service_id.
-- ============================================================

create type public.visit_status as enum (
  'scheduled',
  'done',
  'no_show',
  'rescheduled',
  'cancelled'
);

create table public.quote_visits (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid not null default auth.uid()
    references public.profiles (id) on delete cascade,
  client_name text not null,
  phone text,
  address text not null,
  scheduled_at timestamptz not null,
  notes text,
  status public.visit_status not null default 'scheduled',
  service_id uuid references public.services (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint quote_visits_client_name_length
    check (char_length(btrim(client_name)) between 2 and 100),
  constraint quote_visits_address_length
    check (char_length(btrim(address)) between 5 and 300),
  constraint quote_visits_notes_length
    check (notes is null or char_length(notes) <= 1000),
  constraint quote_visits_phone_format
    check (phone is null or phone ~ '^[0-9]{10,15}$')
);

create index quote_visits_worker_idx
  on public.quote_visits (worker_id, scheduled_at desc);

create index quote_visits_status_idx
  on public.quote_visits (status);

alter table public.quote_visits enable row level security;

-- Trigger updated_at
create trigger set_updated_at before update on public.quote_visits
  for each row execute function public.set_updated_at();

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

-- Privilegios
revoke all on public.quote_visits from anon, authenticated;
grant select, insert, update, delete on public.quote_visits to authenticated;

-- Função para listar visitas do profissional (usada pelo frontend)
create function public.list_my_visits()
returns setof public.quote_visits
language plpgsql
security definer
set search_path = ''
as $$
begin
  return query
  select * from public.quote_visits
  where worker_id = (select auth.uid())
  order by scheduled_at desc;
end;
$$;

revoke execute on function public.list_my_visits() from anon;
grant execute on function public.list_my_visits() to authenticated;

-- Função para buscar uma visita (usada pelo frontend)
create function public.get_visit(p_visit_id uuid)
returns public.quote_visits
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_visit public.quote_visits%rowtype;
begin
  select * into v_visit
  from public.quote_visits
  where id = p_visit_id and worker_id = (select auth.uid());

  if not found then
    return null;
  end if;

  return v_visit;
end;
$$;

revoke execute on function public.get_visit(uuid) from anon;
grant execute on function public.get_visit(uuid) to authenticated;

-- Função para atualizar status da visita
create function public.update_visit_status(p_visit_id uuid, p_status public.visit_status)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.quote_visits
  set status = p_status,
      updated_at = now()
  where id = p_visit_id and worker_id = (select auth.uid());

  if not found then
    raise exception 'visit_not_found';
  end if;
end;
$$;

revoke execute on function public.update_visit_status(uuid, public.visit_status) from anon;
grant execute on function public.update_visit_status(uuid, public.visit_status) to authenticated;

-- Função para reagendar visita
create function public.reschedule_visit(p_visit_id uuid, p_new_scheduled_at timestamptz)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.quote_visits
  set scheduled_at = p_new_scheduled_at,
      status = 'rescheduled',
      updated_at = now()
  where id = p_visit_id and worker_id = (select auth.uid());

  if not found then
    raise exception 'visit_not_found';
  end if;
end;
$$;

revoke execute on function public.reschedule_visit(uuid, timestamptz) from anon;
grant execute on function public.reschedule_visit(uuid, timestamptz) to authenticated;

-- Função para apagar visita
create function public.delete_visit(p_visit_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.quote_visits
  where id = p_visit_id and worker_id = (select auth.uid());

  if not found then
    raise exception 'visit_not_found';
  end if;
end;
$$;

revoke execute on function public.delete_visit(uuid) from anon;
grant execute on function public.delete_visit(uuid) to authenticated;

-- Comentários
comment on table public.quote_visits is 'Visitas de orçamento agendadas pelo profissional. Apenas o dono acessa.';
comment on column public.quote_visits.service_id is 'Preenchido quando a visita vira serviço (via convite aceito).';