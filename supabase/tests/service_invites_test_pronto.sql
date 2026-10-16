-- ============================================================
-- souza.l - Teste do convite por link (service_invites)
-- ============================================================
-- VERSAO PRONTA: os 3 IDs ja estao preenchidos (trabalhador e dois clientes).
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
  v_n2 int;
  v_tok text;
  v_tok2 text;
  v_tok3 text;
  v_tok4 text;
  v_svc uuid;
  v_svc2 uuid;
  v_visit uuid;
  v_linked uuid;
  v_state text;
  v_name text;
begin
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

  -- 01. Trabalhador cria convite
  reset role; perform set_config('request.jwt.claims', v_claim_worker, true); set local role authenticated;
  begin
    v_tok := public.create_service_invite('Teste convite', 'Cliente do convite');
    v_out := v_out || case when char_length(v_tok) = 64 then 'OK     ' else 'FALHOU ' end
          || '01. Trabalhador cria o convite e recebe o código (64 caracteres)' || E'\n';
  exception when others then
    v_out := v_out || 'FALHOU 01. Criar convite (' || sqlerrm || ')' || E'\n';
  end;

  -- 02. Trabalhador le o proprio convite
  select count(*) into v_n from public.service_invites where client_label = 'Cliente do convite';
  v_out := v_out || case when v_n = 1 then 'OK     ' else 'FALHOU ' end
        || '02. Trabalhador enxerga o próprio convite (' || v_n || ')' || E'\n';

  -- 03. Ninguem le o hash do codigo
  begin
    perform token_hash from public.service_invites limit 1;
    v_out := v_out || 'FALHOU 03. Trabalhador leu o hash do código' || E'\n';
  exception when others then
    v_out := v_out || 'OK     03. O hash do código não pode ser lido (' || sqlerrm || ')' || E'\n';
  end;

  -- 04. Nao escreve direto na tabela
  begin
    insert into public.service_invites (token_hash, service_type, client_label)
    values (repeat('a', 64), 'Falso', 'Falso');
    v_out := v_out || 'FALHOU 04. Inserção direta aceita' || E'\n';
  exception when others then
    v_out := v_out || 'OK     04. Não se escreve direto na tabela (' || sqlerrm || ')' || E'\n';
  end;

  -- 05. Cliente nao cria convite
  reset role; perform set_config('request.jwt.claims', v_claim_a, true); set local role authenticated;
  begin
    perform public.create_service_invite('Servico', 'Fulano');
    v_out := v_out || 'FALHOU 05. Cliente criou convite' || E'\n';
  exception when others then
    v_out := v_out || case when sqlerrm like '%not_allowed%' then 'OK     ' else 'FALHOU ' end
          || '05. Cliente não cria convite (' || sqlerrm || ')' || E'\n';
  end;

  -- 06. Visitante ve a previa de um convite valido
  reset role; perform set_config('request.jwt.claims', '', true); set local role anon;
  begin
    select o_state, o_worker_name into v_state, v_name
    from public.preview_service_invite(v_tok);
    v_out := v_out || case when v_state = 'valid' and v_name is not null then 'OK     ' else 'FALHOU ' end
          || '06. Visitante vê a prévia (estado: ' || coalesce(v_state, '?') || ')' || E'\n';
  exception when others then
    v_out := v_out || 'FALHOU 06. Prévia para visitante (' || sqlerrm || ')' || E'\n';
  end;

  -- 07. Codigo falso nao devolve nada
  select count(*) into v_n from public.preview_service_invite(repeat('0', 64));
  select count(*) into v_n2 from public.preview_service_invite('abc');
  v_out := v_out || case when v_n = 0 and v_n2 = 0 then 'OK     ' else 'FALHOU ' end
        || '07. Código falso ou malformado não devolve nada' || E'\n';

  -- 08. Visitante nao le a tabela de convites
  begin
    perform 1 from public.service_invites limit 1;
    v_out := v_out || 'FALHOU 08. Visitante leu a tabela de convites' || E'\n';
  exception when others then
    v_out := v_out || 'OK     08. Visitante não lê a tabela de convites (' || sqlerrm || ')' || E'\n';
  end;

  -- 09. Trabalhador nao aceita convite (so cliente)
  reset role; perform set_config('request.jwt.claims', v_claim_worker, true); set local role authenticated;
  begin
    perform public.redeem_service_invite(v_tok, 'Rua do teste, 200');
    v_out := v_out || 'FALHOU 09. Trabalhador aceitou convite' || E'\n';
  exception when others then
    v_out := v_out || case when sqlerrm like '%not_allowed%' then 'OK     ' else 'FALHOU ' end
          || '09. Só cliente aceita convite (' || sqlerrm || ')' || E'\n';
  end;

  -- 10. Endereco curto e recusado
  reset role; perform set_config('request.jwt.claims', v_claim_a, true); set local role authenticated;
  begin
    perform public.redeem_service_invite(v_tok, 'Rua');
    v_out := v_out || 'FALHOU 10. Endereço curto aceito' || E'\n';
  exception when others then
    v_out := v_out || case when sqlerrm like '%invalid_address%' then 'OK     ' else 'FALHOU ' end
          || '10. Endereço curto é recusado (' || sqlerrm || ')' || E'\n';
  end;

  -- 11. Cliente A aceita: o servico nasce
  begin
    v_svc := public.redeem_service_invite(v_tok, 'Rua do teste, 200');
    select count(*) into v_n from public.services
    where id = v_svc and client_id = v_client_a and worker_id = v_worker and status = 'in_progress';
    v_out := v_out || case when v_n = 1 then 'OK     ' else 'FALHOU ' end
          || '11. Cliente A aceita e o serviço nasce em andamento' || E'\n';
  exception when others then
    v_out := v_out || 'FALHOU 11. Aceitar convite (' || sqlerrm || ')' || E'\n';
  end;

  -- 12. Segundo uso do mesmo convite
  reset role; perform set_config('request.jwt.claims', v_claim_b, true); set local role authenticated;
  begin
    perform public.redeem_service_invite(v_tok, 'Rua do teste, 300');
    v_out := v_out || 'FALHOU 12. Convite usado duas vezes' || E'\n';
  exception when others then
    v_out := v_out || case when sqlerrm like '%invite_already_used%' then 'OK     ' else 'FALHOU ' end
          || '12. O convite vale uma vez só (' || sqlerrm || ')' || E'\n';
  end;

  -- 13. Previa mostra "aceito"
  reset role; perform set_config('request.jwt.claims', '', true); set local role anon;
  select o_state into v_state from public.preview_service_invite(v_tok);
  v_out := v_out || case when v_state = 'accepted' then 'OK     ' else 'FALHOU ' end
        || '13. Previa passa a mostrar convite aceito (' || coalesce(v_state, '?') || ')' || E'\n';

  -- 14. Trabalhador recebeu a notificacao
  reset role; perform set_config('request.jwt.claims', v_claim_worker, true); set local role authenticated;
  select count(*) into v_n from public.notifications where type = 'invite_accepted';
  v_out := v_out || case when v_n >= 1 then 'OK     ' else 'FALHOU ' end
        || '14. Trabalhador é avisado do aceite (' || v_n || ')' || E'\n';

  -- 15. Cliente B nao ve convites do trabalhador
  reset role; perform set_config('request.jwt.claims', v_claim_b, true); set local role authenticated;
  select count(*) into v_n from public.service_invites;
  v_out := v_out || case when v_n = 0 then 'OK     ' else 'FALHOU ' end
        || '15. Cliente não enxerga convites (' || v_n || ')' || E'\n';

  -- 16. Cancelamento
  reset role; perform set_config('request.jwt.claims', v_claim_worker, true); set local role authenticated;
  v_tok2 := public.create_service_invite('Teste cancelar', 'Cliente cancelar');

  reset role; perform set_config('request.jwt.claims', v_claim_b, true); set local role authenticated;
  begin
    perform public.cancel_service_invite((select id from public.service_invites limit 1));
    v_out := v_out || 'FALHOU 16a. Cliente cancelou convite' || E'\n';
  exception when others then
    v_out := v_out || 'OK     16a. Cliente não cancela convite do profissional' || E'\n';
  end;

  reset role; perform set_config('request.jwt.claims', v_claim_worker, true); set local role authenticated;
  begin
    perform public.cancel_service_invite(
      (select id from public.service_invites where client_label = 'Cliente cancelar'));
    v_out := v_out || 'OK     16b. Trabalhador cancela o próprio convite' || E'\n';
  exception when others then
    v_out := v_out || 'FALHOU 16b. Cancelar convite (' || sqlerrm || ')' || E'\n';
  end;

  reset role; perform set_config('request.jwt.claims', v_claim_b, true); set local role authenticated;
  begin
    perform public.redeem_service_invite(v_tok2, 'Rua do teste, 400');
    v_out := v_out || 'FALHOU 16c. Convite cancelado foi aceito' || E'\n';
  exception when others then
    v_out := v_out || case when sqlerrm like '%invite_cancelled%' then 'OK     ' else 'FALHOU ' end
          || '16c. Convite cancelado não pode ser aceito (' || sqlerrm || ')' || E'\n';
  end;

  -- 17. Convite expirado
  reset role; perform set_config('request.jwt.claims', v_claim_worker, true); set local role authenticated;
  v_tok3 := public.create_service_invite('Teste expirar', 'Cliente expirar');
  reset role;
  update public.service_invites
  set expires_at = now() - interval '1 hour'
  where token_hash = public.invite_token_hash(v_tok3);

  perform set_config('request.jwt.claims', v_claim_b, true); set local role authenticated;
  begin
    perform public.redeem_service_invite(v_tok3, 'Rua do teste, 500');
    v_out := v_out || 'FALHOU 17a. Convite expirado foi aceito' || E'\n';
  exception when others then
    v_out := v_out || case when sqlerrm like '%invite_expired%' then 'OK     ' else 'FALHOU ' end
          || '17a. Convite expirado não pode ser aceito (' || sqlerrm || ')' || E'\n';
  end;

  reset role; perform set_config('request.jwt.claims', '', true); set local role anon;
  select o_state into v_state from public.preview_service_invite(v_tok3);
  v_out := v_out || case when v_state = 'expired' then 'OK     ' else 'FALHOU ' end
        || '17b. Previa mostra convite expirado (' || coalesce(v_state, '?') || ')' || E'\n';

  -- 18. Convite ligado a uma visita da agenda
  reset role; perform set_config('request.jwt.claims', v_claim_worker, true); set local role authenticated;
  insert into public.quote_visits (client_name, address, scheduled_at)
  values ('Cliente da visita', 'Rua da visita, 10', now() - interval '3 hours')
  returning id into v_visit;

  v_tok4 := public.create_service_invite('Teste visita', 'Cliente da visita', v_visit);

  reset role; perform set_config('request.jwt.claims', v_claim_b, true); set local role authenticated;
  v_svc2 := public.redeem_service_invite(v_tok4, 'Rua do teste, 600');

  reset role; perform set_config('request.jwt.claims', v_claim_worker, true); set local role authenticated;
  select service_id into v_linked from public.quote_visits where id = v_visit;
  v_out := v_out || case when v_linked is not null and v_linked = v_svc2 then 'OK     ' else 'FALHOU ' end
        || '18a. A visita da agenda fica ligada ao serviço criado' || E'\n';

  begin
    perform public.create_service_invite('Outro', 'Cliente da visita', v_visit);
    v_out := v_out || 'FALHOU 18b. Visita já convertida aceitou novo convite' || E'\n';
  exception when others then
    v_out := v_out || case when sqlerrm like '%visit_already_converted%' then 'OK     ' else 'FALHOU ' end
          || '18b. Visita já convertida não gera outro convite (' || sqlerrm || ')' || E'\n';
  end;

  -- 19. Visita inexistente e dados invalidos
  begin
    perform public.create_service_invite('Servico', 'Fulano', gen_random_uuid());
    v_out := v_out || 'FALHOU 19a. Visita inexistente aceita' || E'\n';
  exception when others then
    v_out := v_out || case when sqlerrm like '%visit_not_found%' then 'OK     ' else 'FALHOU ' end
          || '19a. Visita inexistente é recusada (' || sqlerrm || ')' || E'\n';
  end;

  begin
    perform public.create_service_invite('A', 'Fulano');
    v_out := v_out || 'FALHOU 19b. Tipo de serviço curto aceito' || E'\n';
  exception when others then
    v_out := v_out || case when sqlerrm like '%invalid_service_type%' then 'OK     ' else 'FALHOU ' end
          || '19b. Tipo de serviço curto é recusado (' || sqlerrm || ')' || E'\n';
  end;

  reset role;
  raise exception E'RESULTADO DOS TESTES (nada foi gravado; tudo e desfeito no final)\n\n%', v_out;
end;
$$;
