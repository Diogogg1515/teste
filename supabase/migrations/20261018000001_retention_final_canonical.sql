-- ============================================================
-- souza.l - Migration CANÔNICA FINAL: Retenção + Storage Queue + Cron
-- ============================================================
-- SUBSTITUI TODAS:
--   20261009000001_retention_cleanup.sql
--   20261011000001_retention_12_months.sql
--   20261013000002_retention_fixed.sql
--   20261015000001_storage_cleanup_queue.sql
--   20261016000001_storage_cleanup_recovery.sql
--   20261017000001_cleanup_services_cron.sql
--
-- APLICAR EM BANCO LIMPO: supabase db reset
-- APLICAR EM BANCO EXISTENTE: roda direto (CREATE OR REPLACE + IF NOT EXISTS)
-- ============================================================

-- ============================================================
-- 0. LIMPEZA PREVENTIVA (remove objetos legados se existirem)
-- ============================================================
-- Remove triggers legados
drop trigger if exists set_service_expiry_on_status_change on public.services;

-- Remove policies legadas da storage_cleanup_queue (se tabela existir)
drop policy if exists "Cleanup process pode ler pendentes" on public.storage_cleanup_queue;
drop policy if exists "Cleanup process pode inserir" on public.storage_cleanup_queue;
drop policy if exists "Cleanup process pode atualizar" on public.storage_cleanup_queue;

-- ============================================================
-- 1. TABELA: Fila persistente de limpeza do Storage
-- ============================================================
create table if not exists public.storage_cleanup_queue (
  id uuid primary key default gen_random_uuid(),
  service_id uuid not null references public.services(id) on delete cascade,
  bucket text not null default 'service-files',
  storage_path text not null,
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'completed', 'failed', 'dead_letter')),
  attempts int not null default 0,
  max_attempts int not null default 5,
  last_error text,
  service_number int,
  service_type text,
  client_id uuid,
  worker_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  processed_at timestamptz,
  completed_at timestamptz,
  -- Lease token para reservas atômicas (evita processamento duplicado)
  lease_token text,
  lease_expires_at timestamptz,
  -- Dados para diagnóstico
  error_details jsonb,
  retry_after timestamptz,
  -- Idempotência: service_id + storage_path
  idempotency_key text not null unique
);

-- Índices
create index if not exists storage_cleanup_queue_status_idx
  on public.storage_cleanup_queue (status, retry_after)
  where status in ('pending', 'failed');

create index if not exists storage_cleanup_queue_service_idx
  on public.storage_cleanup_queue (service_id);

create index if not exists storage_cleanup_queue_idempotency_idx
  on public.storage_cleanup_queue (idempotency_key);

create index if not exists storage_cleanup_queue_lease_idx
  on public.storage_cleanup_queue (lease_token)
  where lease_token is not null;

-- Trigger updated_at (depende da função pública set_updated_at existir)
drop trigger if exists set_updated_at on public.storage_cleanup_queue;
do $$
begin
  if exists (select 1 from pg_proc where proname = 'set_updated_at') then
    create trigger set_updated_at
      before update on public.storage_cleanup_queue
      for each row execute function public.set_updated_at();
  end if;
end $$;

-- RLS: apenas service_role
alter table public.storage_cleanup_queue enable row level security;

create policy "Cleanup process pode ler pendentes"
  on public.storage_cleanup_queue for select
  to service_role
  using (status in ('pending', 'failed'));

create policy "Cleanup process pode inserir"
  on public.storage_cleanup_queue for insert
  to service_role
  with check (true);

create policy "Cleanup process pode atualizar"
  on public.storage_cleanup_queue for update
  to service_role
  using (true);


-- ============================================================
-- 2. FUNÇÕES AUXILIARES (definidas ANTES das que as usam)
-- ============================================================

-- 2.1 Cria resumo histórico (idempotente) - DEVE VIR ANTES de cleanup_expired_services
create or replace function public.create_service_summary(p_service_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_service record;
begin
  select service_number, created_at, service_address, service_type
  into v_service
  from public.services
  where id = p_service_id;

  if not found then
    return;
  end if;

  insert into public.service_history_summary (
    service_number, service_date, service_location, service_type
  ) values (
    v_service.service_number, v_service.created_at, v_service.service_address, v_service.service_type
  )
  on conflict (service_number) do nothing;
end;
$$;

revoke execute on function public.create_service_summary(uuid) from public, anon, authenticated;
grant execute on function public.create_service_summary(uuid) to service_role;

comment on function public.create_service_summary(uuid) is
  'Cria resumo histórico antes de excluir dados completos. Idempotente por service_number.';


-- 2.2 Notificação: 30 dias antes da expiração
create or replace function public.notify_expiring_services()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_service record;
begin
  for v_service in
    select s.id, s.service_number, s.client_id, s.worker_id, s.expires_at
    from public.services s
    where s.expires_at between now() + interval '30 days' and now() + interval '31 days'
      and not exists (
        select 1 from public.notifications n
        where n.resource_id = s.id
          and n.type = 'service_expiring'
          and n.created_at > now() - interval '31 days'
      )
  loop
    insert into public.notifications (user_id, type, title, message, resource_type, resource_id)
    values (
      v_service.client_id, 'service_expiring', 'Serviço será excluído em 30 dias',
      'Os dados completos do serviço #' || v_service.service_number || ' serão excluídos em 30 dias. Baixe as informações se necessário.',
      'service', v_service.id
    );

    insert into public.notifications (user_id, type, title, message, resource_type, resource_id)
    values (
      v_service.worker_id, 'service_expiring', 'Serviço será excluído em 30 dias',
      'Os dados completos do serviço #' || v_service.service_number || ' serão excluídos em 30 dias.',
      'service', v_service.id
    );
  end loop;
end;
$$;

comment on function public.notify_expiring_services() is
  'Notifica usuários sobre serviços que expiram em 30 dias (política de retenção).';


-- ============================================================
-- 3. FUNÇÕES DA FILA DE LIMPEZA (storage_cleanup_queue)
-- ============================================================

-- 3.1 Enfileira arquivos de um serviço (idempotente)
create or replace function public.enqueue_storage_cleanup(
  p_service_id uuid,
  p_service_number int,
  p_service_type text,
  p_client_id uuid,
  p_worker_id uuid
)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count int := 0;
  v_file record;
  v_idempotency_key text;
begin
  for v_file in
    select storage_path
    from public.service_files
    where service_id = p_service_id
  loop
    v_idempotency_key := p_service_id::text || ':' || v_file.storage_path;

    insert into public.storage_cleanup_queue (
      service_id, bucket, storage_path,
      service_number, service_type, client_id, worker_id,
      idempotency_key
    ) values (
      p_service_id, 'service-files', v_file.storage_path,
      p_service_number, p_service_type, p_client_id, p_worker_id,
      v_idempotency_key
    )
    on conflict (idempotency_key) do nothing;

    get diagnostics v_count = row_count;
  end loop;

  return v_count;
end;
$$;

revoke execute on function public.enqueue_storage_cleanup(uuid, int, text, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.enqueue_storage_cleanup(uuid, int, text, uuid, uuid)
  to service_role;

comment on function public.enqueue_storage_cleanup(uuid, int, text, uuid, uuid) is
  'Enfileira arquivos de um serviço para limpeza do Storage. Retorna qtd enfileirada. Idempotente.';


-- 3.2 Recupera itens processing com lease expirado (10 min)
create or replace function public.recover_expired_processing_items()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count int := 0;
begin
  with recovered as (
    update public.storage_cleanup_queue
    set status = 'pending',
        lease_token = null,
        lease_expires_at = null,
        attempts = greatest(attempts - 1, 0),
        updated_at = now()
    where status = 'processing'
      and lease_expires_at is not null
      and lease_expires_at < now()
    returning id
  )
  select count(*) into v_count from recovered;

  return v_count;
end;
$$;

revoke execute on function public.recover_expired_processing_items()
  from public, anon, authenticated;
grant execute on function public.recover_expired_processing_items()
  to service_role;

comment on function public.recover_expired_processing_items() is
  'Recupera itens presos em processing com lease expirado (10 min). Retorna qtd recuperada.';


-- 3.3 Busca e reserva itens pendentes com lease token atômico
create or replace function public.get_pending_storage_cleanup(
  p_limit int default 100
)
returns setof public.storage_cleanup_queue
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item public.storage_cleanup_queue%rowtype;
begin
  -- 1. Recupera itens processing com lease expirado
  perform public.recover_expired_processing_items();

  -- 2. Busca e reserva itens pendentes (FOR UPDATE SKIP LOCKED equivalente)
  for v_item in
    select *
    from public.storage_cleanup_queue
    where status in ('pending', 'failed')
      and (retry_after is null or retry_after <= now())
      and attempts < max_attempts
      and (lease_expires_at is null or lease_expires_at > now())
    order by created_at asc
    limit p_limit
  loop
    -- Reserva atômica
    update public.storage_cleanup_queue
    set status = 'processing',
        attempts = attempts + 1,
        lease_token = gen_random_uuid(),
        lease_expires_at = now() + interval '10 minutes',
        updated_at = now()
    where id = v_item.id
      and status in ('pending', 'failed')
      and (lease_token is null or lease_expires_at is null or lease_expires_at < now())
    returning * into v_item;

    if found then
      return next v_item;
    end if;
  end loop;
  return;
end;
$$;

revoke execute on function public.get_pending_storage_cleanup(int)
  from public, anon, authenticated;
grant execute on function public.get_pending_storage_cleanup(int)
  to service_role;

comment on function public.get_pending_storage_cleanup(int) is
  'Retorna itens pendentes para processamento, reservando com lease_token (10 min). Recupera processing expirados.';


-- 3.4 Marca item como concluído (valida lease_token)
create or replace function public.mark_storage_cleanup_completed(
  p_id uuid,
  p_lease_token text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row_count int := 0;
begin
  update public.storage_cleanup_queue
  set status = 'completed',
      completed_at = now(),
      lease_token = null,
      lease_expires_at = null,
      processed_at = now(),
      updated_at = now()
  where id = p_id
    and status = 'processing'
    and lease_token = p_lease_token
    and lease_expires_at > now();

  get diagnostics v_row_count = row_count;
  return v_row_count > 0;
end;
$$;

revoke execute on function public.mark_storage_cleanup_completed(uuid, text)
  from public, anon, authenticated;
grant execute on function public.mark_storage_cleanup_completed(uuid, text)
  to service_role;

comment on function public.mark_storage_cleanup_completed(uuid, text) is
  'Marca item como concluído validando lease_token e lease não expirado. Retorna true se atualizou.';


-- 3.5 Marca item como falha (valida lease_token + backoff exponencial)
create or replace function public.mark_storage_cleanup_failed(
  p_id uuid,
  p_lease_token text,
  p_error text,
  p_details jsonb default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_attempts int;
  v_max_attempts int;
  v_next_retry timestamptz;
begin
  -- Valida lease_token atomicamente
  update public.storage_cleanup_queue
  set attempts = attempts + 1,
      updated_at = now()
  where id = p_id
    and status = 'processing'
    and lease_token = p_lease_token
    and lease_expires_at > now()
  returning attempts, max_attempts into v_attempts, v_max_attempts;

  if not found then
    return false;
  end if;

  if v_attempts >= v_max_attempts then
    -- Dead letter
    update public.storage_cleanup_queue
    set status = 'dead_letter',
        last_error = p_error,
        error_details = p_details,
        lease_token = null,
        lease_expires_at = null,
        updated_at = now()
    where id = p_id;
  else
    -- Backoff exponencial: 5min * 2^attempts (max 1 hora)
    v_next_retry := now() + least(interval '1 hour', interval '5 minutes' * power(2, v_attempts));
    update public.storage_cleanup_queue
    set status = 'failed',
        last_error = p_error,
        error_details = p_details,
        lease_token = null,
        lease_expires_at = null,
        retry_after = v_next_retry,
        updated_at = now()
    where id = p_id;
  end if;

  return true;
end;
$$;

revoke execute on function public.mark_storage_cleanup_failed(uuid, text, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.mark_storage_cleanup_failed(uuid, text, text, jsonb)
  to service_role;

comment on function public.mark_storage_cleanup_failed(uuid, text, text, jsonb) is
  'Marca item como falha validando lease_token e lease não expirado. Retorna true se atualizou. Backoff exponencial.';


-- ============================================================
-- 4. POLÍTICA DE RETENÇÃO + LIMPEZA PRINCIPAL
-- ============================================================

-- 4.1 Trigger: define expiração de 12 meses ao concluir/cancelar
create or replace function public.set_service_expiry_on_status_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status in ('completed', 'cancelled') and old.status not in ('completed', 'cancelled') then
    new.expires_at := now() + interval '12 months';
    if new.status = 'completed' and old.completed_at is null then
      new.completed_at := now();
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists set_service_expiry_on_status_change on public.services;
create trigger set_service_expiry_on_status_change
  before update on public.services
  for each row execute function public.set_service_expiry_on_status_change();

revoke execute on function public.set_service_expiry_on_status_change() from public, anon, authenticated;

comment on function public.set_service_expiry_on_status_change() is
  'Define expires_at = now() + 12 meses quando status vai para completed/cancelled. Preserva completed_at.';


-- 4.2 Limpeza principal: chamada pela Edge Function
create or replace function public.cleanup_expired_services()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_service record;
  v_deleted_count int := 0;
  v_error_count int := 0;
  v_errors jsonb := '[]'::jsonb;
  v_queued_count int := 0;
begin
  -- 1. Recupera itens processing com lease expirado
  perform public.recover_expired_processing_items();

  -- Busca serviços expirados (lote de 100)
  for v_service in
    select id, service_number, service_type, client_id, worker_id
    from public.services
    where expires_at < now()
    order by expires_at asc
    limit 100
  loop
    begin
      -- Cria resumo histórico (função já existe acima)
      perform public.create_service_summary(v_service.id);

      -- Enfileira arquivos do Storage ANTES de deletar service_files
      v_queued_count := v_queued_count + public.enqueue_storage_cleanup(
        v_service.id, v_service.service_number, v_service.service_type,
        v_service.client_id, v_service.worker_id
      );

      -- Deleta registros relacionados (cascata via FK)
      delete from public.service_files where service_id = v_service.id;
      delete from public.service_documents where service_id = v_service.id;
      delete from public.service_records where service_id = v_service.id;
      delete from public.notifications where resource_id = v_service.id;

      -- Remove dados sensíveis, mantém metadados para auditoria
      update public.services
      set service_address = '[excluído]', updated_at = now()
      where id = v_service.id;

      v_deleted_count := v_deleted_count + 1;

    exception when others then
      v_error_count := v_error_count + 1;
      v_errors := v_errors || jsonb_build_object(
        'service_id', v_service.id,
        'service_number', v_service.service_number,
        'error', sqlerrm
      );
    end;
  end loop;

  return jsonb_build_object(
    'deleted_count', v_deleted_count,
    'error_count', v_error_count,
    'errors', v_errors,
    'queued_files', v_queued_count,
    'timestamp', now()
  );
end;
$$;

comment on function public.cleanup_expired_services() is
  'Limpa serviços expirados: 7 dias para ativos, 12 meses para concluídos/cancelados. Enfileira arquivos para limpeza pela Edge Function. Idempotente.';


-- 4.3 Grants das funções de retenção (apenas service_role)
revoke all on function public.notify_expiring_services() from public, anon, authenticated;
revoke all on function public.create_service_summary(uuid) from public, anon, authenticated;
revoke all on function public.cleanup_expired_services() from public, anon, authenticated;

grant execute on function public.notify_expiring_services() to service_role;
grant execute on function public.create_service_summary(uuid) to service_role;
grant execute on function public.cleanup_expired_services() to service_role;


-- ============================================================
-- 5. CONSTRAINT UNIQUE service_history_summary.service_number
-- ============================================================
-- Garante que o resumo histórico não duplique service_number
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'service_history_summary_service_number_key'
      and conrelid = 'public.service_history_summary'::regclass
  ) then
    alter table public.service_history_summary
    add constraint service_history_summary_service_number_key unique (service_number);
  end if;
end $$;


-- ============================================================
-- 6. CRON JOB: Agendamento da Edge Function cleanup-services
-- ============================================================
-- NOTA: No Supabase, pg_cron e pg_net já estão habilitados.
-- Execute o bloco abaixo APÓS deploy da Edge Function no Dashboard.
--
-- Substitua <PROJECT_REF> pelo seu project reference real.
-- Ex: abcdefghijklmnop.supabase.co → project_ref = abcdefghijklmnop
/*
SELECT cron.schedule(
  'cleanup-services-daily',
  '0 3 * * *',  -- 03:00 UTC = 00:00 BRT / 23:00 BRT-1
  $$
  SELECT net.http_post(
    url := 'https://<PROJECT_REF>.supabase.co/functions/v1/cleanup-services',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  );
  $$
);
*/

-- Verificação:
-- SELECT * FROM cron.job WHERE jobname = 'cleanup-services-daily';

-- Remoção (se necessário):
-- SELECT cron.unschedule('cleanup-services-daily');


-- ============================================================
-- 7. VERIFICAÇÃO PÓS-APLICAÇÃO (execute para confirmar)
-- ============================================================
-- Tabela existe?
-- SELECT * FROM information_schema.tables WHERE table_name = 'storage_cleanup_queue';
--
-- Funções existem?
-- SELECT proname FROM pg_proc WHERE proname IN (
--   'enqueue_storage_cleanup', 'get_pending_storage_cleanup',
--   'mark_storage_cleanup_completed', 'mark_storage_cleanup_failed',
--   'recover_expired_processing_items', 'cleanup_expired_services',
--   'notify_expiring_services', 'create_service_summary',
--   'set_service_expiry_on_status_change'
-- );
--
-- Trigger ativo?
-- SELECT * FROM information_schema.triggers WHERE trigger_name = 'set_service_expiry_on_status_change';
--
-- RLS ativo?
-- SELECT * FROM pg_policies WHERE tablename = 'storage_cleanup_queue';
--
-- Constraint unique?
-- SELECT conname, contype FROM pg_constraint WHERE conrelid = 'public.service_history_summary'::regclass;
-- ============================================================