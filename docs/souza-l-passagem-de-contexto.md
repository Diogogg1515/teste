# souza.l — Passagem de contexto para o Claude Code

Este documento resume como o projeto vem sendo conduzido nas conversas com o Claude (chat), o que já foi feito, onde paramos e onde queremos chegar. Leia tudo antes de agir.

---

## 1. Quem é o dono do projeto (como conversar com ele)

- Entende bem a estrutura de um projeto de código, mas **não sabe programar totalmente**. Não conhece React nem segurança em profundidade.
- Explique **em português, em linguagem simples**, e diga *por que* cada coisa está sendo feita.
- Trabalha no **Windows (PowerShell)**, com VS Code. Node.js 24 LTS e Git instalados.
- Quer escrever código de verdade, com liberdade (não quer ferramenta no-code como Lovable).
- Pasta local: `C:\Users\imsouza\souza.l`. Repositório privado no GitHub: `souza.l` (branch `main`).

## 2. O que é o projeto

Aplicação web que conecta **clientes** e **prestadores de serviço** e documenta cada serviço (registros, fotos, laudo, download).

- **V1 = produto real para o primeiro profissional (o pai do dono, encanador)** e, ao mesmo tempo, a primeira vitrine de uma plataforma futura.
- Perfis de acesso: `client`, `worker` e `admin`. O admin **não** vê o conteúdo dos serviços.
- Direção visual: "profissional moderno + tech minimalista".

**Stack:** Next.js, React, TypeScript, Tailwind, Supabase (Auth, PostgreSQL, Storage, RLS), Vercel, GitHub. Projeto Supabase `souza-l` na região de São Paulo.

## 3. Como trabalhamos (regras do processo)

1. **Etapa por etapa.** Nunca gerar tudo de uma vez. Cada etapa é feita, **testada** e só então avançamos.
2. **Testar de verdade.** Cada etapa termina com testes (SQL em `supabase/tests`, e fluxo real no navegador). Ao reportar, diferenciar claramente: *"li o código"* de *"executei e funcionou"*.
3. **SQL versionado.** Todo SQL vai em `supabase/migrations/` (e testes em `supabase/tests/`). Nada de alterar o banco "no escuro".
4. **Enviar ao GitHub** (branch `main`) ao concluir cada etapa.
5. **Antes de mudar algo existente, avisar e pedir confirmação.** Nada de alterar código, migration ou banco sem o dono saber.
6. **O briefing não pode ser alterado sem autorização dele.** Decisões técnicas que fogem do briefing (ex.: o campo `service_type` em `service_requests`) são registradas como decisão técnica separada.
7. **Documentos para ele, em Word (.docx)** quando forem documentos de leitura/decisão.
8. **Segurança em camadas:** a regra nunca fica só na interface. Banco (RLS + funções com validação interna) é a barreira real.

## 4. Documentos-fonte do projeto

- **Briefing V1.0** (mais de 4 mil linhas, seções 1 a 4.127): fonte principal das decisões de produto.
- **Objetivos** (regras de comportamento do sistema V1, 32 seções).
- **Briefing2** (evolução da V1, outubro/2026): visão do produto real + vitrine, perfil público, direção visual, planta tela por tela.
- **CLAUDE.md** dentro do projeto.
- **Ordem de trabalho** (lista de etapas da V1; a próxima é a "etapa 5").

## 5. O que já está feito

- Banco: 9 tabelas criadas no Supabase, mais `worker_profiles` (perfil público) e as tabelas da agenda.
- Login, logout, cadastro de cliente (perfil criado por gatilho no banco, papel sempre `client`), recuperação de senha e proteção de páginas por papel. Testado.
- Regras de acesso / RLS das tabelas, funções de pedido e de serviço (`find_client_by_code`, `create_service_request`, `accept_service_request`, `reject_service_request`, `withdraw_service_request`, `change_service_status`), privilégios restritos. 33 testes de SQL passaram.
- Home pública e perfil público do profissional (`/` e `/p/[slug]`). Teste de segurança do visitante passou.
- **Agenda de orçamentos** (exclusiva do profissional): registra horário, local e nome do cliente; depois do horário o painel pergunta "Você realizou esse orçamento? Sim/Não" (Sim = ponto verde, Não = ponto vermelho). 14 testes do banco OK.
- **Convite por link:** o profissional envia o link pelo WhatsApp, o cliente cria a conta e aceita ali. O código do cliente continua como alternativa. Testado no banco e no navegador.

## 6. Decisões de produto já tomadas

- Só o trabalhador muda o status do serviço. O cliente se manifesta pelos próprios registros.
- O trabalhador pode retirar um pedido pendente.
- Fotos do registro são apenas do serviço realizado. O endereço é necessário para o laudo.
- A agenda de orçamentos é separada dos serviços e funciona mesmo que o cliente não use o site (ligação "Virou serviço" parte da agenda).
- Das ideias extras sugeridas, só o **prontuário do imóvel** interessa, e fica para depois.
- Escopo grande na V1 foi mantido de propósito, e vamos testar assim mesmo.

## 7. Onde paramos

**Próximo passo: página do serviço e registros (etapa 5 da ordem de trabalho).**

Auditoria de segurança feita pelo Claude Code (relatório `teste.txt`): foi **estática** (leitura de código, nada executado). Resultado: **nenhuma vulnerabilidade confirmada** (RLS, isolamento entre usuários, RPCs, IDOR, escalada de privilégio, notificações, grants). Isso é bom sinal, mas **não é prova**; precisa de testes práticos.

Pendências levantadas pela auditoria (nenhuma é falha de autorização):

| Pendência | Situação |
|---|---|
| Retenção de 7 dias | O campo `expires_at` existe, mas **não há rotina de limpeza** (cron, função ou job). Envolve privacidade. |
| Upload de fotos/vídeos/documentos | Parcial. Tabelas existem, o fluxo completo não. |
| PDF / laudo | Não implementado (nem biblioteca no `package.json`). |
| Spam de solicitações | Há índice contra duplicadas pendentes, mas sem rate limit/cooldown. Pode esperar enquanto só 1 profissional usa. |
| Código do cliente | 6 caracteres, gerado com `random()`. Tratar como identificador compartilhável, **nunca como senha**. |

## 8. Testes práticos que ainda precisam ser feitos (de verdade, não por leitura)

1. Duas contas de cliente + uma de profissional: o cliente A tenta abrir o serviço do cliente B colando o ID na URL (deve falhar).
2. Conferir RLS ativa em todas as tabelas: `select tablename, rowsecurity from pg_tables where schemaname = 'public';` (todas `true`).
3. Logado como cliente, tentar mudar o próprio `role` para `worker` pelo cliente Supabase (deve falhar).
4. Chamar as funções do banco sem login (deve dar `not_allowed`) e confirmar que o papel `anon` não tem `execute` onde não deve.
5. Quando o upload for feito: revisar as regras (policies) dos buckets do Storage antes de liberar. É o ponto onde mais vazam dados.

## 9. Decisão em aberto (precisa ser resolvida antes de ter dados reais)

**Regra dos 7 dias de exclusão.** O dono delegou ao assistente a decisão (manter, aumentar ou retirar). Regra original do briefing: o serviço é apagado 7 dias após a criação, ficando só o resumo (data, local, tipo), e o cliente pode baixar as informações antes. Se for mantida, é preciso implementar a limpeza automática (registros **e** arquivos do Storage).

## 10. Onde queremos chegar

Um **V1 utilizável**: o pai do dono (encanador) consegue usar no dia a dia para agendar orçamentos, convidar clientes, registrar serviços com fotos e entregar o laudo. A pergunta que guia tudo é *"o que falta para ser utilizável?"*, e não *"o que mais dá para melhorar?"*.

Depois da etapa 5, a ideia é fazer uma **auditoria de completude do V1**, comparando briefing → banco → backend → Server Actions → frontend → fluxo real, e classificando cada requisito como implementado, parcial, não implementado ou fora da V1.

## 11. Como o Claude Code deve se comportar neste projeto

- Ler este documento, o `CLAUDE.md` e o briefing antes de propor qualquer coisa.
- Propor a etapa, explicar em linguagem simples, e **esperar o "pode seguir"** antes de mexer em código, migration ou banco.
- Ao terminar, listar: o que mudou, quais arquivos, **o que foi testado de verdade** e o que ficou só "lido".
- Não classificar como vulnerabilidade o que é funcionalidade pendente, e vice-versa (a auditoria anterior usou: confirmado / não confirmado / incorreto / necessita teste).
- Quando tiver dúvida de produto, perguntar ao dono em vez de decidir sozinho.
