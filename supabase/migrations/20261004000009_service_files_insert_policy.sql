-- ============================================================
-- souza.l - Migration 09: atualizar política de INSERT para service_files
-- ============================================================
-- RODAR UMA VEZ, no SQL Editor do Supabase (cole tudo e clique em Run).

-- 1) Revoga a política de INSERT existente (se houver) para evitar conflitos
do $$
begin
  if exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'service_files'
      and policyname = 'Participante pode enviar arquivo'
  ) then
    drop policy "Participante pode enviar arquivo" on public.service_files;
  end if;
end $$;

-- 2) Cria nova política de INSERT com todas as restrições de segurança
create policy "Participante pode enviar arquivo"
on public.service_files for insert
to authenticated
with check (
  -- 1) O usuário que está fazendo o upload deve ser o mesmo do token de autenticação
  uploaded_by = (select auth.uid())

  -- 2) O usuário deve participar do serviço (client_id ou worker_id)
  and exists (
    select 1 from public.services s
    where s.id = service_id
      and (select auth.uid()) in (s.client_id, s.worker_id)
  )

  -- 3) O serviço deve estar em status permitido para novos registros
  and exists (
    select 1 from public.services s
    where s.id = service_id
      and s.status in ('in_progress', 'waiting_response')
  )

  -- 4) Se houver record_id, ele deve ser válido e pertencer ao mesmo usuário e serviço
  and (
    record_id is null
    or (
      exists (
        select 1 from public.service_records r
        where r.id = record_id
          and r.service_id = service_files.service_id  -- Qualificado para evitar ambiguidade
          and r.author_id = (select auth.uid())
      )
    )
  )

  -- 5) O storage_path deve começar com o ID do serviço seguido de barra
  and storage_path like service_files.service_id::text || '/%'

  -- 6) O tipo de arquivo deve ser permitido (inicialmente só foto)
  and file_type = 'photo'
);

-- 3) Consulta de conferência:
-- select policyname, permissive, roles, cmd, qual, with_check
-- from pg_policies
-- where tablename = 'service_files' and schemaname = 'public'
--   and policyname = 'Participante pode enviar arquivo';
-- Verifique se a política está presente com as condições corretas

-- 4) Concede privilégio de INSERT apenas nas colunas que o usuário pode preencher
grant insert (service_id, record_id, uploaded_by, file_type, storage_path, original_name, mime_type, file_size)
  on public.service_files to authenticated;