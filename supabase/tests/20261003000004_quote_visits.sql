-- ============================================================
-- souza.l - Teste da agenda de orcamentos (quote_visits)
-- ============================================================
-- Use as mesmas 3 contas do teste anterior:
--   TRABALHADOR (role = worker), CLIENTE A e CLIENTE B (role = client).
-- IDs:  select id, name, role from public.profiles;
-- VERSAO PRONTA: os 3 IDs ja foram preenchidos. Basta copiar tudo e rodar.
-- O resultado aparece numa MENSAGEM DE ERRO chamada "RESULTADO DOS TESTES".
-- Isso e proposital: o erro no final desfaz tudo (nada fica gravado).
-- Todas as linhas devem comecar com OK.
-- ============================================================

do $$
declare
  v_worker   uuid := '50640d77-7851-4786-b348-a931e88a67ee';
  v_client_a uuid := '381fde72-3ecc-4be4-bbc4-883aa119749e';
  v_client_b uuid := '482d7341-59e5-4926-b389-78750da444a1';

  v_claim_worker text;
  v_claim_a text;
  v_out text := '';
  v_n int;
  v_n2 int;
  v_visit uuid;
  v_tmp uuid;
  v_answered timestamptz;
begin
  if v_worker = '00000000-0000-0000-0000-000000000000'::uuid
     or v_client_a = '00000000-0000-0000-0000-000000000000'::uuid
     or v_client_b = '00000000-0000-0000-0000-000000000000'::uuid then
    raise exception 'Troque os tres IDs no topo do script.';
  end if;

  if (select role from public.profiles where id = v_worker)
       is distinct from 'worker'::public.user_role then
    raise exception 'A conta do trabalhador precisa estar com role = worker.';
  end if;

  v_claim_worker := json_build_object('sub', v_worker::text, 'role', 'authenticated')::text;
  v_claim_a      := json_build_object('sub', v_client_a::text, 'role', 'authenticated')::text;

  -- 1. Trabalhador cria uma visita
  reset role; perform set_config('request.jwt.claims', v_claim_worker, true); set local role authenticated;
  begin
    insert into public.quote_visits (client_name, address, scheduled_at)
    values ('Cliente de teste', 'Rua de teste, 100', now() + interval '1 day')
    returning id into v_visit;
    v_out := v_out || 'OK     01. Trabalhador cria uma visita' || E'\n';
  exception when others then
    v_out := v_out || 'FALHOU 01. Criar visita (' || sqlerrm || ')' || E'\n';
  end;

  -- 2. Trabalhador le a propria visita
  select count(*) into v_n from public.quote_visits where id = v_visit;
  v_out := v_out || case when v_n = 1 then 'OK     ' else 'FALHOU ' end
        || '02. Trabalhador enxerga a propria visita (' || v_n || ')' || E'\n';

  -- 3. Cliente A nao enxerga
  reset role; perform set_config('request.jwt.claims', v_claim_a, true); set local role authenticated;
  select count(*) into v_n from public.quote_visits;
  v_out := v_out || case when v_n = 0 then 'OK     ' else 'FALHOU ' end
        || '03. Cliente nao enxerga visitas (' || v_n || ')' || E'\n';

  -- 4. Cliente A nao cria visita
  begin
    insert into public.quote_visits (client_name, address, scheduled_at)
    values ('Invasor', 'Rua X', now());
    v_out := v_out || 'FALHOU 04. Cliente criou visita' || E'\n';
  exception when others then
    v_out := v_out || 'OK     04. Cliente nao cria visita (' || sqlerrm || ')' || E'\n';
  end;

  -- 5. Cliente A nao altera a visita do trabalhador
  v_tmp := null;
  update public.quote_visits set client_name = 'Adulterado' where id = v_visit returning id into v_tmp;
  v_out := v_out || case when v_tmp is null then 'OK     ' else 'FALHOU ' end
        || '05. Cliente nao altera visita de outra pessoa' || E'\n';

  -- 6. Cliente A nao apaga a visita do trabalhador
  v_tmp := null;
  delete from public.quote_visits where id = v_visit returning id into v_tmp;
  v_out := v_out || case when v_tmp is null then 'OK     ' else 'FALHOU ' end
        || '06. Cliente nao apaga visita de outra pessoa' || E'\n';

  -- 7. Ninguem escolhe o dono da visita
  reset role; perform set_config('request.jwt.claims', v_claim_worker, true); set local role authenticated;
  begin
    insert into public.quote_visits (worker_id, client_name, address, scheduled_at)
    values (v_client_a, 'Dono forjado', 'Rua Y', now());
    v_out := v_out || 'FALHOU 07. Trabalhador escolheu o dono da visita' || E'\n';
  exception when others then
    v_out := v_out || 'OK     07. Dono da visita nao pode ser escolhido (' || sqlerrm || ')' || E'\n';
  end;

  -- 8. Responder "Sim" grava a hora da resposta (gatilho)
  update public.quote_visits set status = 'done' where id = v_visit;
  select answered_at into v_answered from public.quote_visits where id = v_visit;
  v_out := v_out || case when v_answered is not null then 'OK     ' else 'FALHOU ' end
        || '08. Responder Sim marca a hora da resposta' || E'\n';

  -- 9. Reagendar limpa a resposta
  update public.quote_visits
  set status = 'scheduled', scheduled_at = now() + interval '2 days'
  where id = v_visit;
  select answered_at into v_answered from public.quote_visits where id = v_visit;
  v_out := v_out || case when v_answered is null then 'OK     ' else 'FALHOU ' end
        || '09. Reagendar limpa a resposta' || E'\n';

  -- 10. Vinculo com servico so por funcao do banco
  begin
    update public.quote_visits set service_id = gen_random_uuid() where id = v_visit;
    v_out := v_out || 'FALHOU 10. Trabalhador alterou o vinculo com servico' || E'\n';
  exception when others then
    v_out := v_out || 'OK     10. Vinculo com servico protegido (' || sqlerrm || ')' || E'\n';
  end;

  -- 11. Telefone invalido e nome curto sao recusados
  begin
    insert into public.quote_visits (client_name, address, scheduled_at, phone)
    values ('Nome valido', 'Rua Z', now(), '123');
    v_out := v_out || 'FALHOU 11. Telefone invalido aceito' || E'\n';
  exception when others then
    v_out := v_out || 'OK     11. Telefone invalido recusado' || E'\n';
  end;

  begin
    insert into public.quote_visits (client_name, address, scheduled_at)
    values ('A', 'Rua Z', now());
    v_out := v_out || 'FALHOU 12. Nome curto aceito' || E'\n';
  exception when others then
    v_out := v_out || 'OK     12. Nome curto recusado' || E'\n';
  end;

  -- 13. Visitante sem login nao le nada
  reset role; perform set_config('request.jwt.claims', '', true); set local role anon;
  begin
    perform 1 from public.quote_visits limit 1;
    v_out := v_out || 'FALHOU 13. Visitante leu a agenda' || E'\n';
  exception when others then
    v_out := v_out || 'OK     13. Visitante sem login nao le a agenda (' || sqlerrm || ')' || E'\n';
  end;

  -- 14. Trabalhador apaga a propria visita
  reset role; perform set_config('request.jwt.claims', v_claim_worker, true); set local role authenticated;
  delete from public.quote_visits where id = v_visit;
  select count(*) into v_n2 from public.quote_visits where id = v_visit;
  v_out := v_out || case when v_n2 = 0 then 'OK     ' else 'FALHOU ' end
        || '14. Trabalhador apaga a propria visita' || E'\n';

  reset role;
  raise exception E'RESULTADO DOS TESTES (nada foi gravado; tudo e desfeito no final)\n\n%', v_out;
end;
$$;