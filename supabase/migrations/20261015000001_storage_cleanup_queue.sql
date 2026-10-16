-- ============================================================
-- souza.l - Migration: Fila persistente de limpeza do Storage
-- ============================================================
-- Cria tabela de fila para limpeza de arquivos do Storage,
-- processada pela Edge Function cleanup-services.
-- Permite retry, diagnóstico e idempotência.
-- ============================================================

-- 1. Tabela de fila de limpeza do Storage
create table public.storage_cleanup_queue (
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
  -- Dados para diagnóstico
  error_details jsonb,
  retry_after timestamptz,
  idempotency_key text not null unique
);

-- Índices para consultas da Edge Function
create index storage_cleanup_queue_status_idx
  on public.storage_cleanup_queue (status, retry_after)
  where status in ('pending', 'failed');

create index storage_cleanup_queue_service_idx
  on public.storage_cleanup_queue (service_id);

create index storage_cleanup_queue_idempotency_idx
  on public.storage_cleanup_queue (idempotency_key);

-- Trigger updated_at
create trigger set_updated_at
  before update on public.storage_cleanup_queue
  for each row execute function public.set_updated_at();

-- RLS: apenas service_role pode acessar
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

-- 2. Função para enfileirar arquivos de um serviço
-- Chamada pela cleanup_expired_services ANTES de deletar service_files
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
    -- Chave de idempotência: service_id + storage_path
    v_idempotency_key := p_service_id::text || ':' || v_file.storage_path;

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
      p_service_id,
      'service-files',
      v_file.storage_path,
      p_service_number,
      p_service_type,
      p_client_id,
      p_worker_id,
      v_idempotency_key
    )
    on conflict (idempotency_key) do nothing; -- idempotente

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


-- 3. Função para a Edge Function buscar itens pendentes
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
  for v_item in
    select *
    from public.storage_cleanup_queue
    where status in ('pending', 'failed')
      and (retry_after is null or retry_after <= now())
      and attempts < max_attempts
    order by created_at asc
    limit p_limit
  loop
    -- Marca como processing para evitar concorrência
    update public.storage_cleanup_queue
    set status = 'processing',
        attempts = attempts + 1,
        updated_at = now()
    where id = v_item.id
      and status in ('pending', 'failed');

    -- Retorna item atualizado se ainda for nosso
    if found then
      select * into v_item
      from public.storage_cleanup_queue
      where id = v_item.id;
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
  'Retorna itens pendentes para processamento, marcando como processing. Limite default 100.';


-- 4. Função para marcar item como concluído
create or replace function public.mark_storage_cleanup_completed(
  p_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.storage_cleanup_queue
  set status = 'completed',
      completed_at = now(),
      updated_at = now()
  where id = p_id
    and status = 'processing';
end;
$$;

revoke execute on function public.mark_storage_cleanup_completed(uuid)
  from public, anon, authenticated;
grant execute on function public.mark_storage_cleanup_completed(uuid)
  to service_role;


-- 5. Função para marcar item como falha (com backoff exponencial)
create or replace function public.mark_storage_cleanup_failed(
  p_id uuid,
  p_error text,
  p_details jsonb default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_attempts int;
  v_max_attempts int;
  v_next_retry timestamptz;
begin
  select attempts, max_attempts into v_attempts, v_max_attempts
  from public.storage_cleanup_queue
  where id = p_id;

  if v_attempts >= v_max_attempts then
    -- Dead letter
    update public.storage_cleanup_queue
    set status = 'dead_letter',
        last_error = p_error,
        error_details = p_details,
        updated_at = now()
    where id = p_id;
  else
    -- Backoff exponencial: 5min * 2^attempts (max 1 hora)
    v_next_retry := now() + least(interval '1 hour', interval '5 minutes' * power(2, v_attempts));
    update public.storage_cleanup_queue
    set status = 'failed',
        last_error = p_error,
        error_details = p_details,
        retry_after = v_next_retry,
        updated_at = now()
    where id = p_id;
  end if;
end;
$$;

revoke execute on function public.mark_storage_cleanup_failed(uuid, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.mark_storage_cleanup_failed(uuid, text, jsonb)
  to service_role;

comment on function public.mark_storage_cleanup_failed(uuid, text, jsonb) is
  'Marca item como falha com backoff exponencial. Após max_attempts, vai para dead_letter.';


-- 6. Atualização da cleanup_expired_services para usar a fila
-- Substitui a versão anterior
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
      v_queued_count := v_queued_count + public.enqueue_storage_cleanup(
        v_service.id,
        v_service.service_number,
        v_service.service_type,
        (select client_id from public.services where id = v_service.id),
        (select worker_id from public.services where id = v_service.id)
      );

      -- 3. Deleta registros relacionados (cascata via FK)
      delete from public.service_files where service_id = v_service.id;
      delete from public.service_documents where service_id = v_service.id;
      delete from public.service_records where service_id = v_service.id;
      delete from public.notifications where resource_id = v_service.id;

      -- 3. Remove dados sensíveis do serviço, mantém só metadados para auditoria
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


-- 6. Grants atualizados
revoke all on function public.enqueue_storage_cleanup(uuid, int, text, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.enqueue_storage_cleanup(uuid, int, text, uuid, uuid)
  to service_role;

revoke all on function public.get_pending_storage_cleanup(int)
  from public, anon, authenticated;
grant execute on function public.get_pending_storage_cleanup(int)
  to service_role;

revoke all on function public.mark_storage_cleanup_completed(uuid)
  from public, anon, authenticated;
grant execute on function public.mark_storage_cleanup_completed(uuid)
  to service_role;

revoke all on function public.mark_storage_cleanup_failed(uuid, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.mark_storage_cleanup_failed(uuid, text, jsonb)
  to service_role;

-- Grants da cleanup_expired_services já existem na migration anterior