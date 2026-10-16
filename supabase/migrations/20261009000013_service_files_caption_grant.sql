-- ============================================================
-- souza.l - Migration 13: atualiza grant INSERT para incluir caption
-- ============================================================
-- Migration 11 (20261005000011) adicionou coluna caption à tabela
-- service_files, mas o GRANT INSERT da migration 09 não foi atualizado.
-- Esta migration corrige isso.
-- ============================================================

-- Remove grant antigo e adiciona novo com caption
revoke insert on public.service_files from authenticated;

grant insert (service_id, record_id, uploaded_by, file_type, storage_path, original_name, mime_type, file_size, caption)
  on public.service_files to authenticated;

-- Consulta de conferência:
-- select privilege_type, column_name
-- from information_schema.column_privileges
-- where table_name = 'service_files' and grantee = 'authenticated'
-- order by column_name;
-- Verifique se 'caption' aparece na lista de colunas com INSERT
