-- Migration: Limpeza automática de serviços expirados
-- Executa exclusão de dados conforme política de retenção de 7 dias

-- Função para notificar serviços próximos da expiração (24h antes)
create or replace function public.notify_expiring_services()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_service record;
begin
  -- Serviços que expiram nas próximas 24-48 horas e ainda não foram notificados
  for v_service in
    select s.id, s.service_number, s.client_id, s.worker_id
    from public.services s
    where s.expires_at between now() + interval '24 hours' and now() + interval '48 hours'
      and not exists (
        select 1 from public.notifications n
        where n.resource_id = s.id
          and n.type = 'service_expiring'
          and n.created_at > now() - interval '48 hours'
      )
  loop
    -- Notifica cliente
    insert into public.notifications (user_id, type, title, message, resource_type, resource_id)
    values (
      v_service.client_id,
      'service_expiring',
      'Serviço será excluído em breve',
      'Os dados completos deste serviço serão excluídos em até 24 horas. Baixe as informações se necessário.',
      'service',
      v_service.id
    );

    -- Notifica trabalhador
    insert into public.notifications (user_id, type, title, message, resource_type, resource_id)
    values (
      v_service.worker_id,
      'service_expiring',
      'Serviço será excluído em breve',
      'Os dados completos deste serviço serão excluídos em até 24 horas.',
      'service',
      v_service.id
    );
  end loop;
end;
$$;

-- Função para criar resumo histórico antes da exclusão
create or replace function public.create_service_summary(p_service_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_service record;
begin
  -- Busca dados do serviço
  select service_number, created_at, service_address, service_type
  into v_service
  from public.services
  where id = p_service_id;

  if not found then
    return;
  end if;

  -- Cria resumo se não existir
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

-- Função principal de limpeza
create or replace function public.cleanup_expired_services()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_service record;
  v_file record;
  v_deleted_count int := 0;
  v_error_count int := 0;
  v_errors jsonb := '[]'::jsonb;
begin
  -- Busca serviços expirados
  for v_service in
    select id, service_number
    from public.services
    where expires_at < now()
    order by expires_at asc
    limit 100  -- Processa em lotes
  loop
    begin
      -- 1. Cria resumo histórico
      perform public.create_service_summary(v_service.id);

      -- 2. Deleta arquivos do Storage (service_files aponta para eles)
      for v_file in
        select storage_path
        from public.service_files
        where service_id = v_service.id
      loop
        -- Marca para deleção (Edge Function fará a limpeza real do Storage)
        -- Por ora, apenas remove registro do banco
        null;
      end loop;

      -- 3. Deleta registros relacionados (cascata via FK)
      delete from public.service_files where service_id = v_service.id;
      delete from public.service_documents where service_id = v_service.id;
      delete from public.service_records where service_id = v_service.id;
      delete from public.notifications where resource_id = v_service.id;

      -- 4. Remove dados sensíveis do serviço, mantém só metadados
      update public.services
      set service_address = '[excluído]',
          updated_at = now()
      where id = v_service.id;

      -- Poderia deletar o serviço inteiro, mas manter registro vazio ajuda auditoria
      -- Alternativa: delete from public.services where id = v_service.id;

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
    'timestamp', now()
  );
end;
$$;

-- Grants (apenas para uso interno via Edge Function)
revoke all on function public.notify_expiring_services() from public, anon, authenticated;
revoke all on function public.create_service_summary(uuid) from public, anon, authenticated;
revoke all on function public.cleanup_expired_services() from public, anon, authenticated;

-- Service role pode executar (Edge Function usa service role)
grant execute on function public.notify_expiring_services() to service_role;
grant execute on function public.create_service_summary(uuid) to service_role;
grant execute on function public.cleanup_expired_services() to service_role;

-- Comentários
comment on function public.notify_expiring_services() is
  'Notifica usuários sobre serviços que expiram em 24-48h';
comment on function public.create_service_summary(uuid) is
  'Cria resumo histórico antes de excluir dados completos';
comment on function public.cleanup_expired_services() is
  'Limpa serviços expirados conforme política de retenção de 7 dias. Idempotente.';
