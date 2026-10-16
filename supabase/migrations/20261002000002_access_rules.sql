-- ============================================================
-- souza.l - Migration 02: regras de acesso (Etapa 3)
-- ============================================================
-- RODAR UMA VEZ, no SQL Editor do Supabase (cole tudo e clique em Run).
--
-- Principios:
--  * Quem pode LER cada tabela: so os participantes do servico.
--  * Quem pode ESCREVER: somente por funcoes controladas no banco
--    (aceitar pedido, mudar status etc.), nunca direto pelo site.
--  * Registros: so se cria; ninguem edita nem apaga (V1).
--  * Administrador fica fora do conteudo dos servicos.
--  * Alem do RLS, os PRIVILEGIOS das tabelas tambem sao restritos
--    (segunda camada de protecao).
-- ============================================================


-- ------------------------------------------------------------
-- 1. Papel padrao de menor privilegio
-- ------------------------------------------------------------
alter table public.profiles alter column role set default 'client';


-- ------------------------------------------------------------
-- 2. Integridade e validacao dos dados
-- ------------------------------------------------------------

-- Um unico pedido pendente por par cliente + trabalhador (evita duplicidade)
create unique index service_requests_one_pending_per_pair
  on public.service_requests (client_id, worker_id)
  where status = 'pending';

alter table public.service_requests
  add constraint service_requests_type_length
  check (service_type is null or char_length(btrim(service_type)) between 2 and 100);

alter table public.services
  add constraint services_type_length
  check (char_length(btrim(service_type)) between 2 and 100);

alter table public.services
  add constraint services_address_length
  check (char_length(btrim(service_address)) between 5 and 300);

alter table public.service_records
  add constraint service_records_content_length
  check (char_length(btrim(content)) between 1 and 5000);


-- ------------------------------------------------------------
-- 3. Funcao auxiliar (uso interno; ninguem de fora pode chamar)
-- ------------------------------------------------------------
create function public.my_role()
returns public.user_role
language sql
stable
security definer
set search_path = ''
as $$
  select role from public.profiles where id = (select auth.uid());
$$;

revoke all on function public.my_role() from public, anon, authenticated;


-- ------------------------------------------------------------
-- 4. Funcoes de negocio (unico caminho de escrita para pedidos e servicos)
-- ------------------------------------------------------------

-- 4.1 Trabalhador procura um cliente pelo codigo (devolve so id e nome)
create function public.find_client_by_code(p_code text)
returns table (client_id uuid, client_name text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null
     or public.my_role() is distinct from 'worker'::public.user_role then
    raise exception 'not_allowed';
  end if;

  return query
  select p.id, p.name
  from public.profiles p
  where p.client_code = upper(btrim(p_code))
    and p.role = 'client';
end;
$$;

-- 4.2 Trabalhador envia um pedido de servico
create function public.create_service_request(p_client_id uuid, p_service_type text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_type text := btrim(coalesce(p_service_type, ''));
  v_id uuid;
begin
  if v_uid is null
     or public.my_role() is distinct from 'worker'::public.user_role then
    raise exception 'not_allowed';
  end if;

  if char_length(v_type) not between 2 and 100 then
    raise exception 'invalid_service_type';
  end if;

  if not exists (
    select 1 from public.profiles
    where id = p_client_id and role = 'client'
  ) then
    raise exception 'client_not_found';
  end if;

  begin
    insert into public.service_requests (client_id, worker_id, service_type)
    values (p_client_id, v_uid, v_type)
    returning id into v_id;
  exception when unique_violation then
    raise exception 'duplicate_pending_request';
  end;

  insert into public.notifications (user_id, type, title, message, resource_type, resource_id)
  values (
    p_client_id,
    'service_request_received',
    'Novo pedido de serviço',
    'Você recebeu um pedido de serviço: ' || v_type || '.',
    'service_request',
    v_id
  );

  return v_id;
end;
$$;

-- 4.3 Cliente aceita o pedido: cria o servico (uma unica vez)
create function public.accept_service_request(p_request_id uuid, p_address text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_req public.service_requests%rowtype;
  v_address text := btrim(coalesce(p_address, ''));
  v_service_id uuid;
begin
  if v_uid is null then
    raise exception 'not_allowed';
  end if;

  -- Trava a linha: dois cliques ao mesmo tempo nao criam dois servicos
  select * into v_req
  from public.service_requests
  where id = p_request_id and client_id = v_uid
  for update;

  if not found then
    raise exception 'request_not_found';
  end if;

  if v_req.status <> 'pending' then
    raise exception 'request_not_pending';
  end if;

  if char_length(v_address) not between 5 and 300 then
    raise exception 'invalid_address';
  end if;

  insert into public.services (client_id, worker_id, service_type, service_address)
  values (
    v_req.client_id,
    v_req.worker_id,
    coalesce(v_req.service_type, 'Serviço'),
    v_address
  )
  returning id into v_service_id;

  update public.service_requests
  set status = 'accepted', responded_at = now()
  where id = v_req.id;

  insert into public.notifications (user_id, type, title, message, resource_type, resource_id)
  values (
    v_req.worker_id,
    'service_request_accepted',
    'Pedido aceito',
    'O cliente aceitou o pedido de serviço.',
    'service',
    v_service_id
  );

  return v_service_id;
end;
$$;

-- 4.4 Cliente recusa o pedido: o pedido e excluido (sem servico, sem historico)
create function public.reject_service_request(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_req public.service_requests%rowtype;
begin
  if v_uid is null then
    raise exception 'not_allowed';
  end if;

  select * into v_req
  from public.service_requests
  where id = p_request_id and client_id = v_uid
  for update;

  if not found then
    raise exception 'request_not_found';
  end if;

  if v_req.status <> 'pending' then
    raise exception 'request_not_pending';
  end if;

  delete from public.service_requests where id = v_req.id;

  insert into public.notifications (user_id, type, title, message)
  values (
    v_req.worker_id,
    'service_request_rejected',
    'Pedido recusado',
    'O cliente recusou o pedido de serviço.'
  );
end;
$$;

-- 4.5 Trabalhador retira um pedido que ainda esta pendente
create function public.withdraw_service_request(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_req public.service_requests%rowtype;
begin
  if v_uid is null then
    raise exception 'not_allowed';
  end if;

  select * into v_req
  from public.service_requests
  where id = p_request_id and worker_id = v_uid
  for update;

  if not found then
    raise exception 'request_not_found';
  end if;

  if v_req.status <> 'pending' then
    raise exception 'request_not_pending';
  end if;

  delete from public.service_requests where id = v_req.id;
end;
$$;

-- 4.6 Trabalhador muda o status do servico (so ele; so transicoes validas)
--   em andamento     -> aguardando resposta | interrompido | concluido | cancelado
--   aguardando resp. -> em andamento | concluido | cancelado
--   interrompido     -> em andamento | concluido | cancelado
--   concluido e cancelado: finais (nao mudam mais)
-- Nada aqui mexe em expires_at: o prazo de 7 dias nunca reinicia.
create function public.change_service_status(
  p_service_id uuid,
  p_new_status public.service_status
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_service public.services%rowtype;
  v_allowed boolean;
begin
  if v_uid is null then
    raise exception 'not_allowed';
  end if;

  select * into v_service
  from public.services
  where id = p_service_id and worker_id = v_uid
  for update;

  if not found then
    raise exception 'service_not_found';
  end if;

  if v_service.status = p_new_status then
    raise exception 'no_change';
  end if;

  v_allowed := case v_service.status
    when 'in_progress' then
      p_new_status in ('waiting_response', 'interrupted', 'completed', 'cancelled')
    when 'waiting_response' then
      p_new_status in ('in_progress', 'completed', 'cancelled')
    when 'interrupted' then
      p_new_status in ('in_progress', 'completed', 'cancelled')
    else false
  end;

  if not v_allowed then
    raise exception 'invalid_transition';
  end if;

  update public.services
  set status = p_new_status,
      completed_at = case when p_new_status = 'completed' then now() else completed_at end
  where id = v_service.id;

  insert into public.notifications (user_id, type, title, message, resource_type, resource_id)
  values (
    v_service.client_id,
    'service_status_changed',
    'Status do serviço alterado',
    'O trabalhador alterou o status do serviço.',
    'service',
    v_service.id
  );
end;
$$;

-- Quem pode chamar cada funcao: so usuarios logados (nunca visitantes)
revoke all on function public.find_client_by_code(text) from public, anon;
revoke all on function public.create_service_request(uuid, text) from public, anon;
revoke all on function public.accept_service_request(uuid, text) from public, anon;
revoke all on function public.reject_service_request(uuid) from public, anon;
revoke all on function public.withdraw_service_request(uuid) from public, anon;
revoke all on function public.change_service_status(uuid, public.service_status) from public, anon;

grant execute on function public.find_client_by_code(text) to authenticated;
grant execute on function public.create_service_request(uuid, text) to authenticated;
grant execute on function public.accept_service_request(uuid, text) to authenticated;
grant execute on function public.reject_service_request(uuid) to authenticated;
grant execute on function public.withdraw_service_request(uuid) to authenticated;
grant execute on function public.change_service_status(uuid, public.service_status) to authenticated;


-- ------------------------------------------------------------
-- 5. Politicas RLS
-- ------------------------------------------------------------
-- profiles: ja existe "Usuario le o proprio perfil" (migration 01).

create policy "Participante le o servico"
on public.services for select
to authenticated
using ((select auth.uid()) in (client_id, worker_id));

create policy "Participante le o pedido"
on public.service_requests for select
to authenticated
using ((select auth.uid()) in (client_id, worker_id));

create policy "Participante le os registros"
on public.service_records for select
to authenticated
using (
  exists (
    select 1 from public.services s
    where s.id = service_records.service_id
      and (select auth.uid()) in (s.client_id, s.worker_id)
  )
);

-- Cada participante cria apenas o PROPRIO registro, com o proprio papel,
-- e somente enquanto o servico esta em andamento ou aguardando resposta.
create policy "Participante cria o proprio registro"
on public.service_records for insert
to authenticated
with check (
  author_id = (select auth.uid())
  and exists (
    select 1 from public.services s
    where s.id = service_records.service_id
      and s.status in ('in_progress', 'waiting_response')
      and (
        (s.client_id = (select auth.uid()) and service_records.author_role = 'client')
        or
        (s.worker_id = (select auth.uid()) and service_records.author_role = 'worker')
      )
  )
);

create policy "Participante le os arquivos"
on public.service_files for select
to authenticated
using (
  exists (
    select 1 from public.services s
    where s.id = service_files.service_id
      and (select auth.uid()) in (s.client_id, s.worker_id)
  )
);

create policy "Participante le os documentos"
on public.service_documents for select
to authenticated
using (
  exists (
    select 1 from public.services s
    where s.id = service_documents.service_id
      and (select auth.uid()) in (s.client_id, s.worker_id)
  )
);

create policy "Usuario le as proprias notificacoes"
on public.notifications for select
to authenticated
using (user_id = (select auth.uid()));

create policy "Usuario marca as proprias notificacoes como lidas"
on public.notifications for update
to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

-- audit_logs e service_history_summary: sem politica = ninguem acessa
-- pelo site (so o servidor, em funcoes e rotinas controladas).
-- service_files e service_documents: o INSERT sera criado junto com a
-- funcionalidade de arquivos (Etapa 7) e de laudo (Etapa 9).


-- ------------------------------------------------------------
-- 6. Privilegios das tabelas (segunda camada de protecao)
-- ------------------------------------------------------------
-- Mesmo que uma politica seja criada por engano no futuro,
-- os privilegios abaixo continuam limitando o que o site pode fazer.

revoke all on all tables in schema public from anon;
revoke all on all tables in schema public from authenticated;

-- Tabelas novas nao nascem abertas: cada acesso precisa ser liberado de proposito
alter default privileges in schema public revoke all on tables from anon, authenticated;

grant select on
  public.profiles,
  public.services,
  public.service_requests,
  public.service_records,
  public.service_files,
  public.service_documents,
  public.notifications
to authenticated;

-- Registros: so as colunas que a pessoa pode preencher (id e datas ficam por conta do banco)
grant insert (service_id, author_id, author_role, content)
  on public.service_records to authenticated;

-- Notificacoes: a pessoa so pode marcar como lida
grant update (read_at) on public.notifications to authenticated;
