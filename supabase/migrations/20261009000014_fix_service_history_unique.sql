-- ============================================================
-- souza.l - Migration 14: corrige constraint ausente em service_history_summary
-- ============================================================
-- PROBLEMA: Migration 20261009000001_retention_cleanup.sql linha 84 usa
-- "on conflict (service_number) do nothing" mas a tabela não possui
-- unique constraint em service_number, causando erro em runtime.
--
-- CORREÇÃO: Adiciona unique constraint necessário.
-- ============================================================

-- Adiciona unique constraint em service_number
alter table public.service_history_summary
add constraint service_history_summary_service_number_key
unique (service_number);

-- Consulta de conferência:
-- select constraint_name, constraint_type
-- from information_schema.table_constraints
-- where table_name = 'service_history_summary'
--   and constraint_type = 'UNIQUE';
-- Esperado: service_history_summary_service_number_key | UNIQUE
