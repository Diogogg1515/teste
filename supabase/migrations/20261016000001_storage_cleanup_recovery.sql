-- ============================================================
-- souza.l - Migration: Recuperação e lease token para fila de limpeza
-- ============================================================
-- Adiciona mecanismo de lease token para reservas atômicas,
-- recuperação de itens processing expirados (10 min),
-- e validação atômica de token nas operações de conclusão/falha.
-- ============================================================

-- 1. Adicionar colunas de lease token e lease expiry na fila
alter table public.storage_cleanup_queue
add column if not exists lease_token text,
add column if not exists lease_expires_at timestamptz;

-- Índice para busca por lease token
create index if not exists storage_cleanup_queue_lease_idx
  on public.storage_cleanup_queue (lease_token)
  where lease_token is not null;

-- 1. Função para recuperar itens processing com lease expirado
create or replace function public.recover_expired_processing_items()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count int := 0;
begin
  -- Recupera itens processing com lease_expires_at expirado
  -- Usa UPDATE com RETURNING para atomicidade
  with recovered as (
    update public.storage_cleanup_queue
    set status = 'pending',
        lease_token = null,
        lease_expires_at = null,
        attempts = greatest(attempts - 1, 0),  -- Decrementa tentativa mas não abaixo de zero
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
  'Recupera itens presos em processing com lease expirado. Retorna qtd recuperada.';


-- 2. Função para buscar e reservar itens pendentes com lease token atômico
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
  -- 1. Primeiro, recupera itens processing com lease expirado
  perform public.recover_expired_processing_items();

  -- 2. Busca e reserva itens pendentes com lease token atômico (FOR UPDATE SKIP LOCKED equivalente)
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
    -- Reserva atômica com FOR UPDATE SKIP LOCKED equivalente
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

    -- Se conseguiu reservar (found), retorna item com lease_token
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


-- 3. Atualizar mark_storage_cleanup_completed para validar lease_token
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
  -- Valida lease_token atomicamente: só atualiza se lease_token bater
  -- e status for processing e lease não expirado
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


-- 5. Atualizar mark_storage_cleanup_failed para validar lease_token
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
  v_updated boolean := false;
  v_attempts int;
  v_max_attempts int;
  v_next_retry timestamptz;
  v_row_count int;
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


-- 5. Atualizar cleanup_expired_services para enfileirar arquivos do Storage
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
  v_file record;
begin
  -- 1. Primeiro, recupera itens processing com lease expirado
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
      -- 1. Cria resumo histórico
      perform public.create_service_summary(v_service.id);

      -- 2. Enfileira arquivos do Storage ANTES de deletar service_files
      -- A Edge Function processará a fila storage_cleanup_queue
      for v_file in
        select storage_path
        from public.service_files
        where service_id = v_service.id
      loop
        -- Insere na fila de limpeza (idempotente por service_id:storage_path)
        insert into public.storage_cleanup_queue (
          service_id,
          bucket,
          storage_path,
          service_number,
          service_type,
          client_id,
          worker_id,
          idempotency_key
        ) values (
          v_service.id,
          'service-files',
          v_file.storage_path,
          v_service.service_number,
          v_service.service_type,
          v_service.client_id,
          v_service.worker_id,
          (v_service.id || ':' || v_file.storage_path) -- idempotency_key
        )
        on conflict (idempotency_key) do nothing;

        get diagnostics v_row_count = row_count;
        v_queued_count := v_queued_count + v_row_count;
      end loop;

      -- 3. Deleta registros relacionados (cascata via FK)
      delete from public.service_files where service_id = v_service.id;
      delete from public.service_documents where service_id = v_service.id;
      delete from public.service_records where service_id = v_service.id;
      delete from public.notifications where resource_id = v_service.id;

      -- 4. Remove dados sensíveis do serviço, mantém só metadados para auditoria
      update public.services
      set service_address = '[excluído]',
          updated_at = now()
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


-- Grants para as novas funções (apenas as que ainda não têm grant)
-- recover_expired_processing_items() e get_pending_storage_cleanup(int)
-- já têm grants na migration 20261015000001_storage_cleanup_queue.sql
-- mark_storage_cleanup_completed, mark_storage_cleanup_failed, cleanup_expired_services
-- também já têm grants na migration 20261015000001, NÃO duplicar aqui.