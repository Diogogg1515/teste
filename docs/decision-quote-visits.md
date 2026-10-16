# DECISÃO: quote_visits (Agenda) — FORA DA V1?

## Contexto
- CLAUDE.md linha 149: "agenda complexa" listada como **FORA DA V1**
- Implementação atual: `app/agenda/` (491 linhas), `lib/agenda/`, tabela `quote_visits`
- Funcionalidade: agendamento de visitas para orçamento

## Opção A: REMOVER (Alinhado com CLAUDE.md) ✅ RECOMENDADA
```bash
# Remover código
rm -rf app/agenda lib/agenda

# Dropar tabela (via migration)
# supabase/migrations/20261011000002_drop_quote_visits.sql
```
**Prós:** Escopo V1 puro, menos superfície de ataque, menos manutenção
**Contras:** Perde funcionalidade já construída

## Opção B: MANTER (Documentar como "Aceito Fora do Escopo")
- Manter código funcional
- Adicionar em CLAUDE.md: "quote_visits: mantido como funcionalidade extra aceita, não bloqueia V1"
- Não investir mais tempo nela

## Opção C: MANTER MÍNIMO (Apenas backend, sem UI)
- Manter RPCs/tabela para uso futuro
- Remover `app/agenda/` (UI)
- Reduz complexidade frontend

## Recomendação
**Opção A** — O CLAUDE.md é explícito. Se o dono quiser manter, deve ser decisão consciente documentada, não padrão.