# ⚠️ ALERTA DE SEGURANÇA CRÍTICO

**Data:** 09/10/2026 21:17 UTC  
**Severidade:** CRÍTICA  
**Status:** BLOQUEADOR PARA PRODUÇÃO

---

## VULNERABILITY: Escalação de Privilégios

### Arquivo Malicioso
```
supabase/migrations/20261009000013_test_set_role.sql
```

### Descrição
Migration de teste permite **qualquer usuário autenticado** alterar próprio papel para `admin` ou `worker`, bypassing completamente o sistema de permissões.

### Código Vulnerável
```sql
create or replace function public.set_test_role(
  p_user_id uuid,
  p_new_role public.user_role
)
returns void
language plpgsql
security definer  -- ← Executa com privilégios elevados
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  -- Apenas usuários autenticados podem chamar
  if v_uid is null then
    raise exception 'not_allowed';
  end if;

  -- Atualiza o papel SEM VALIDAR SE É ADMIN
  update public.profiles
  set role = p_new_role
  where id = p_user_id;
end;
$$;

-- VULNERABILIDADE: grant para TODOS autenticados
grant execute on function public.set_test_role(uuid, public.user_role) to authenticated;
```

### Exploit
1. Cliente se cadastra normalmente (papel `client`)
2. Cliente chama `select set_test_role(auth.uid(), 'admin')`
3. Cliente agora tem papel `admin`
4. Cliente acessa todas funções privilegiadas, bypassa RLS, vê todos serviços

### Impacto
- **Confidencialidade:** Total - acesso a todos dados de todos usuários
- **Integridade:** Total - pode alterar/deletar qualquer registro
- **Disponibilidade:** Total - pode cancelar todos serviços, apagar dados

### Vector de Ataque
```sql
-- Cliente malicioso executa:
select set_test_role(auth.uid(), 'admin');

-- Agora pode:
select * from services; -- Vê TODOS serviços (bypass RLS)
select * from profiles; -- Vê todos perfis
-- etc.
```

---

## AÇÕES OBRIGATÓRIAS ANTES DE PRODUÇÃO

### 1. REMOVER arquivo de teste
```bash
rm supabase/migrations/20261009000013_test_set_role.sql
```

### 2. REVOGAR função se já aplicada
```sql
-- Executar no banco:
revoke execute on function public.set_test_role(uuid, public.user_role) from authenticated;
drop function if exists public.set_test_role(uuid, public.user_role);
```

### 3. AUDITAR contas existentes
```sql
-- Verificar se alguém já escalou privilégios:
select id, name, role, created_at, updated_at
from public.profiles
where role in ('worker', 'admin')
  and updated_at > created_at + interval '5 minutes';
-- Investigar qualquer resultado suspeito
```

---

## PREVENÇÃO FUTURA

### Regra: Funções de Teste NUNCA em Migrations
- Criar pasta `supabase/migrations-dev/` para testes
- `.gitignore` deve bloquear `migrations-dev/`
- CI/CD deve falhar se encontrar comentário "TESTE" em migrations/

### Checklist Deploy
- [ ] Revisar TODAS migrations antes aplicar
- [ ] Buscar `security definer` + `grant execute ... to authenticated`
- [ ] Validar que funções privilegiadas checam papel do usuário
- [ ] Testar escalação de privilégios em staging

---

## EVIDÊNCIA

```bash
$ grep -r "set_test_role" supabase/
supabase/migrations/20261009000013_test_set_role.sql:create or replace function public.set_test_role(
supabase/migrations/20261009000013_test_set_role.sql:grant execute on function public.set_test_role(uuid, public.user_role) to authenticated;
```

Função existe, está acessível, e é executável por qualquer usuário logado.

---

**ESTE ARQUIVO DEVE SER MOSTRADO AO RESPONSÁVEL ANTES DE QUALQUER DEPLOY.**
