-- ============================================================
-- souza.l - Migration 05: convite por link
-- ============================================================
-- RODAR UMA VEZ, no SQL Editor do Supabase (cole tudo e clique em Run).
--
-- Como funciona:
--  1. O profissional cria um convite (tipo de servico + nome do cliente).
--     O banco gera um codigo longo e aleatorio (64 caracteres) e devolve
--     UMA vez. So o "hash" (impressao digital) do codigo fica guardado:
--     quem ler a tabela nao consegue reconstruir o link.
--  2. O cliente abre o link. A previa (so nome do profissional e tipo do
--     servico) e a unica funcao liberada para visitantes sem login.
--  3. O cliente cria conta ou entra, informa o endereco e aceita. O banco
--     cria o servico de uma vez so. O convite vale uma unica vez e
--     expira em 7 dias.
--
-- Seguranca:
--  * Ninguem escreve na tabela pelo site: so por funcoes do banco.
--  * O profissional le apenas os proprios convites (sem o hash).
--  * So contas de CLIENTE aceitam convites.
-- ============================================================

create type public.invite_status as enum ('pending', 'accepted', 'cancelled');

create table public.service_invites (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid not null default auth.uid()
    references public.profiles (id) on delete cascade,
  token_hash text not null unique,
  service_type text not null,
  client_label text not null,
  visit_id uuid references public.quote_visits (id) on delete set null,
  status public.invite_status not null default 'pending',
  expires_at timestamptz not null default (now() + interval '7 days'),
  accepted_by uuid references public.profiles (id) on delete set null,
  accepted_at timestamptz,
  service_id uuid references public.services (id) on delete set null,
  created_at timestamptz not null default now(),

  constraint service_invites_token_hash_format
    check (token_hash ~ '^[0-9a-f]{64}$'),
  constraint service_invites_type_length
    check (char_length(btrim(service_type)) between 2 and 100),
  constraint service_invites_label_length
    check (char_length(btrim(client_label)) between 2 and 100)
);

create index service_invites_worker_idx
  on public.service_invites (worker_id, created_at desc);

alter table public.service_invites enable row level security;

create policy "Profissional le os proprios convites"
on public.service_invites for select
to authenticated
using (worker_id = (select auth.uid()));

-- Privilegios: so leitura, e sem a coluna token_hash.
revoke all on public.service_invites from anon, authenticated;
grant select (
  id, worker_id, service_type, client_label, visit_id, status,
  expires_at, accepted_at, service_id, created_at
) on public.service_invites to authenticated;


-- ------------------------------------------------------------
-- Funcao interna: impressao digital do codigo (ninguem de fora chama)
-- ------------------------------------------------------------
create function public.invite_token_hash(p_token text)
returns text
language sql
immutable
set search_path = ''
as $$
  select encode(sha256(convert_to(p_token, 'utf8')), 'hex');
$$;

revoke all on function public.invite_token_hash(text) from public, anon, authenticated;


-- ------------------------------------------------------------
-- Profissional cria o convite (devolve o codigo UMA vez)
-- ------------------------------------------------------------
create function public.create_service_invite(
  p_service_type text,
  p_client_label text,
  p_visit_id uuid default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_type text := btrim(coalesce(p_service_type, ''));
  v_label text := btrim(coalesce(p_client_label, ''));
  v_token text;
begin
  if v_uid is null
     or public.my_role() is distinct from 'worker'::public.user_role then
    raise exception 'not_allowed';
  end if;

  if char_length(v_type) not between 2 and 100 then
    raise exception 'invalid_service_type';
  end if;

  if char_length(v_label) not between 2 and 100 then
    raise exception 'invalid_client_name';
  end if;

  if p_visit_id is not null then
    if not exists (
      select 1 from public.quote_visits
      where id = p_visit_id and worker_id = v_uid
    ) then
      raise exception 'visit_not_found';
    end if;

    if exists (
      select 1 from public.quote_visits
      where id = p_visit_id and service_id is not null
    ) then
      raise exception 'visit_already_converted';
    end if;
  end if;

  -- 64 caracteres hexadecimais, aleatorios
  v_token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');

  insert into public.service_invites (
    worker_id, token_hash, service_type, client_label, visit_id
  )
  values (
    v_uid, public.invite_token_hash(v_token), v_type, v_label, p_visit_id
  );

  return v_token;
end;
$$;


-- ------------------------------------------------------------
-- Previa do convite (UNICA funcao liberada para visitantes)
-- Mostra so o nome do profissional e o tipo do servico.
-- ------------------------------------------------------------
create function public.preview_service_invite(p_token text)
returns table (o_worker_name text, o_service_type text, o_state text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_inv public.service_invites%rowtype;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{64}$' then
    return;
  end if;

  select * into v_inv
  from public.service_invites
  where token_hash = public.invite_token_hash(p_token);

  if not found then
    return;
  end if;

  return query
  select
    coalesce(
      (select wp.display_name from public.worker_profiles wp
        where wp.user_id = v_inv.worker_id),
      (select p.name from public.profiles p where p.id = v_inv.worker_id)
    ),
    v_inv.service_type,
    case
      when v_inv.status = 'accepted' then 'accepted'
      when v_inv.status = 'cancelled' then 'cancelled'
      when v_inv.expires_at <= now() then 'expired'
      else 'valid'
    end;
end;
$$;


-- ------------------------------------------------------------
-- Cliente aceita o convite: cria o servico (uma unica vez)
-- ------------------------------------------------------------
create function public.redeem_service_invite(p_token text, p_address text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_inv public.service_invites%rowtype;
  v_address text := btrim(coalesce(p_address, ''));
  v_service_id uuid;
begin
  if v_uid is null
     or public.my_role() is distinct from 'client'::public.user_role then
    raise exception 'not_allowed';
  end if;

  if p_token is null or p_token !~ '^[0-9a-f]{64}$' then
    raise exception 'invite_not_found';
  end if;

  -- Trava o convite: dois toques ao mesmo tempo nao criam dois servicos
  select * into v_inv
  from public.service_invites
  where token_hash = public.invite_token_hash(p_token)
  for update;

  if not found then
    raise exception 'invite_not_found';
  end if;

  if v_inv.status = 'accepted' then
    raise exception 'invite_already_used';
  end if;

  if v_inv.status = 'cancelled' then
    raise exception 'invite_cancelled';
  end if;

  if v_inv.expires_at <= now() then
    raise exception 'invite_expired';
  end if;

  if char_length(v_address) not between 5 and 300 then
    raise exception 'invalid_address';
  end if;

  -- Registro do pedido (todo servico nasce de um pedido aceito)
  insert into public.service_requests (
    client_id, worker_id, service_type, status, responded_at
  )
  values (
    v_uid, v_inv.worker_id, v_inv.service_type, 'accepted', now()
  );

  insert into public.services (client_id, worker_id, service_type, service_address)
  values (v_uid, v_inv.worker_id, v_inv.service_type, v_address)
  returning id into v_service_id;

  update public.service_invites
  set status = 'accepted',
      accepted_by = v_uid,
      accepted_at = now(),
      service_id = v_service_id
  where id = v_inv.id;

  -- Se o convite veio de uma visita da agenda, liga a visita ao servico
  if v_inv.visit_id is not null then
    update public.quote_visits
    set service_id = v_service_id
    where id = v_inv.visit_id and worker_id = v_inv.worker_id;
  end if;

  insert into public.notifications (
    user_id, type, title, message, resource_type, resource_id
  )
  values (
    v_inv.worker_id,
    'invite_accepted',
    'Convite aceito',
    'O cliente aceitou o convite e o serviço foi criado.',
    'service',
    v_service_id
  );

  return v_service_id;
end;
$$;


-- ------------------------------------------------------------
-- Profissional cancela um convite que ainda esta pendente
-- ------------------------------------------------------------
create function public.cancel_service_invite(p_invite_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    raise exception 'not_allowed';
  end if;

  update public.service_invites
  set status = 'cancelled'
  where id = p_invite_id and worker_id = v_uid and status = 'pending';

  if not found then
    raise exception 'invite_not_found';
  end if;
end;
$$;


-- ------------------------------------------------------------
-- Quem pode chamar cada funcao
-- ------------------------------------------------------------
revoke all on function public.create_service_invite(text, text, uuid) from public, anon;
revoke all on function public.preview_service_invite(text) from public;
revoke all on function public.redeem_service_invite(text, text) from public, anon;
revoke all on function public.cancel_service_invite(uuid) from public, anon;

grant execute on function public.create_service_invite(text, text, uuid) to authenticated;
grant execute on function public.preview_service_invite(text) to anon, authenticated;
grant execute on function public.redeem_service_invite(text, text) to authenticated;
grant execute on function public.cancel_service_invite(uuid) to authenticated;
