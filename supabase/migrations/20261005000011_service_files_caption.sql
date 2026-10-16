-- ============================================================
-- souza.l - Migration 11: adicionar campo de legenda em service_files
-- ============================================================
-- RODAR UMA VEZ, no SQL Editor do Supabase (cole tudo e clique em Run).

-- 1) Adiciona COLUMN para legenda/descrição da foto
alter table public.service_files
add column caption text;

-- 2) Consulta de conferência:
-- select column_name, data_type, is_nullable, column_default
-- from information_schema.columns
-- where table_name = 'service_files' and table_schema = 'public'
-- and column_name = 'caption';
- Esperado: caption, text, YES, NULL

-- 3) Opcional: atualizar comentário da coluna para documentar o propósito
comment on column public.service_files.caption is 'Legenda ou descrição fornecida pelo usuário para a foto (ex: " Vista frontal do prédio após o serviço ")';