-- ============================================================
-- souza.l - Migration 06: apoio a pagina do servico
-- ============================================================
-- RODAR UMA VEZ, no SQL Editor do Supabase (cole tudo e clique em Run).
--
-- 1) get_service_counterpart: devolve o NOME da outra pessoa do servico
--    (o cliente ve o nome do profissional; o profissional ve o nome do
--    cliente). So funciona para quem participa do servico. Nao abre a
--    tabela de perfis: devolve apenas o nome.
-- 2) Gatilho: quando alguem adiciona um registro, a outra pessoa do
--    servico recebe uma notificacao.
-- ============================================================

create function public.get_service_counterpart(p_service_id uuid)
returns table (o_name text, o_role text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_svc public.services%rowtype;
begin
  if v_uid is null then
    return;
  end if;

  select * into v_svc
  from public.services s
  where s.id = p_service_id
    and v_uid in (s.client_id, s.worker_id);

  if not found then
    return;
  end if;

  if v_svc.client_id = v_uid then
    -- Quem consulta e o cliente: mostra o profissional
    return query
    select
      coalesce(
        (select wp.display_name from public.worker_profiles wp
          where wp.user_id = v_svc.worker_id),
        (select p.name from public.profiles p where p.id = v_svc.worker_id)
      ),
      'worker'::text;
  else
    -- Quem consulta e o profissional: mostra o cliente
    return query
    select
      (select p.name from public.profiles p where p.id = v_svc.client_id),
      'client'::text;
  end if;
end;
$$;

revoke all on function public.get_service_counterpart(uuid) from public, anon;
grant execute on function public.get_service_counterpart(uuid) to authenticated;


create function public.notify_on_new_record()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_svc public.services%rowtype;
  v_target uuid;
begin
  select * into v_svc from public.services where id = new.service_id;

  if not found then
    return new;
  end if;

  v_target := case
    when new.author_id = v_svc.client_id then v_svc.worker_id
    else v_svc.client_id
  end;

  insert into public.notifications (
    user_id, type, title, message, resource_type, resource_id
  )
  values (
    v_target,
    'service_record_added',
    'Novo registro no serviço',
    case
      when new.author_role = 'client' then 'O cliente adicionou um registro ao serviço.'
      else 'O trabalhador adicionou um registro ao serviço.'
    end,
    'service',
    v_svc.id
  );

  return new;
end;
$$;

create trigger notify_on_new_record
  after insert on public.service_records
  for each row execute function public.notify_on_new_record();

revoke execute on function public.notify_on_new_record() from public, anon, authenticated;
