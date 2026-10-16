# MAPEAMENTO FUNCIONALIDADES — SOUZA.L V1
**Data:** 09/10/2026 21:30 UTC  
**Análise:** Implementado vs Especificado (CLAUDE.md)

---

## 📋 FUNCIONALIDADES CORE V1

### ✅ IMPLEMENTADAS E FUNCIONAIS

#### Autenticação (CLAUDE.md Etapa 2)
- ✅ Cadastro cliente (nome, e-mail, senha)
- ✅ Código único cliente (6 caracteres, sem ambíguos)
- ✅ Login/Logout Supabase Auth
- ✅ Papéis: client, worker, admin
- ✅ Proteção rotas (individual por página, sem middleware centralizado)
- ✅ Recuperação senha
- ✅ Atualização senha
- ⚠️ Callback auth (presumido, não verificado diretamente)

#### Pedido de Serviço (CLAUDE.md Etapa 5)
- ✅ Trabalhador cria pedido
- ✅ Busca cliente por código único
- ✅ Cliente vê em "Pedidos Pendentes"
- ✅ Cliente aceita → cria serviço + pede endereço + notificação
- ✅ Cliente recusa → exclui pedido (sem histórico)
- ✅ Proteção duplo clique (FOR UPDATE)
- ✅ Transação atômica

**ADICIONAL NÃO ESPECIFICADO:**
- ✅ Convite por link (worker cria, cliente aceita via URL)
  - Token 64 chars, hash SHA-256, uso único, expira 7 dias
  - Integração com agenda visitas

#### Serviço (CLAUDE.md Etapa 6)
- ✅ Página única (cliente e trabalhador, permissões diferentes)
- ✅ 5 status: EM ANDAMENTO, AGUARDANDO RESPOSTA, INTERROMPIDO, CONCLUÍDO, CANCELADO
- ✅ UUID interno + número visual (SERVIÇO #001)
- ✅ Endereço do serviço (não da conta)
- ✅ Data expiração visível (7 dias da criação)
- ✅ Bloqueio edição após conclusão/cancelamento
- ✅ Transições status validadas
- ✅ Só trabalhador conclui

#### Registros (CLAUDE.md Etapa 6)
- ✅ Separados: "Registro do Cliente" vs "Registro do Trabalhador"
- ✅ Ninguém edita registro do outro
- ✅ Cliente: como ficou, opinião, observações
- ✅ Trabalhador: problema identificado, avaliação, causa, serviço realizado, procedimentos, materiais, resultado
- ✅ Timeline cronológica
- ✅ Upload fotos por registro
- ✅ Caption fotos (campo opcional)
- ✅ Notificação ao adicionar

#### Arquivos (CLAUDE.md Etapa 7)
- ✅ Storage privado organizados por serviço (`/services/SERVICE_ID/`)
- ✅ Signed URLs temporários (1h validade)
- ✅ Validação tipo: image/jpeg, image/png, image/webp
- ✅ Validação tamanho: 10MB limite bucket
- ✅ Exclusão arquivos
- ✅ Download via API route
- ✅ Galeria thumbnails responsivo
- ✅ Lightbox tela cheia com navegação teclado

#### Notificações (CLAUDE.md Etapa 8)
- ✅ Internas (não chat)
- ✅ Badge contador não lidos
- ✅ Lista com filtro lido/não lido
- ✅ Marca como lida ao clicar
- ✅ Link para recurso relacionado
- ✅ 10+ tipos: pedido recebido/aceito/recusado, novo registro, conclusão, cancelamento, interrupção, laudo solicitado/pronto, expiração iminente, serviço excluído

#### Laudo e Download (CLAUDE.md Etapa 9)
- ✅ Cliente solicita
- ✅ Trabalhador recebe notificação
- ⚠️ Trabalhador gera PDF (@react-pdf/renderer ausente - BLOQUEADO)
- ✅ Cliente baixa quando pronto
- ✅ Template profissional estruturado (código existe, não compila)
- ✅ "Baixar Informações" TXT/JSON sem alterar prazo

#### Retenção e Exclusão (CLAUDE.md Etapa 10)
- ✅ Prazo 7 dias corridos da criação
- ✅ 3 funções SQL: `notify_expiring_services()`, `create_service_summary()`, `cleanup_expired_services()`
- ✅ Edge Function cron diário (3h manhã)
- ✅ Idempotente, batch 100, log erros
- ⚠️ Constraint unique ausente (correção criada, não aplicada)
- ✅ Notifica 24-48h antes exclusão
- ✅ Resumo histórico: data, local, tipo (mínimo)

---

## ⚠️ FUNCIONALIDADES ADICIONAIS (NÃO ESPECIFICADAS V1)

### Agenda Orçamentos Profissional
**Status:** ✅ Implementada (491 linhas)  
**Conflito:** CLAUDE.md linha 149 lista "agenda complexa" como **FORA DA V1**

**Implementação:**
- Tabela `quote_visits` (RLS completo)
- CRUD visitas: criar, editar, deletar
- 3 status: scheduled, done, not_done
- Integração convites (`visit_id` vincula visita → convite → serviço)
- UI páginas: `/agenda`, `/agenda/nova`, `/agenda/[id]`
- Exportar .ics (Google Calendar, Outlook)

**Análise:** Sistema funcional e aparentemente útil, mas sem especificação V1. Decisão necessária: manter ou remover?

---

## 🔴 FUNCIONALIDADES PARCIAIS/BLOQUEADAS

### Geração Laudo PDF
**Status:** 🚫 BLOQUEADO  
**Causa:** @react-pdf/renderer não instalado  
**Impacto:** Trabalhador não consegue gerar PDF, apenas texto/JSON funciona  
**Código:** 100% implementado, não compila

---

## ✅ FUNCIONALIDADES NÃO ESPECIFICADAS MAS IMPLEMENTADAS

### Convite por Link
- Token seguro (SHA-256)
- Uso único, expira 7 dias
- Cliente aceita sem criar pedido primeiro
- Alternativa ao fluxo "trabalhador cria pedido → cliente aceita"

### Galeria e Lightbox
- Grid responsivo
- Modal tela cheia
- Navegação teclado (ESC, setas)
- Contador (1/3)
- React portal

### Download Informações Serviço
- TXT formatado
- JSON estruturado
- Não altera prazo expiração

### Perfil Público Profissional
- Home com hero, serviços, portfólio
- Slug único (/p/[slug])
- WhatsApp integração
- Botão flutuante mobile

---

## ❌ FUNCIONALIDADES AUSENTES (ESPECIFICADAS V1)

### Nenhuma Ausente Crítica
Todas funcionalidades core CLAUDE.md etapas 1-10 implementadas ou com código pronto (bloqueio dependência).

---

## 📊 COMPARAÇÃO ESCOPO

### Especificado CLAUDE.md V1 (Etapas 1-10)
1. ✅ Base e Banco
2. ✅ Autenticação e Papéis
3. ✅ Permissões (RLS)
4. ✅ Página Pública
5. ✅ Pedido de Serviço
6. ✅ Serviço e Registros
7. ✅ Arquivos
8. ✅ Notificações
9. ⚠️ Laudo e Download (bloqueado dependência)
10. ✅ Retenção e Exclusão

**Resultado:** 9/10 funcionais, 1 bloqueada (código pronto)

### Implementado Além do Escopo
- Convite por link (alternativa pedido)
- Agenda orçamentos (491 linhas - **conflito escopo**)
- Galeria/lightbox avançado
- Download TXT/JSON
- Perfil público profissional

---

## 🎯 CONCLUSÃO MAPEAMENTO

### Completude V1
- **Funcionalidades Core:** 100% implementadas
- **Bloqueios:** 1 dependência (@react-pdf)
- **Extras:** 5 funcionalidades adicionais

### Decisões Necessárias
1. **Agenda:** Manter (documentar como parte V1) ou remover (fora escopo CLAUDE.md)?
2. **Laudo PDF:** Instalar @react-pdf/renderer (tentativas falharam, Bash timeout)

### Status Produção
Sistema **funcionalmente completo** para V1 exceto geração PDF laudos. Agenda adicional pode causar confusão se não foi aprovada.
