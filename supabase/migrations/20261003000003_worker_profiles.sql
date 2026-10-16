-- ============================================================
-- souza.l - Migration 03: perfis profissionais (vitrine publica)
-- ============================================================
-- RODAR UMA VEZ, no SQL Editor do Supabase (cole tudo e clique em Run).
--
-- O que e: o cartao publico do profissional (home e /p/[slug]).
-- Regras:
--  * So perfis com is_published = true aparecem para visitantes.
--  * Visitantes leem APENAS as colunas publicas (nunca user_id).
--  * Ninguem escreve pelo site nesta etapa. O perfil e criado/editado
--    pelo SQL Editor. A tela de edicao (/perfil) vem depois, com
--    politica propria e testes.
-- ============================================================

create table public.worker_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references public.profiles (id) on delete cascade,
  slug text not null unique,
  display_name text not null,
  profession text not null,
  region text,
  description text,
  services text[] not null default '{}',
  whatsapp text not null,
  is_published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint worker_profiles_slug_format
    check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and char_length(slug) between 3 and 40),
  constraint worker_profiles_name_length
    check (char_length(btrim(display_name)) between 2 and 100),
  constraint worker_profiles_profession_length
    check (char_length(btrim(profession)) between 2 and 60),
  constraint worker_profiles_region_length
    check (region is null or char_length(region) <= 100),
  constraint worker_profiles_description_length
    check (description is null or char_length(description) <= 600),
  constraint worker_profiles_services_count
    check (cardinality(services) <= 20),
  -- WhatsApp: so numeros, com codigo do pais e DDD (ex.: 5511999999999)
  constraint worker_profiles_whatsapp_format
    check (whatsapp ~ '^[0-9]{10,15}$')
);

create trigger set_updated_at before update on public.worker_profiles
  for each row execute function public.set_updated_at();

alter table public.worker_profiles enable row level security;

-- Visitantes e usuarios logados leem perfis PUBLICADOS
create policy "Qualquer pessoa le perfis publicados"
on public.worker_profiles for select
to anon, authenticated
using (is_published);

-- O proprio profissional le o seu perfil, mesmo nao publicado
create policy "Profissional le o proprio perfil"
on public.worker_profiles for select
to authenticated
using (user_id = (select auth.uid()));

-- Privilegios (segunda camada de protecao)
revoke all on public.worker_profiles from anon, authenticated;

-- Visitante: so as colunas publicas (is_published entra porque a politica a usa)
grant select (
  slug, display_name, profession, region, description,
  services, whatsapp, is_published
) on public.worker_profiles to anon;

-- Usuario logado: leitura (as politicas acima decidem quais linhas)
grant select on public.worker_profiles to authenticated;

-- Sem insert/update/delete para ninguem pelo site nesta etapa.
