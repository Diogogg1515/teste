-- ============================================================
-- souza.l - Migration 10: adicionar restricões de tamanho e tipo em service_files
-- ============================================================
-- RODAR UMA VEZ, no SQL Editor do Supabase (cole tudo e clique em Run).

-- 1) Adiciona CHECK constraint para tamanho máximo de arquivo (10 MB)
alter table public.service_files
add constraint service_files_file_size_check
check (file_size > 0 and file_size <= 10485760);  -- 10 MB = 10 * 1024 * 1024 bytes

-- 2) Adiciona CHECK constraint para tipo de arquivo e MIME type permitido para fotos
alter table public.service_files
add constraint service_files_file_type_mime_check
check (
  file_type != 'photo'
  or (
    file_type = 'photo'
    and mime_type in ('image/jpeg', 'image/png', 'image/webp')
    and file_size is not null
    and mime_type is not null
  )
);

-- 3) Consulta de conferência:
-- select conname, contype, consrc
-- from pg_constraint
-- where conrelid = 'public.service_files'::regclass
--   and conname in ('service_files_file_size_check', 'service_files_file_type_mime_check');
-- Verifique se as duas constraints estão presentes