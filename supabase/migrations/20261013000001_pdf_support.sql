-- ============================================================
-- souza.l - Migration: Suporte a PDF para laudos e documentos
-- ============================================================
-- Permite upload de PDF no bucket service-files para laudos.
-- Ajusta policy de Storage para permitir upload em serviços concluídos.
-- Adiciona valores 'laudo' e 'laudo_requested' ao enum document_kind.
-- ============================================================

-- 1. Atualiza bucket para aceitar PDF
-- O bucket já existe (migração 07), fazemos UPDATE no storage.buckets
update storage.buckets
set allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp', 'application/pdf']::text[]
where id = 'service-files';

-- Consulta de conferência:
-- select id, name, public, file_size_limit, allowed_mime_types
-- from storage.buckets
-- where name = 'service-files';
-- Esperado: allowed_mime_types inclui application/pdf


-- 2. Atualiza policy de INSERT no Storage para permitir upload em serviços concluídos
-- (necessário para geração de laudo, que ocorre após conclusão)
do $$
begin
  -- Remove policy antiga se existir
  if exists (
    select 1 from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'Participante pode enviar arquivos para o serviço'
  ) then
    drop policy "Participante pode enviar arquivos para o serviço" on storage.objects;
  end if;
end $$;

-- Nova policy: permite upload para participantes em serviços ativos OU concluídos/cancelados
-- (laudos são gerados para serviços completed/cancelled)
create policy "Participante pode enviar arquivos para o serviço"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'service-files'
  and exists (
    select 1 from public.services s
    where s.id::text = (storage.foldername(storage.objects.name))[1]
      and (select auth.uid()) in (s.client_id, s.worker_id)
      and s.status in ('in_progress', 'waiting_response', 'completed', 'cancelled')
  )
);

-- Consulta de conferência:
-- select policyname, cmd, with_check
-- from pg_policies
-- where schemaname = 'storage' and tablename = 'objects'
--   and policyname = 'Participante pode enviar arquivos para o serviço';


-- 3. Adiciona valores ao enum document_kind para suportar laudos
-- Postgres não permite ALTER TYPE ... ADD VALUE em transação, usamos blocos separados
-- (cada ALTER TYPE ADD VALUE commitado automaticamente)
alter type public.document_kind add value if not exists 'laudo';
alter type public.document_kind add value if not exists 'laudo_requested';

-- Consulta de conferência:
-- select enumlabel from pg_enum
-- where enumtypid = 'public.document_kind'::regtype
-- order by enumsortorder;
-- Esperado: report, service_export, laudo, laudo_requested


-- 4. Atualiza CHECK constraint de service_files para também permitir 'document' com PDF
-- (opcional: permite anexar PDFs como documentos em registros, não só laudos)
do $$
begin
  -- Remove constraint antiga se existir
  if exists (
    select 1 from pg_constraint
    where conrelid = 'public.service_files'::regclass
      and conname = 'service_files_file_type_mime_check'
  ) then
    alter table public.service_files
    drop constraint service_files_file_type_mime_check;
  end if;
end $$;

-- Nova constraint: permite 'photo' (imagens) OU 'document' (PDF)
alter table public.service_files
add constraint service_files_file_type_mime_check
check (
  (file_type = 'photo'
   and mime_type in ('image/jpeg', 'image/png', 'image/webp')
   and file_size is not null
   and mime_type is not null)
  or
  (file_type = 'document'
   and mime_type = 'application/pdf'
   and file_size is not null
   and mime_type is not null)
);

-- Consulta de conferência:
-- select conname, pg_get_constraintdef(oid)
-- from pg_constraint
-- where conrelid = 'public.service_files'::regclass
--   and conname = 'service_files_file_type_mime_check';


-- 5. Atualiza policy de INSERT em service_files para permitir file_type = 'document' (PDF)
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

create policy "Participante pode enviar arquivo"
on public.service_files for insert
to authenticated
with check (
  uploaded_by = (select auth.uid())
  and exists (
    select 1 from public.services s
    where s.id = service_id
      and (select auth.uid()) in (s.client_id, s.worker_id)
      and s.status in ('in_progress', 'waiting_response', 'completed', 'cancelled')
  )
  and (
    record_id is null
    or (
      exists (
        select 1 from public.service_records r
        where r.id = record_id
          and r.service_id = service_files.service_id
          and r.author_id = (select auth.uid())
      )
    )
  )
  and storage_path like service_files.service_id::text || '/%'
  and (
    (file_type = 'photo' and mime_type in ('image/jpeg', 'image/png', 'image/webp'))
    or
    (file_type = 'document' and mime_type = 'application/pdf')
  )
  and file_size > 0 and file_size <= 10485760
);

-- Grant INSERT nas colunas permitidas (inclui file_type/document)
revoke insert on public.service_files from authenticated;
grant insert (
  service_id, record_id, uploaded_by, file_type, storage_path,
  original_name, mime_type, file_size, caption
) on public.service_files to authenticated;

-- Consulta de conferência:
-- select policyname, cmd, with_check
-- from pg_policies
-- where schemaname = 'public' and tablename = 'service_files'
--   and policyname = 'Participante pode enviar arquivo';