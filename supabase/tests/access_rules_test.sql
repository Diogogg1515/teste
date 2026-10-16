-- ============================================================
-- souza.l - Teste das regras de acesso (Etapa 3)
-- ============================================================
-- COMO USAR
--  1) Tenha 3 contas: um TRABALHADOR (role = worker), um CLIENTE A e
--     um CLIENTE B (role = client). Mude o role no Table Editor > profiles.
--  2) Pegue os IDs com:  select id, name, role from public.profiles;
--  3) Troque os tres IDs abaixo (linhas "TROQUE") e rode o script inteiro.
--  4) O resultado aparece numa MENSAGEM DE ERRO vermelha chamada
--     "RESULTADO DOS TESTES". Isso e proposital: o erro no final desfaz
--     tudo o que o teste criou, entao NADA fica gravado no banco.
--  5) Todas as linhas devem comecar com OK. Qualquer FALHOU = problema.
-- ============================================================

do $$
declare
  v_worker   uuid := '00000000-0000-0000-0000-000000000000'; -- TROQUE: id do trabalhador
  v_client_a uuid := '00000000-0000-0000-0000-000000000000'; -- TROQUE: id do cliente A
  v_client_b uuid := '00000000-0000-0000-0000-000000000000'; -- TROQUE: id do cliente B

  v_claim_worker text;
  v_claim_a text;
  v_claim_b text;

  v_out text := '';
  v_code text;
  v_n int;
  v_n2 int;
  v_n3 int;
  v_req uuid;
  v_req2 uuid;
  v_svc uuid;
  v_rec uuid;
begin
  -- ---------- Verificacoes iniciais (como administrador do banco) ----------
  if v_worker = '00000000-0000-0000-0000-000000000000'::uuid
     or v_client_a = '00000000-0000-0000-0000-000000000000'::uuid
     or v_client_b = '00000000-0000-0000-0000-000000000000'::uuid then
    raise exception 'Troque os tres IDs no topo do script pelos IDs das suas contas.';
  end if;

  if v_worker in (v_client_a, v_client_b) or v_client_a = v_client_b then
    raise exception 'Os tres IDs precisam ser de contas diferentes.';
  end if;

  if (select role from public.profiles where id = v_worker)
       is distinct from 'worker'::public.user_role then
    raise exception 'A conta do trabalhador precisa estar com role = worker.';
  end if;

  if (select role from public.profiles where id = v_client_a)
       is distinct from 'client'::public.user_role
     or (select role from public.profiles where id = v_client_b)
       is distinct from 'client'::public.user_role then
    raise exception 'As contas dos clientes precisam estar com role = client.';
  end if;

  v_claim_worker := json_build_object('sub', v_worker::text, 'role', 'authenticated')::text;
  v_claim_a      := json_build_object('sub', v_client_a::text, 'role', 'authenticated')::text;
  v_claim_b      := json_build_object('sub', v_client_b::text, 'role', 'authenticated')::text;

  select client_code into v_code from public.profiles where id = v_client_a;

  -- ---------- Pedidos ----------
  reset role; perform set_config('request.jwt.claims', v_claim_worker, true); set local role authenticated;
  select count(*) into v_n from public.find_client_by_code(v_code);
  v_out := v_out || case when v_n = 1 then 'OK     ' else 'FALHOU ' end
        || '01. Trabalhador acha o cliente pelo código' || E'\n';

  reset role; perform set_config('request.jwt.claims', v_claim_a, true); set local role authenticated;
  begin
    perform public.find_client_by_code(v_code);
    v_out := v_out || 'FALHOU 02. Cliente NAO deveria buscar clientes' || E'\n';
  exception when others then
    v_out := v_out || 'OK     02. Cliente não consegue buscar clientes (' || sqlerrm || ')' || E'\n';
  end;

  reset role; perform set_config('request.jwt.claims', v_claim_worker, true); set local role authenticated;
  begin
    v_req := public.create_service_request(v_client_a, 'Teste de pedido');
    v_out := v_out || 'OK     03. Trabalhador cria pedido para o cliente A' || E'\n';
  exception when others then
    v_out := v_out || 'FALHOU 03. Trabalhador deveria criar o pedido (' || sqlerrm || ')' || E'\n';
  end;

  begin
    perform public.create_service_request(v_client_a, 'Pedido repetido');
    v_out := v_out || 'FALHOU 04. Pedido pendente duplicado foi aceito' || E'\n';
  exception when others then
    v_out := v_out || 'OK     04. Pedido pendente duplicado bloqueado (' || sqlerrm || ')' || E'\n';
  end;

  reset role; perform set_config('request.jwt.claims', v_claim_b, true); set local role authenticated;
  select count(*) into v_n from public.service_requests;
  v_out := v_out || case when v_n = 0 then 'OK     ' else 'FALHOU ' end
        || '05. Cliente B não enxerga o pedido do cliente A' || E'\n';

  begin
    perform public.accept_service_request(v_req, 'Rua Teste, 123');
    v_out := v_out || 'FALHOU 06. Cliente B aceitou o pedido de outra pessoa' || E'\n';
  exception when others then
    v_out := v_out || 'OK     06. Cliente B não consegue aceitar o pedido do A (' || sqlerrm || ')' || E'\n';
  end;

  reset role; perform set_config('request.jwt.claims', v_claim_a, true); set local role authenticated;
  select count(*) into v_n from public.service_requests;
  v_out := v_out || case when v_n = 1 then 'OK     ' else 'FALHOU ' end
        || '07. Cliente A enxerga o próprio pedido' || E'\n';

  begin
    v_svc := public.accept_service_request(v_req, 'Rua Teste, 123');
    v_out := v_out || 'OK     08. Cliente A aceita o pedido e o serviço é criado' || E'\n';
  exception when others then
    v_out := v_out || 'FALHOU 08. Cliente A deveria aceitar (' || sqlerrm || ')' || E'\n';
  end;

  begin
    perform public.accept_service_request(v_req, 'Rua Teste, 123');
    v_out := v_out || 'FALHOU 09. Segundo aceite criou outro serviço' || E'\n';
  exception when others then
    v_out := v_out || 'OK     09. Aceite repetido bloqueado (' || sqlerrm || ')' || E'\n';
  end;

  -- ---------- Leitura dos servicos ----------
  select count(*) into v_n from public.services;
  reset role; perform set_config('request.jwt.claims', v_claim_b, true); set local role authenticated;
  select count(*) into v_n2 from public.services;
  reset role; perform set_config('request.jwt.claims', v_claim_worker, true); set local role authenticated;
  select count(*) into v_n3 from public.services;
  v_out := v_out || case when v_n = 1 and v_n2 = 0 and v_n3 = 1 then 'OK     ' else 'FALHOU ' end
        || '10. Serviço visível para A e para o trabalhador, invisível para B'
        || ' (A=' || v_n || ', B=' || v_n2 || ', trabalhador=' || v_n3 || ')' || E'\n';

  -- ---------- Status ----------
  reset role; perform set_config('request.jwt.claims', v_claim_a, true); set local role authenticated;
  begin
    update public.services set status = 'cancelled' where id = v_svc;
    v_out := v_out || 'FALHOU 11. Cliente conseguiu alterar o serviço direto' || E'\n';
  exception when others then
    v_out := v_out || 'OK     11. Cliente não altera o serviço direto (' || sqlerrm || ')' || E'\n';
  end;

  begin
    perform public.change_service_status(v_svc, 'cancelled');
    v_out := v_out || 'FALHOU 12. Cliente conseguiu mudar o status' || E'\n';
  exception when others then
    v_out := v_out || 'OK     12. Cliente não muda o status (' || sqlerrm || ')' || E'\n';
  end;

  -- ---------- Registros ----------
  begin
    insert into public.service_records (service_id, author_id, author_role, content)
    values (v_svc, v_client_a, 'client', 'Registro do cliente A');
    v_out := v_out || 'OK     13. Cliente A cria o próprio registro' || E'\n';
  exception when others then
    v_out := v_out || 'FALHOU 13. Cliente A deveria criar o registro (' || sqlerrm || ')' || E'\n';
  end;

  begin
    insert into public.service_records (service_id, author_id, author_role, content)
    values (v_svc, v_client_a, 'worker', 'Cliente fingindo ser trabalhador');
    v_out := v_out || 'FALHOU 14. Cliente criou registro como trabalhador' || E'\n';
  exception when others then
    v_out := v_out || 'OK     14. Cliente não cria registro como trabalhador (' || sqlerrm || ')' || E'\n';
  end;

  reset role; perform set_config('request.jwt.claims', v_claim_b, true); set local role authenticated;
  begin
    insert into public.service_records (service_id, author_id, author_role, content)
    values (v_svc, v_client_b, 'client', 'Cliente B em serviço de outro');
    v_out := v_out || 'FALHOU 15. Cliente B criou registro no serviço do A' || E'\n';
  exception when others then
    v_out := v_out || 'OK     15. Cliente B não cria registro no serviço do A (' || sqlerrm || ')' || E'\n';
  end;

  reset role; perform set_config('request.jwt.claims', v_claim_worker, true); set local role authenticated;
  begin
    insert into public.service_records (service_id, author_id, author_role, content)
    values (v_svc, v_worker, 'worker', 'Registro técnico do trabalhador');
    v_out := v_out || 'OK     16. Trabalhador cria o próprio registro' || E'\n';
  exception when others then
    v_out := v_out || 'FALHOU 16. Trabalhador deveria criar o registro (' || sqlerrm || ')' || E'\n';
  end;

  select count(*) into v_n3 from public.service_records;
  reset role; perform set_config('request.jwt.claims', v_claim_a, true); set local role authenticated;
  select count(*) into v_n from public.service_records;
  reset role; perform set_config('request.jwt.claims', v_claim_b, true); set local role authenticated;
  select count(*) into v_n2 from public.service_records;
  v_out := v_out || case when v_n = 2 and v_n2 = 0 and v_n3 = 2 then 'OK     ' else 'FALHOU ' end
        || '17. Registros: A e trabalhador veem os 2, B não vê nenhum'
        || ' (A=' || v_n || ', B=' || v_n2 || ', trabalhador=' || v_n3 || ')' || E'\n';

  reset role; perform set_config('request.jwt.claims', v_claim_a, true); set local role authenticated;
  begin
    update public.service_records set content = 'adulterado' where service_id = v_svc;
    v_out := v_out || 'FALHOU 18. Registro foi editado' || E'\n';
  exception when others then
    v_out := v_out || 'OK     18. Registros não podem ser editados (' || sqlerrm || ')' || E'\n';
  end;

  begin
    delete from public.service_records where service_id = v_svc;
    v_out := v_out || 'FALHOU 19. Registro foi apagado' || E'\n';
  exception when others then
    v_out := v_out || 'OK     19. Registros não podem ser apagados (' || sqlerrm || ')' || E'\n';
  end;

  -- ---------- Notificacoes e tabelas internas ----------
  select count(*) into v_n from public.notifications;
  reset role; perform set_config('request.jwt.claims', v_claim_b, true); set local role authenticated;
  select count(*) into v_n2 from public.notifications;
  reset role; perform set_config('request.jwt.claims', v_claim_worker, true); set local role authenticated;
  select count(*) into v_n3 from public.notifications;
  v_out := v_out || case when v_n >= 1 and v_n2 = 0 and v_n3 >= 1 then 'OK     ' else 'FALHOU ' end
        || '20. Cada pessoa vê só as próprias notificações'
        || ' (A=' || v_n || ', B=' || v_n2 || ', trabalhador=' || v_n3 || ')' || E'\n';

  reset role; perform set_config('request.jwt.claims', v_claim_a, true); set local role authenticated;
  begin
    insert into public.notifications (user_id, type, title) values (v_client_a, 'x', 'forjada');
    v_out := v_out || 'FALHOU 21. Cliente criou notificação' || E'\n';
  exception when others then
    v_out := v_out || 'OK     21. Cliente não cria notificações (' || sqlerrm || ')' || E'\n';
  end;

  begin
    perform 1 from public.audit_logs limit 1;
    v_out := v_out || 'FALHOU 22. Cliente leu audit_logs' || E'\n';
  exception when others then
    v_out := v_out || 'OK     22. Cliente não acessa audit_logs (' || sqlerrm || ')' || E'\n';
  end;

  reset role; perform set_config('request.jwt.claims', '', true); set local role anon;
  begin
    perform 1 from public.services limit 1;
    v_out := v_out || 'FALHOU 23. Visitante leu serviços' || E'\n';
  exception when others then
    v_out := v_out || 'OK     23. Visitante sem login não lê nada (' || sqlerrm || ')' || E'\n';
  end;

  -- ---------- Transicoes de status e bloqueio de registros ----------
  reset role; perform set_config('request.jwt.claims', v_claim_worker, true); set local role authenticated;
  begin
    perform public.change_service_status(v_svc, 'waiting_response');
    v_out := v_out || 'OK     24. Trabalhador muda para aguardando resposta' || E'\n';
  exception when others then
    v_out := v_out || 'FALHOU 24. Mudança válida foi recusada (' || sqlerrm || ')' || E'\n';
  end;

  reset role; perform set_config('request.jwt.claims', v_claim_a, true); set local role authenticated;
  begin
    insert into public.service_records (service_id, author_id, author_role, content)
    values (v_svc, v_client_a, 'client', 'Resposta do cliente');
    v_out := v_out || 'OK     25. Cliente responde enquanto aguarda resposta' || E'\n';
  exception when others then
    v_out := v_out || 'FALHOU 25. Cliente deveria poder responder (' || sqlerrm || ')' || E'\n';
  end;

  reset role; perform set_config('request.jwt.claims', v_claim_worker, true); set local role authenticated;
  begin
    perform public.change_service_status(v_svc, 'interrupted');
    v_out := v_out || 'FALHOU 26. Transição inválida foi aceita' || E'\n';
  exception when others then
    v_out := v_out || 'OK     26. Aguardando -> interrompido bloqueado (' || sqlerrm || ')' || E'\n';
  end;

  begin
    perform public.change_service_status(v_svc, 'completed');
    v_out := v_out || 'OK     27. Trabalhador conclui o serviço' || E'\n';
  exception when others then
    v_out := v_out || 'FALHOU 27. Concluir deveria funcionar (' || sqlerrm || ')' || E'\n';
  end;

  reset role; perform set_config('request.jwt.claims', v_claim_a, true); set local role authenticated;
  begin
    insert into public.service_records (service_id, author_id, author_role, content)
    values (v_svc, v_client_a, 'client', 'Registro depois de concluído');
    v_out := v_out || 'FALHOU 28. Registro criado em serviço concluído' || E'\n';
  exception when others then
    v_out := v_out || 'OK     28. Serviço concluído bloqueia novos registros (' || sqlerrm || ')' || E'\n';
  end;

  reset role; perform set_config('request.jwt.claims', v_claim_worker, true); set local role authenticated;
  begin
    perform public.change_service_status(v_svc, 'in_progress');
    v_out := v_out || 'FALHOU 29. Serviço concluído foi reaberto' || E'\n';
  exception when others then
    v_out := v_out || 'OK     29. Serviço concluído não volta atrás (' || sqlerrm || ')' || E'\n';
  end;

  -- ---------- Recusar e retirar pedidos ----------
  begin
    v_req2 := public.create_service_request(v_client_b, 'Pedido para o cliente B');
    v_out := v_out || 'OK     30. Trabalhador cria pedido para o cliente B' || E'\n';
  exception when others then
    v_out := v_out || 'FALHOU 30. Pedido para B deveria ser criado (' || sqlerrm || ')' || E'\n';
  end;

  reset role; perform set_config('request.jwt.claims', v_claim_a, true); set local role authenticated;
  begin
    perform public.reject_service_request(v_req2);
    v_out := v_out || 'FALHOU 31. Cliente A recusou pedido do cliente B' || E'\n';
  exception when others then
    v_out := v_out || 'OK     31. Cliente A não recusa pedido de outro (' || sqlerrm || ')' || E'\n';
  end;

  reset role; perform set_config('request.jwt.claims', v_claim_b, true); set local role authenticated;
  begin
    perform public.reject_service_request(v_req2);
    select count(*) into v_n from public.service_requests;
    v_out := v_out || case when v_n = 0 then 'OK     ' else 'FALHOU ' end
          || '32. Cliente B recusa e o pedido é excluído' || E'\n';
  exception when others then
    v_out := v_out || 'FALHOU 32. Recusa deveria funcionar (' || sqlerrm || ')' || E'\n';
  end;

  reset role; perform set_config('request.jwt.claims', v_claim_worker, true); set local role authenticated;
  begin
    v_req2 := public.create_service_request(v_client_b, 'Outro pedido para B');
    perform public.withdraw_service_request(v_req2);
    select count(*) into v_n from public.service_requests where client_id = v_client_b;
    v_out := v_out || case when v_n = 0 then 'OK     ' else 'FALHOU ' end
          || '33. Trabalhador retira o pedido pendente' || E'\n';
  exception when others then
    v_out := v_out || 'FALHOU 33. Retirar pedido deveria funcionar (' || sqlerrm || ')' || E'\n';
  end;

  -- ---------- Fim: mostra o resultado e DESFAZ tudo ----------
  reset role;
  raise exception E'RESULTADO DOS TESTES (nada foi gravado; tudo é desfeito no final)\n\n%', v_out;
end;
$$;

-- ------------------------------------------------------------
-- DEPOIS DOS TESTES (opcional):
-- O teste consome o numero 1 da sequencia de servicos, mesmo desfeito.
-- Se ainda NAO existir nenhum servico real, voce pode reiniciar a
-- contagem para o primeiro servico real ser o numero 1:
--
--   alter table public.services alter column service_number restart with 1;
--
-- Depois do teste, devolva o role das contas para 'client'.
-- ------------------------------------------------------------
