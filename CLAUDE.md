# souza.l — Guia do projeto (V1)

Este arquivo fica na raiz do projeto. Leia-o inteiro antes de qualquer tarefa.

> **Referência rápida:** Regras de atuação de agentes em `AGENTS.md`. Estrutura real do repositório em `STRUCTURE.md`.
> **Preservação obrigatória:** Nunca descarte alterações staged/unstaged do usuário (ver `git status` antes de editar).

## O que é o souza.l

Aplicação web responsiva (prioridade: celular) que **conecta** clientes e um prestador de serviços, **organiza** cada serviço, **registra** o que cada parte informa e **documenta** tudo (laudo em PDF).

- O souza.l **não executa** o serviço, **não negocia**, **não cobra**, **não medeia conflitos** e **não garante resultado**. Ele documenta.
- V1: um único trabalhador, mas a estrutura deve permitir vários no futuro.
- Interface 100% em português do Brasil.

## Regra de ouro do escopo

Antes de criar qualquer funcionalidade, pergunte: **"Isso é necessário para conectar, organizar, registrar ou documentar o serviço?"** Se não, está fora da V1. Não adicione nada "porque pode ser útil".

**Fora da V1:** marketplace, comissão, pagamentos, chat interno, garantia, mediação, avaliação por estrelas, rastreamento, app nativo, orçamento automático, IA, agenda complexa, perfil público do cliente, pós-venda.

## Stack (não trocar sem motivo técnico concreto)

Next.js (App Router) + React + TypeScript + Tailwind CSS · Supabase (Auth, PostgreSQL, Storage, RLS) · Vercel · Git + GitHub.

Não usar: microserviços, servidores próprios, Redis, filas, backend separado, autenticação própria, criptografia própria de campos.

## Como você (o assistente) deve trabalhar com o dono do projeto

O dono entende bem de estrutura de código, mas **não conhece React nem segurança**. Por isso:

1. **Explique antes de codar.** Comece cada tarefa com um plano curto em português simples: o que vai criar, em quais arquivos, e por quê.
2. **Uma etapa por vez.** Faça só o que foi pedido na etapa atual. Não adiante etapas futuras.
3. **Explique o código novo** em linguagem simples: o que cada arquivo faz e como ele se liga ao resto.
4. **Segurança: nunca mexa sem avisar.** Qualquer alteração em autenticação, permissões, políticas RLS, Storage ou chaves deve ser sinalizada de forma explícita, com explicação do que muda e do risco.
5. **Termine cada etapa com um checklist de teste manual** que o dono consiga executar sem ler código (ex.: "entre com a conta A e tente abrir o serviço da conta B; deve dar acesso negado").
6. **Se houver dúvida sobre uma regra do produto, pergunte.** Não invente regra.
7. **Aponte problemas que você notar**, mesmo fora da tarefa (erros, riscos, inconsistências), em vez de ficar em silêncio.
8. Sugira um commit com mensagem clara ao final de cada etapa (ex.: `feat: cria tabelas e RLS base`).

## Segurança (obrigatório)

- Autenticação **somente** pelo Supabase Auth. Nunca armazenar senha.
- **RLS ativo em todas as tabelas.** Sem política = sem acesso. Permissões nunca dependem só da interface: esconder botão não é segurança.
- Toda ação protegida é validada **no servidor e/ou no banco**: quem é o usuário, qual o papel, se pertence àquele serviço, se a ação é permitida.
- Papéis (`client`, `worker`, `admin`) ficam guardados no banco. Permissão **nunca** é decidida pelo e-mail.
- `SUPABASE_SERVICE_ROLE_KEY` é secreta: só no servidor, nunca no navegador, nunca no código. Usar variáveis de ambiente e manter `.env*` fora do Git.
- Arquivos (fotos, laudos) em Storage **privado**, organizados por serviço, acessados por link assinado/temporário. Nunca URL pública permanente.
- Validar todos os dados no servidor (campos, tamanhos, tipo e tamanho de arquivo, estado do serviço).
- Logs e auditoria **sem** senhas, tokens ou dados desnecessários.
- Acessar diretamente `/servicos/<id-de-outro-cliente>` deve resultar em acesso negado.

## Regras do produto

**Contas**
- Cliente: cadastro só com nome, e-mail, senha. O sistema gera um **código exclusivo do cliente**. Endereço **não** é pedido no cadastro.
- Trabalhador e Administrador: contas separadas, com permissões próprias.

**Pedido de serviço → Serviço**
- Só o **trabalhador** cria o Pedido de Serviço (procurando o cliente pelo código ou pela lista de Clientes).
- O cliente vê em *Meus Serviços → Pedidos de Serviço* e **aceita** ou **recusa**.
- **Aceitar:** cria o serviço com status `EM ANDAMENTO`, pede o **endereço do serviço** (que pertence ao serviço, não à conta), define a data de expiração e cria notificação. Tudo numa transação; clique duplo não pode criar dois serviços.
- **Recusar:** o pedido é excluído. Não cria serviço nem histórico.

**Serviço**
- Unidade central do sistema. Cada serviço é independente (mesmo entre serviços do mesmo cliente). Tem ID interno (UUID) e número visual (ex.: "SERVIÇO #001").
- Status: `EM ANDAMENTO`, `AGUARDANDO RESPOSTA` (volta para em andamento), `INTERROMPIDO` (pode ser retomado), `CONCLUÍDO` e `CANCELADO` (bloqueados para alterações comuns).
- Só o trabalhador conclui o serviço; não precisa de aprovação do cliente.

**Registros**
- Página do serviço é única e igual para cliente e trabalhador; muda só o que cada um pode fazer.
- Cada registro mostra o autor: **Registro do Cliente** ou **Registro do Trabalhador**. Um lado **nunca edita** o registro do outro.
- Cliente registra: como ficou, fotos finais, opinião, observações.
- Trabalhador registra: problema identificado, avaliação técnica, possível causa, serviço realizado, procedimentos, materiais, peças, intervenções, autorizações/recusas, o que não foi realizado, resultado, fotos, observações.
- Sempre manter separado: **problema informado pelo cliente** ≠ **problema identificado pelo trabalhador**. O sistema só registra; nunca decide quem está certo.
- Autorizações (quebrar parede, piso etc.) são registradas, nunca presumidas. O sistema não afirma que autorização torna algo legal ou livre de responsabilidade.

**Laudo e download**
- Registro ≠ Documento. O laudo (PDF, gerado no servidor) só usa informações já registradas; nunca inventa conteúdo técnico.
- Cliente solicita → trabalhador recebe → gera → cliente baixa.
- "Baixar Informações do Serviço" gera um documento único com tudo até o momento e **não altera** o prazo.

**Retenção (7 dias)**
- Prazo de 7 dias corridos **a partir da criação do serviço**; não reinicia com novos registros, fotos, mudança de status, retomada ou download.
- Ao expirar, uma rotina agendada, **idempotente**, exclui registros, arquivos, documentos, endereço e demais dados. Fica só o **resumo histórico**: data, local, tipo de serviço.
- Falhas da rotina são registradas para nova tentativa.

> **DECISÃO PENDENTE (perguntar ao dono antes da etapa de retenção):** como tratar serviços que duram mais de 7 dias e seriam apagados ainda em andamento (contar a partir da conclusão? permitir extensão manual?). Até lá, implementar `expires_at` como coluna, sem espalhar a regra pelo código, para ser fácil de mudar.

**Notificações**
- Internas, sem chat. Geradas para ações importantes (pedido recebido/aceito/recusado, novo registro, conclusão, cancelamento, interrupção, solicitação e disponibilização de laudo, serviço próximo da exclusão, serviço excluído). Levam o usuário ao recurso relacionado.

## Banco de dados (nomes das tabelas)

`profiles`, `services`, `service_requests`, `service_records`, `service_files`, `notifications`, `service_documents`, `service_history_summary`, `audit_logs`.

- UUID como ID interno; chaves estrangeiras sempre; índices só para consultas frequentes (`services.client_id/worker_id/status/expires_at`, `service_requests.client_id/worker_id/status`, `service_records.service_id`, `service_files.service_id`, `notifications.user_id/read_at`).
- Não usar e-mail como chave de relacionamento.
- Não guardar dado que não tenha finalidade definida (LGPD: minimização).

## Estrutura de pastas (pode ser ajustada, mantendo a separação)

```
app/        (public), (auth), dashboard, servicos, clientes, notificacoes, documentos, admin
components/ ui, forms, servicos, clientes, notificacoes, documentos
lib/        supabase, auth, permissions, services, documents, notifications
types/  validations/  utils/  tests/
```

Componentes visuais genéricos (Button, Input, Modal, Card, StatusBadge) separados dos de negócio (ServiceCard, RecordCard, FileUpload...). Regras de negócio no servidor, **nunca só no frontend**, e sem duplicar a mesma regra em dois lugares.

## Erros e usabilidade

- Mensagens simples ao usuário ("Não foi possível salvar o registro. Tente novamente."); detalhes técnicos só nos logs.
- Feedback em operações demoradas ("Salvando...", "Gerando laudo...").
- Confirmação em ações irreversíveis (recusar pedido, cancelar, concluir, excluir arquivo).
- Mobile first, contraste adequado, áreas de toque grandes, labels nos formulários, não depender só de cor.

## Ordem de desenvolvimento

1. Base e banco → 2. Autenticação e papéis → 3. Permissões (RLS) → 4. Página pública → 5. Pedido de serviço → 6. Serviço e registros → 7. Arquivos → 8. Notificações → 9. Laudo e download → 10. Retenção/exclusão, admin, testes e produção.

Nenhuma funcionalidade secundária passa na frente de uma essencial que ainda não funciona direito.
