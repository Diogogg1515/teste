-- ============================================================
-- souza.l - Migration 01: estrutura base (REGISTRO DO QUE JA FOI APLICADO)
-- ============================================================
-- ATENCAO: este arquivo NAO deve ser rodado de novo no Supabase.
-- Ele existe so para o projeto guardar, no Git, o que ja foi feito
-- nas Etapas 1 e 2 (tabelas, gatilho do perfil e politica de profiles).
-- Observacao: o padrao de profiles.role aqui aparece como 'client';
-- no banco real ele estava 'worker' e e corrigido na migration 02.
-- ============================================================

-- ---------- Parte 1: tipos e tabelas principais ----------
create type public.user_role as enum ('client', 'worker', 'admin');
create type public.service_status as enum ('in_progress', 'waiting_response', 'completed', 'cancelled', 'interrupted');
create type public.request_status as enum ('pending', 'accepted', 'rejected');
create type public.record_author as enum ('client', 'worker');
create type public.file_kind as enum ('photo', 'document', 'report', 'other');
create type public.document_kind as enum ('report', 'service_export');

create function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  name text not null,
  role public.user_role not null default 'client',
  client_code text unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.services (
  id uuid primary key default gen_random_uuid(),
  service_number bigint generated always as identity unique,
  client_id uuid not null references public.profiles (id),
  worker_id uuid not null references public.profiles (id),
  service_type text not null,
  service_address text not null,
  status public.service_status not null default 'in_progress',
  created_at timestamptz not null default now(),
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  expires_at timestamptz not null default (now() + interval '7 days'),
  updated_at timestamptz not null default now()
);

create table public.service_requests (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.profiles (id),
  worker_id uuid not null references public.profiles (id),
  service_type text,
  status public.request_status not null default 'pending',
  created_at timestamptz not null default now(),
  responded_at timestamptz
);

create trigger set_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();
create trigger set_updated_at before update on public.services
  for each row execute function public.set_updated_at();

-- ---------- Parte 2: demais tabelas, indices e RLS ----------
create table public.service_records (
  id uuid primary key default gen_random_uuid(),
  service_id uuid not null references public.services (id) on delete cascade,
  author_id uuid not null references public.profiles (id),
  author_role public.record_author not null,
  content text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.service_files (
  id uuid primary key default gen_random_uuid(),
  service_id uuid not null references public.services (id) on delete cascade,
  record_id uuid references public.service_records (id) on delete set null,
  uploaded_by uuid not null references public.profiles (id),
  file_type public.file_kind not null default 'photo',
  storage_path text not null,
  original_name text,
  mime_type text,
  file_size bigint,
  created_at timestamptz not null default now()
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  type text not null,
  title text not null,
  message text,
  resource_type text,
  resource_id uuid,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.service_documents (
  id uuid primary key default gen_random_uuid(),
  service_id uuid not null references public.services (id) on delete cascade,
  document_type public.document_kind not null,
  storage_path text not null,
  generated_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.service_history_summary (
  id uuid primary key default gen_random_uuid(),
  service_number bigint not null,
  service_date timestamptz not null,
  service_location text,
  service_type text,
  created_at timestamptz not null default now()
);

create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles (id) on delete set null,
  action text not null,
  resource_type text,
  resource_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create trigger set_updated_at before update on public.service_records
  for each row execute function public.set_updated_at();

create index on public.services (client_id);
create index on public.services (worker_id);
create index on public.services (status);
create index on public.services (expires_at);
create index on public.service_requests (client_id);
create index on public.service_requests (worker_id);
create index on public.service_requests (status);
create index on public.service_records (service_id);
create index on public.service_files (service_id);
create index on public.notifications (user_id);
create index on public.notifications (read_at);

alter table public.profiles enable row level security;
alter table public.services enable row level security;
alter table public.service_requests enable row level security;
alter table public.service_records enable row level security;
alter table public.service_files enable row level security;
alter table public.notifications enable row level security;
alter table public.service_documents enable row level security;
alter table public.service_history_summary enable row level security;
alter table public.audit_logs enable row level security;

-- ---------- Parte 3: codigo do cliente, gatilho do perfil e politica ----------

-- Gera um codigo de 6 caracteres, sem O/0/I/1/L
create function public.generate_client_code()
returns text
language plpgsql
set search_path = ''
as $$
declare
  chars constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  result text;
  i int;
begin
  loop
    result := '';
    for i in 1..6 loop
      result := result || substr(chars, 1 + floor(random() * length(chars))::int, 1);
    end loop;
    exit when not exists (
      select 1 from public.profiles where client_code = result
    );
  end loop;
  return result;
end;
$$;

-- Cria o perfil quando uma conta nasce. O papel e SEMPRE 'client'.
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, name, role, client_code)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'name'), ''), 'Cliente'),
    'client',
    public.generate_client_code()
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

revoke execute on function public.generate_client_code() from public, anon, authenticated;
revoke execute on function public.handle_new_user() from public, anon, authenticated;

-- Cada pessoa le so o proprio perfil. Sem politica de insert/update.
create policy "Usuario le o proprio perfil"
on public.profiles for select
to authenticated
using ((select auth.uid()) = id);
