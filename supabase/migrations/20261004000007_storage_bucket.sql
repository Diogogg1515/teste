-- ============================================================
-- souza.l - Migration 07: bucket privado para arquivos de serviço
-- ============================================================
-- RODAR UMA VEZ, no SQL Editor do Supabase (cole tudo e clique em Run).

-- 1) Cria o bucket privado 'service-files'
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'service-files',
  'service-files',
  false,  -- privado (não público)
  10485760,  -- limite de 10 MB em bytes
  ARRAY['image/jpeg', 'image/png', 'image/webp']::text[]
)
on conflict (id) do nothing;  -- Não falha se o bucket já existir

-- 2) Consulta de conferência:
-- select id, name, public, file_size_limit, allowed_mime_types
-- from storage.buckets
-- where name = 'service-files';
-- Esperado: public=false, file_size_limit=10485760, allowed_mime_types={image/jpeg,image/png,image/webp}