-- ============================================================
-- souza.l - Teste do upload de fotos (Parte 5, migrations 07 a 10)
-- ============================================================
-- Copie tudo e rode no SQL Editor do Supabase.
-- O resultado aparece numa MENSAGEM DE ERRO chamada "RESULTADO DOS TESTES".
-- Isso e proposital: o erro no final desfaz tudo (nada fica gravado).
-- Todas as linhas devem comecar com OK.
-- Contas: as mesmas dos testes anteriores (1 trabalhador e 2 clientes).
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
  v_tok1 text;
  v_tok2 text;
  v_svc1 uuid;    -- servico do trabalhador com o cliente A (fica em andamento)
  v_svc2 uuid;    -- servico do trabalhador com o cliente B (sera concluido)
  v_rec_w uuid;   -- registro do trabalhador no servico 1
  v_rec_w2 uuid;  -- registro do trabalhador no servico 2
begin
  -- ----------------------------------------------------------
  -- Conferencias iniciais (avisam se alguma migration faltou)
  -- ----------------------------------------------------------
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

  if not exists (
    select 1 from storage.buckets where id = 'service-files' and public = false
  ) then
    raise exception 'Bucket service-files nao existe ou esta publico (migration 07).';
  end if;

  if (select count(*) from pg_policies
      where schemaname = 'storage' and tablename = 'objects'
        and (policyname like 'Participante pode enviar arquivos para o servi%'
          or policyname like 'Participante pode baixar arquivos do servi%')) <> 2 then
    raise exception 'Faltam as duas regras do Storage (migration 08).';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'service_files'
      and policyname = 'Participante pode enviar arquivo'
  ) then
    raise exception 'Falta a regra de envio em service_files (migration 09).';
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.service_files'::regclass
      and conname = 'service_files_file_type_mime_check'
  ) then
    raise exception 'Faltam as regras de tamanho e tipo (migration 10).';
  end if;

  v_claim_worker := json_build_object('sub', v_worker::text, 'role', 'authenticated')::text;
  v_claim_a      := json_build_object('sub', v_client_a::text, 'role', 'authenticated')::text;
  v_claim_b      := json_build_object('sub', v_client_b::text, 'role', 'authenticated')::text;

  -- ----------------------------------------------------------
  -- Preparacao: dois servicos criados por convite
  --   servico 1 = trabalhador + cliente A
  --   servico 2 = trabalhador + cliente B
  -- ----------------------------------------------------------
  reset role; perform set_config('request.jwt.claims', v_claim_worker, true); set local role authenticated;
  v_tok1 := public.create_service_invite('Teste fotos A', 'Cliente A');
  v_tok2 := public.create_service_invite('Teste fotos B', 'Cliente B');

  reset role; perform set_config('request.jwt.claims', v_claim_a, true); set local role authenticated;
  v_svc1 := public.redeem_service_invite(v_tok1, 'Rua do teste, 100');

  reset role; perform set_config('request.jwt.claims', v_claim_b, true); set local role authenticated;
  v_svc2 := public.redeem_service_invite(v_tok2, 'Rua do teste, 200');

  -- Um registro do trabalhador em cada servico
  reset role; perform set_config('request.jwt.claims', v_claim_worker, true); set local role authenticated;
  insert into public.service_records (service_id, author_id, author_role, content)
  values (v_svc1, v_worker, 'worker', 'Registro do trabalhador no servico 1')
  returning id into v_rec_w;

  insert into public.service_records (service_id, author_id, author_role, content)
  values (v_svc2, v_worker, 'worker', 'Registro do trabalhador no servico 2')
  returning id into v_rec_w2;

  -- ==========================================================
  -- PARTE A: tabela service_files
  -- ==========================================================

  -- 01. Trabalhador envia foto no servico 1
  reset role; perform set_config('request.jwt.claims', v_claim_worker, true); set local role authenticated;
  begin
    insert into public.service_files
      (service_id, uploaded_by, file_type, storage_path, original_name, mime_type, file_size)
    values
      (v_svc1, v_worker, 'photo', v_svc1::text || '/a.jpg', 'a.jpg', 'image/jpeg', 102400);
    v_out := v_out || 'OK     01. Trabalhador registra foto no servico' || E'\n';
  exception when others then
    v_out := v_out || 'FALHOU 01. Trabalhador registra foto (' || sqlerrm || ')' || E'\n';
  end;

  -- 02. Cliente A envia foto no servico 1
  reset role; perform set_config('request.jwt.claims', v_claim_a, true); set local role authenticated;
  begin
    insert into public.service_files
      (service_id, uploaded_by, file_type, storage_path, original_name, mime_type, file_size)
    values
      (v_svc1, v_client_a, 'photo', v_svc1::text || '/b.png', 'b.png', 'image/png', 204800);
    v_out := v_out || 'OK     02. Cliente registra foto no servico' || E'\n';
  exception when others then
    v_out := v_out || 'FALHOU 02. Cliente registra foto (' || sqlerrm || ')' || E'\n';
  end;

  -- 03. Cliente A nao registra foto em nome do trabalhador (uploaded_by forjado)
  begin
    insert into public.service_files
      (service_id, uploaded_by, file_type, storage_path, original_name, mime_type, file_size)
    values
      (v_svc1, v_worker, 'photo', v_svc1::text || '/forjada.jpg', 'forjada.jpg', 'image/jpeg', 1000);
    v_out := v_out || 'FALHOU 03. Foto registrada em nome de outra pessoa' || E'\n';
  exception when others then
    v_out := v_out || case when sqlerrm like '%row-level security%' then 'OK     ' else 'FALHOU ' end
          || '03. Nao se registra foto em nome de outra pessoa (' || sqlerrm || ')' || E'\n';
  end;

  -- 04. Cliente A nao liga a foto ao registro do trabalhador
  begin
    insert into public.service_files
      (service_id, record_id, uploaded_by, file_type, storage_path, original_name, mime_type, file_size)
    values
      (v_svc1, v_rec_w, v_client_a, 'photo', v_svc1::text || '/reg.jpg', 'reg.jpg', 'image/jpeg', 1000);
    v_out := v_out || 'FALHOU 04. Foto ligada ao registro de outra pessoa' || E'\n';
  exception when others then
    v_out := v_out || case when sqlerrm like '%row-level security%' then 'OK     ' else 'FALHOU ' end
          || '04. Nao se liga foto ao registro de outra pessoa (' || sqlerrm || ')' || E'\n';
  end;

  -- 05. Cliente B (nao participa do servico 1) nao registra foto nele
  reset role; perform set_config('request.jwt.claims', v_claim_b, true); set local role authenticated;
  begin
    insert into public.service_files
      (service_id, uploaded_by, file_type, storage_path, original_name, mime_type, file_size)
    values
      (v_svc1, v_client_b, 'photo', v_svc1::text || '/invasor.jpg', 'invasor.jpg', 'image/jpeg', 1000);
    v_out := v_out || 'FALHOU 05. Quem nao participa registrou foto' || E'\n';
  exception when others then
    v_out := v_out || case when sqlerrm like '%row-level security%' then 'OK     ' else 'FALHOU ' end
          || '05. Quem nao participa nao registra foto (' || sqlerrm || ')' || E'\n';
  end;

  -- 06. Trabalhador liga a foto ao proprio registro
  reset role; perform set_config('request.jwt.claims', v_claim_worker, true); set local role authenticated;
  begin
    insert into public.service_files
      (service_id, record_id, uploaded_by, file_type, storage_path, original_name, mime_type, file_size)
    values
      (v_svc1, v_rec_w, v_worker, 'photo', v_svc1::text || '/reg.jpg', 'reg.jpg', 'image/webp', 300000);
    v_out := v_out || 'OK     06. Trabalhador liga a foto ao proprio registro' || E'\n';
  exception when others then
    v_out := v_out || 'FALHOU 06. Ligar foto ao proprio registro (' || sqlerrm || ')' || E'\n';
  end;

  -- 07. Registro de OUTRO servico (mesmo sendo dele) nao serve
  begin
    insert into public.service_files
      (service_id, record_id, uploaded_by, file_type, storage_path, original_name, mime_type, file_size)
    values
      (v_svc1, v_rec_w2, v_worker, 'photo', v_svc1::text || '/reg2.jpg', 'reg2.jpg', 'image/jpeg', 1000);
    v_out := v_out || 'FALHOU 07. Foto ligada a registro de outro servico' || E'\n';
  exception when others then
    v_out := v_out || case when sqlerrm like '%row-level security%' then 'OK     ' else 'FALHOU ' end
          || '07. Nao se liga foto a registro de outro servico (' || sqlerrm || ')' || E'\n';
  end;

  -- 08. Caminho da pasta de outro servico e recusado
  begin
    insert into public.service_files
      (service_id, uploaded_by, file_type, storage_path, original_name, mime_type, file_size)
    values
      (v_svc1, v_worker, 'photo', v_svc2::text || '/x.jpg', 'x.jpg', 'image/jpeg', 1000);
    v_out := v_out || 'FALHOU 08. Caminho de outro servico aceito' || E'\n';
  exception when others then
    v_out := v_out || case when sqlerrm like '%row-level security%' then 'OK     ' else 'FALHOU ' end
          || '08. Caminho de outro servico e recusado (' || sqlerrm || ')' || E'\n';
  end;

  -- 09. Tipo de arquivo que nao e foto e recusado
  begin
    insert into public.service_files
      (service_id, uploaded_by, file_type, storage_path, original_name, mime_type, file_size)
    values
      (v_svc1, v_worker, 'document', v_svc1::text || '/doc.jpg', 'doc.jpg', 'image/jpeg', 1000);
    v_out := v_out || 'FALHOU 09. Tipo document aceito' || E'\n';
  exception when others then
    v_out := v_out || case when sqlerrm like '%row-level security%' then 'OK     ' else 'FALHOU ' end
          || '09. So foto e aceita (' || sqlerrm || ')' || E'\n';
  end;

  -- 10. PDF como foto e recusado
  begin
    insert into public.service_files
      (service_id, uploaded_by, file_type, storage_path, original_name, mime_type, file_size)
    values
      (v_svc1, v_worker, 'photo', v_svc1::text || '/f.pdf', 'f.pdf', 'application/pdf', 1000);
    v_out := v_out || 'FALHOU 10. PDF aceito como foto' || E'\n';
  exception when others then
    v_out := v_out || case when sqlerrm like '%check constraint%' then 'OK     ' else 'FALHOU ' end
          || '10. Tipo de imagem invalido e recusado (' || sqlerrm || ')' || E'\n';
  end;

  -- 11. Tamanho zero e recusado
  begin
    insert into public.service_files
      (service_id, uploaded_by, file_type, storage_path, original_name, mime_type, file_size)
    values
      (v_svc1, v_worker, 'photo', v_svc1::text || '/zero.jpg', 'zero.jpg', 'image/jpeg', 0);
    v_out := v_out || 'FALHOU 11. Tamanho zero aceito' || E'\n';
  exception when others then
    v_out := v_out || case when sqlerrm like '%check constraint%' then 'OK     ' else 'FALHOU ' end
          || '11. Tamanho zero e recusado (' || sqlerrm || ')' || E'\n';
  end;

  -- 12. Arquivo maior que 10 MB e recusado
  begin
    insert into public.service_files
      (service_id, uploaded_by, file_type, storage_path, original_name, mime_type, file_size)
    values
      (v_svc1, v_worker, 'photo', v_svc1::text || '/grande.jpg', 'grande.jpg', 'image/jpeg', 10485761);
    v_out := v_out || 'FALHOU 12. Arquivo maior que 10 MB aceito' || E'\n';
  exception when others then
    v_out := v_out || case when sqlerrm like '%check constraint%' then 'OK     ' else 'FALHOU ' end
          || '12. Arquivo maior que 10 MB e recusado (' || sqlerrm || ')' || E'\n';
  end;

  -- 13. Foto sem tipo de imagem informado e recusada
  begin
    insert into public.service_files
      (service_id, uploaded_by, file_type, storage_path, original_name, mime_type, file_size)
    values
      (v_svc1, v_worker, 'photo', v_svc1::text || '/semtipo.jpg', 'semtipo.jpg', null, 1000);
    v_out := v_out || 'FALHOU 13. Foto sem tipo aceita' || E'\n';
  exception when others then
    v_out := v_out || case when sqlerrm like '%check constraint%' then 'OK     ' else 'FALHOU ' end
          || '13. Foto sem tipo de imagem e recusada (' || sqlerrm || ')' || E'\n';
  end;

  -- 14. Trabalhador le os arquivos do servico (esperado: 3 = testes 01, 02 e 06)
  select count(*) into v_n from public.service_files where service_id = v_svc1;
  v_out := v_out || case when v_n = 3 then 'OK     ' else 'FALHOU ' end
        || '14. Trabalhador le os arquivos do servico (' || v_n || ' de 3)' || E'\n';

  -- 15. Cliente A le os arquivos do servico
  reset role; perform set_config('request.jwt.claims', v_claim_a, true); set local role authenticated;
  select count(*) into v_n from public.service_files where service_id = v_svc1;
  v_out := v_out || case when v_n = 3 then 'OK     ' else 'FALHOU ' end
        || '15. Cliente le os arquivos do servico (' || v_n || ' de 3)' || E'\n';

  -- 16. Cliente B nao enxerga nenhum arquivo do servico 1
  reset role; perform set_config('request.jwt.claims', v_claim_b, true); set local role authenticated;
  select count(*) into v_n from public.service_files where service_id = v_svc1;
  v_out := v_out || case when v_n = 0 then 'OK     ' else 'FALHOU ' end
        || '16. Quem nao participa nao enxerga arquivos (' || v_n || ')' || E'\n';

  -- 17. Ninguem altera registro de foto
  reset role; perform set_config('request.jwt.claims', v_claim_worker, true); set local role authenticated;
  begin
    update public.service_files set original_name = 'adulterado.jpg' where service_id = v_svc1;
    v_out := v_out || 'FALHOU 17. Foto alterada' || E'\n';
  exception when others then
    v_out := v_out || case when sqlerrm like '%permission denied%' then 'OK     ' else 'FALHOU ' end
          || '17. Registro de foto nao pode ser alterado (' || sqlerrm || ')' || E'\n';
  end;

  -- 18. Ninguem apaga registro de foto
  begin
    delete from public.service_files where service_id = v_svc1;
    v_out := v_out || 'FALHOU 18. Foto apagada' || E'\n';
  exception when others then
    v_out := v_out || case when sqlerrm like '%permission denied%' then 'OK     ' else 'FALHOU ' end
          || '18. Registro de foto nao pode ser apagado (' || sqlerrm || ')' || E'\n';
  end;

  -- ==========================================================
  -- PARTE B: servico concluido nao recebe mais fotos
  -- ==========================================================
  perform public.change_service_status(v_svc2, 'completed');

  begin
    insert into public.service_files
      (service_id, uploaded_by, file_type, storage_path, original_name, mime_type, file_size)
    values
      (v_svc2, v_worker, 'photo', v_svc2::text || '/tarde.jpg', 'tarde.jpg', 'image/jpeg', 1000);
    v_out := v_out || 'FALHOU 19a. Trabalhador registrou foto em servico concluido' || E'\n';
  exception when others then
    v_out := v_out || case when sqlerrm like '%row-level security%' then 'OK     ' else 'FALHOU ' end
          || '19a. Servico concluido nao recebe foto do trabalhador (' || sqlerrm || ')' || E'\n';
  end;

  reset role; perform set_config('request.jwt.claims', v_claim_b, true); set local role authenticated;
  begin
    insert into public.service_files
      (service_id, uploaded_by, file_type, storage_path, original_name, mime_type, file_size)
    values
      (v_svc2, v_client_b, 'photo', v_svc2::text || '/tarde2.jpg', 'tarde2.jpg', 'image/jpeg', 1000);
    v_out := v_out || 'FALHOU 19b. Cliente registrou foto em servico concluido' || E'\n';
  exception when others then
    v_out := v_out || case when sqlerrm like '%row-level security%' then 'OK     ' else 'FALHOU ' end
          || '19b. Servico concluido nao recebe foto do cliente (' || sqlerrm || ')' || E'\n';
  end;

  -- ==========================================================
  -- PARTE C: Storage (tabela storage.objects, onde ficam os arquivos)
  -- ==========================================================

  -- 20. Trabalhador envia arquivo para a pasta do servico 1
  reset role; perform set_config('request.jwt.claims', v_claim_worker, true); set local role authenticated;
  begin
    insert into storage.objects (bucket_id, name)
    values ('service-files', v_svc1::text || '/w.jpg');
    v_out := v_out || 'OK     20. Trabalhador envia arquivo para a pasta do servico' || E'\n';
  exception when others then
    v_out := v_out || 'FALHOU 20. Envio do trabalhador ao Storage (' || sqlerrm || ')' || E'\n';
  end;

  -- 21. Cliente A envia arquivo para a pasta do servico 1
  reset role; perform set_config('request.jwt.claims', v_claim_a, true); set local role authenticated;
  begin
    insert into storage.objects (bucket_id, name)
    values ('service-files', v_svc1::text || '/c.jpg');
    v_out := v_out || 'OK     21. Cliente envia arquivo para a pasta do servico' || E'\n';
  exception when others then
    v_out := v_out || 'FALHOU 21. Envio do cliente ao Storage (' || sqlerrm || ')' || E'\n';
  end;

  -- 22. Cliente B nao envia arquivo para a pasta do servico 1
  reset role; perform set_config('request.jwt.claims', v_claim_b, true); set local role authenticated;
  begin
    insert into storage.objects (bucket_id, name)
    values ('service-files', v_svc1::text || '/invasor.jpg');
    v_out := v_out || 'FALHOU 22. Quem nao participa enviou ao Storage' || E'\n';
  exception when others then
    v_out := v_out || case when sqlerrm like '%row-level security%' then 'OK     ' else 'FALHOU ' end
          || '22. Quem nao participa nao envia ao Storage (' || sqlerrm || ')' || E'\n';
  end;

  -- 23. Servico concluido nao recebe arquivos no Storage
  reset role; perform set_config('request.jwt.claims', v_claim_worker, true); set local role authenticated;
  begin
    insert into storage.objects (bucket_id, name)
    values ('service-files', v_svc2::text || '/tarde.jpg');
    v_out := v_out || 'FALHOU 23. Servico concluido recebeu arquivo no Storage' || E'\n';
  exception when others then
    v_out := v_out || case when sqlerrm like '%row-level security%' then 'OK     ' else 'FALHOU ' end
          || '23. Servico concluido nao recebe arquivo no Storage (' || sqlerrm || ')' || E'\n';
  end;

  -- 24. Pasta que nao e ID de servico e recusada
  begin
    insert into storage.objects (bucket_id, name)
    values ('service-files', 'pasta-qualquer/x.jpg');
    v_out := v_out || 'FALHOU 24. Pasta qualquer aceita' || E'\n';
  exception when others then
    v_out := v_out || case when sqlerrm like '%row-level security%' then 'OK     ' else 'FALHOU ' end
          || '24. Pasta que nao e de um servico e recusada (' || sqlerrm || ')' || E'\n';
  end;

  -- 25. Arquivo solto, sem pasta, e recusado
  begin
    insert into storage.objects (bucket_id, name)
    values ('service-files', 'solto.jpg');
    v_out := v_out || 'FALHOU 25. Arquivo sem pasta aceito' || E'\n';
  exception when others then
    v_out := v_out || case when sqlerrm like '%row-level security%' then 'OK     ' else 'FALHOU ' end
          || '25. Arquivo sem pasta e recusado (' || sqlerrm || ')' || E'\n';
  end;

  -- 26. Trabalhador enxerga os 2 arquivos do servico 1 no Storage
  select count(*) into v_n from storage.objects
  where bucket_id = 'service-files' and name like v_svc1::text || '/%';
  v_out := v_out || case when v_n = 2 then 'OK     ' else 'FALHOU ' end
        || '26. Trabalhador enxerga os arquivos do servico no Storage (' || v_n || ' de 2)' || E'\n';

  -- 27. Cliente A enxerga os 2 arquivos
  reset role; perform set_config('request.jwt.claims', v_claim_a, true); set local role authenticated;
  select count(*) into v_n from storage.objects
  where bucket_id = 'service-files' and name like v_svc1::text || '/%';
  v_out := v_out || case when v_n = 2 then 'OK     ' else 'FALHOU ' end
        || '27. Cliente enxerga os arquivos do servico no Storage (' || v_n || ' de 2)' || E'\n';

  -- 28. Cliente B nao enxerga nenhum
  reset role; perform set_config('request.jwt.claims', v_claim_b, true); set local role authenticated;
  select count(*) into v_n from storage.objects
  where bucket_id = 'service-files' and name like v_svc1::text || '/%';
  v_out := v_out || case when v_n = 0 then 'OK     ' else 'FALHOU ' end
        || '28. Quem nao participa nao enxerga arquivos no Storage (' || v_n || ')' || E'\n';

  -- 29. Visitante sem login nao enxerga nada
  reset role; perform set_config('request.jwt.claims', '', true); set local role anon;
  begin
    select count(*) into v_n from storage.objects where bucket_id = 'service-files';
    v_out := v_out || case when v_n = 0 then 'OK     ' else 'FALHOU ' end
          || '29. Visitante sem login nao enxerga arquivos (' || v_n || ')' || E'\n';
  exception when others then
    v_out := v_out || 'OK     29. Visitante sem login nao acessa o Storage (' || sqlerrm || ')' || E'\n';
  end;

  -- 30. Ninguem altera arquivo no Storage (esperado: 0 linhas alteradas, ou erro)
  reset role; perform set_config('request.jwt.claims', v_claim_worker, true); set local role authenticated;
  begin
    update storage.objects set name = name
    where bucket_id = 'service-files' and name like v_svc1::text || '/%';
    get diagnostics v_n = row_count;
    v_out := v_out || case when v_n = 0 then 'OK     ' else 'FALHOU ' end
          || '30. Arquivo no Storage nao pode ser alterado (' || v_n || ' linhas)' || E'\n';
  exception when others then
    v_out := v_out || 'OK     30. Alterar arquivo no Storage e bloqueado (' || sqlerrm || ')' || E'\n';
  end;

  -- 31. Ninguem apaga arquivo no Storage (esperado: 0 linhas apagadas, ou erro)
  begin
    delete from storage.objects
    where bucket_id = 'service-files' and name like v_svc1::text || '/%';
    get diagnostics v_n = row_count;
    v_out := v_out || case when v_n = 0 then 'OK     ' else 'FALHOU ' end
          || '31. Arquivo no Storage nao pode ser apagado (' || v_n || ' linhas)' || E'\n';
  exception when others then
    v_out := v_out || 'OK     31. Apagar arquivo no Storage e bloqueado (' || sqlerrm || ')' || E'\n';
  end;

  reset role;
  raise exception E'RESULTADO DOS TESTES (nada foi gravado; tudo e desfeito no final)\n\n%', v_out;
end;
$$;