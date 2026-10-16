-- ============================================================
-- souza.l - Migration: Correção unificada da política de retenção
-- ============================================================
-- Substitui as migrations 20261009000001 e 20261011000001 (não as apaga;
-- cria nova versão corretiva).
--
-- Regras:
--   * Serviços em andamento (in_progress, waiting_response, interrupted):
--     expires_at = created_at + 7 dias (mantido pelo default atual).
--   * Serviços concluídos ou cancelados (completed, cancelled):
--     expires_at = now() + 12 meses (definido pelo trigger na transição).
--   * Aviso: 30 dias antes da expiração.
--   * Limpeza: exclui registros, arquivos, documentos, endereço e limpa Storage.
-- ============================================================

-- 1. Trigger: define expiração de 12 meses ao concluir ou cancelar
-- (substitui a função da migration 11)
create or replace function public.set_service_expiry_on_status_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Só age nas transições relevantes
  if new.status in ('completed', 'cancelled') and old.status not in ('completed', 'cancelled') then
    -- Define expiração para 12 meses a partir de agora
    new.expires_at := now() + interval '12 months';
    -- Registra quando foi concluído (se ainda não estava)
    if new.status = 'completed' and old.completed_at is null then
      new.completed_at := now();
    end if;
  end if;
  return new;
end;
$$;

-- Recria trigger (drop if exists + create)
drop trigger if exists set_service_expiry_on_status_change on public.services;
create trigger set_service_expiry_on_status_change
  before update on public.services
  for each row execute function public.set_service_expiry_on_status_change();

revoke execute on function public.set_service_expiry_on_status_change() from public, anon, authenticated;

comment on function public.set_service_expiry_on_status_change() is
  'Define expires_at = now() + 12 meses quando status vai para completed/cancelled. Preserva completed_at.';


-- 2. Notificação: 30 dias antes da expiração
-- (substitui a função da migration 1 e 11)
create or replace function public.notify_expiring_services()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_service record;
begin
  -- Serviços que expiram nos próximos 30-31 dias e ainda não foram notificados
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
    -- Notifica cliente
    insert into public.notifications (user_id, type, title, message, resource_type, resource_id)
    values (
      v_service.client_id,
      'service_expiring',
      'Serviço será excluído em 30 dias',
      'Os dados completos do serviço #' || v_service.service_number || ' serão excluídos em 30 dias. Baixe as informações se necessário.',
      'service',
      v_service.id
    );

    -- Notifica trabalhador
    insert into public.notifications (user_id, type, title, message, resource_type, resource_id)
    values (
      v_service.worker_id,
      'service_expiring',
      'Serviço será excluído em 30 dias',
      'Os dados completos do serviço #' || v_service.service_number || ' serão excluídos em 30 dias.',
      'service',
      v_service.id
    );
  end loop;
end;
$$;

comment on function public.notify_expiring_services() is
  'Notifica usuários sobre serviços que expiram em 30 dias (política de retenção).';


-- 3. Cria resumo histórico antes da exclusão (idempotente)
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
    service_number,
    service_date,
    service_location,
    service_type
  )
  values (
    v_service.service_number,
    v_service.created_at,
    v_service.service_address,
    v_service.service_type
  )
  on conflict (service_number) do nothing;
end;
$$;

revoke execute on function public.create_service_summary(uuid) from public, anon, authenticated;
grant execute on function public.create_service_summary(uuid) to service_role;


-- 4. Limpeza principal: exclui dados expirados e enfileira arquivos do Storage
-- Esta função é chamada pela Edge Function (service_role)
-- A Edge Function processa a fila storage_cleanup_queue via API oficial
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

      -- 2. Enfileira arquivos do Storage ANTES de deletar os registros
      -- A Edge Function processará a fila storage_cleanup_queue
      v_queued_count := v_queued_count + public.enqueue_storage_cleanup(
        v_service.id,
        v_service.service_number,
        v_service.service_type,
        v_service.client_id,
        v_service.worker_id
      );

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


-- 5. Grants: apenas service_role (Edge Function)
revoke all on function public.notify_expiring_services() from public, anon, authenticated;
revoke all on function public.create_service_summary(uuid) from public, anon, authenticated;
revoke all on function public.cleanup_expired_services() from public, anon, authenticated;

grant execute on function public.notify_expiring_services() to service_role;
grant execute on function public.create_service_summary(uuid) to service_role;
grant execute on function public.cleanup_expired_services() to service_role;