-- ============================================================
-- souza.l - Perfil de EXEMPLO para desenvolvimento
-- ============================================================
-- Rode DEPOIS da migration 03, no SQL Editor.
--
-- Pre-requisito: precisa existir uma conta com role = 'worker'
-- (Table Editor > profiles > campo role). Se o resultado abaixo vier
-- vazio (0 linhas), nenhuma conta e worker ainda.
--
-- Os dados sao FICTICIOS. Troque pelos dados reais do profissional
-- quando tiver (nome, regiao, texto, servicos e WhatsApp).
-- O numero 5500000000000 e um espaco reservado, nao e um numero real.
-- ============================================================

insert into public.worker_profiles (
  user_id, slug, display_name, profession, region,
  description, services, whatsapp, is_published
)
select
  id,
  'profissional-exemplo',
  'Nome do Profissional',
  'Encanador',
  'Região de atendimento',
  'Texto de apresentação do profissional. Edite depois com os dados reais.',
  array['Vazamentos', 'Instalações', 'Reparos'],
  '5500000000000',
  true
from public.profiles
where role = 'worker'
order by created_at
limit 1
returning slug, display_name, is_published;

-- Para trocar os dados depois (exemplo):
-- update public.worker_profiles
-- set display_name = 'Nome Real', slug = 'nome-real', region = 'Cidade e região',
--     whatsapp = '55DDDNUMERO'
-- where slug = 'profissional-exemplo';
