-- ============================================================
-- souza.l - Teste do apoio a pagina do servico (migration 06)
-- ============================================================
-- VERSAO PRONTA: os 3 IDs ja estao preenchidos.
-- Copie tudo e rode no SQL Editor. O resultado aparece numa MENSAGEM DE
-- ERRO chamada "RESULTADO DOS TESTES": e proposital, desfaz tudo.
-- Todas as linhas devem comecar com OK.
-- ============================================================

do $$
declare
  v_worker   uuid := '50640d77-7851-4786-b348-a931e88a67ee';
  v_client_a uuid := '381fde72-3ecc-4be4-bbc4-883aa119749e';
  v_client_b uuid := '482d7341-59e5-4926-b389-78750da444a1';

  v_claim_worker text;
  v_claim_a text;
  v_claim_b text;
  v_out text := '';
  v_n int;
  v_tok text;
  v_svc uuid;
  v_name text;
  v_role text;
begin
  if (select role from public.profiles where id = v_worker)
       is distinct from 'worker'::public.user_role then
    raise exception 'A conta do trabalhador precisa estar com role = worker.';
  end if;

  v_claim_worker := json_build_object('sub', v_worker::text, 'role', 'authenticated')::text;
  v_claim_a      := json_build_object('sub', v_client_a::text, 'role', 'authenticated')::text;
  v_claim_b      := json_build_object('sub', v_client_b::text, 'role', 'authenticated')::text;

  -- Preparacao: um servico criado por convite (cliente A + trabalhador)
  reset role; perform set_config('request.jwt.claims', v_claim_worker, true); set local role authenticated;
  v_tok := public.create_service_invite('Teste pagina', 'Cliente A');
  reset role; perform set_config('request.jwt.claims', v_claim_a, true); set local role authenticated;
  v_svc := public.redeem_service_invite(v_tok, 'Rua do teste, 100');

  -- 01. Cliente ve o nome do profissional
  select o_name, o_role into v_name, v_role from public.get_service_counterpart(v_svc);
  v_out := v_out || case when v_name is not null and v_role = 'worker' then 'OK     ' else 'FALHOU ' end
        || '01. Cliente vê o nome do profissional (papel: ' || coalesce(v_role, '?') || ')' || E'\n';

  -- 02. Profissional ve o nome do cliente
  reset role; perform set_config('request.jwt.claims', v_claim_worker, true); set local role authenticated;
  select o_name, o_role into v_name, v_role from public.get_service_counterpart(v_svc);
  v_out := v_out || case when v_name is not null and v_role = 'client' then 'OK     ' else 'FALHOU ' end
        || '02. Profissional vê o nome do cliente (papel: ' || coalesce(v_role, '?') || ')' || E'\n';

  -- 03. Outro cliente nao ve nada
  reset role; perform set_config('request.jwt.claims', v_claim_b, true); set local role authenticated;
  select count(*) into v_n from public.get_service_counterpart(v_svc);
  v_out := v_out || case when v_n = 0 then 'OK     ' else 'FALHOU ' end
        || '03. Cliente de fora não vê o nome de ninguém (' || v_n || ')' || E'\n';

  -- 04. Visitante sem login nao chama a funcao
  reset role; perform set_config('request.jwt.claims', '', true); set local role anon;
  begin
    perform 1 from public.get_service_counterpart(v_svc);
    v_out := v_out || 'FALHOU 04. Visitante chamou a função' || E'\n';
  exception when others then
    v_out := v_out || 'OK     04. Visitante sem login não chama a função (' || sqlerrm || ')' || E'\n';
  end;

  -- 05. Registro do cliente avisa o profissional
  reset role; perform set_config('request.jwt.claims', v_claim_a, true); set local role authenticated;
  insert into public.service_records (service_id, author_id, author_role, content)
  values (v_svc, v_client_a, 'client', 'Registro do cliente');

  select count(*) into v_n from public.notifications where type = 'service_record_added';
  v_out := v_out || case when v_n = 0 then 'OK     ' else 'FALHOU ' end
        || '05a. Quem registra não recebe aviso do próprio registro (' || v_n || ')' || E'\n';

  reset role; perform set_config('request.jwt.claims', v_claim_worker, true); set local role authenticated;
  select count(*) into v_n from public.notifications
  where type = 'service_record_added' and resource_id = v_svc;
  v_out := v_out || case when v_n = 1 then 'OK     ' else 'FALHOU ' end
        || '05b. Profissional é avisado do registro do cliente (' || v_n || ')' || E'\n';

  -- 06. Registro do profissional avisa o cliente
  insert into public.service_records (service_id, author_id, author_role, content)
  values (v_svc, v_worker, 'worker', 'Registro do profissional');

  reset role; perform set_config('request.jwt.claims', v_claim_a, true); set local role authenticated;
  select count(*) into v_n from public.notifications
  where type = 'service_record_added' and resource_id = v_svc;
  v_out := v_out || case when v_n = 1 then 'OK     ' else 'FALHOU ' end
        || '06. Cliente é avisado do registro do profissional (' || v_n || ')' || E'\n';

  -- 07. Interrompido bloqueia registros; aguardando resposta libera
  reset role; perform set_config('request.jwt.claims', v_claim_worker, true); set local role authenticated;
  perform public.change_service_status(v_svc, 'interrupted');

  reset role; perform set_config('request.jwt.claims', v_claim_a, true); set local role authenticated;
  begin
    insert into public.service_records (service_id, author_id, author_role, content)
    values (v_svc, v_client_a, 'client', 'Registro com serviço interrompido');
    v_out := v_out || 'FALHOU 07a. Registro criado com serviço interrompido' || E'\n';
  exception when others then
    v_out := v_out || 'OK     07a. Serviço interrompido bloqueia registros' || E'\n';
  end;

  reset role; perform set_config('request.jwt.claims', v_claim_worker, true); set local role authenticated;
  perform public.change_service_status(v_svc, 'in_progress');
  perform public.change_service_status(v_svc, 'waiting_response');

  reset role; perform set_config('request.jwt.claims', v_claim_a, true); set local role authenticated;
  begin
    insert into public.service_records (service_id, author_id, author_role, content)
    values (v_svc, v_client_a, 'client', 'Resposta do cliente');
    v_out := v_out || 'OK     07b. Cliente responde enquanto aguarda resposta' || E'\n';
  exception when others then
    v_out := v_out || 'FALHOU 07b. Resposta deveria ser aceita (' || sqlerrm || ')' || E'\n';
  end;

  reset role;
  raise exception E'RESULTADO DOS TESTES (nada foi gravado; tudo e desfeito no final)\n\n%', v_out;
end;
$$;
