-- ============================================================
-- souza.l - Migration 08: políticas de acesso ao Storage para arquivos de serviço
-- ============================================================
-- RODAR UMA VEZ, no SQL Editor do Supabase (cole tudo e clique em Run).

-- 1) Policy: UPLOAD - Só participantes do serviço podem enviar arquivos
create policy "Participante pode enviar arquivos para o serviço"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'service-files'
  and exists (
    select 1 from public.services s
    where s.id::text = (storage.foldername(storage.objects.name))[1]
      and (select auth.uid()) in (s.client_id, s.worker_id)
      and s.status in ('in_progress', 'waiting_response')
  )
);

-- 2) Policy: DOWNLOAD - Só participantes do serviço podem baixar arquivos
create policy "Participante pode baixar arquivos do serviço"
on storage.objects for select
to authenticated
using (
  bucket_id = 'service-files'
  and exists (
    select 1 from public.services s
    where s.id::text = (storage.foldername(storage.objects.name))[1]
      and (select auth.uid()) in (s.client_id, s.worker_id)
  )
);

-- 3) Consulta de conferência:
-- select policyname, permissive, roles, cmd, qual, with_check
-- from pg_policies
-- where tablename = 'objects' and schemaname = 'storage';
-- Verifique se as duas políticas acima estão presentes

-- 4) Nenhuma policy de UPDATE ou DELETE (mantém arquivos imutáveis como os registros)