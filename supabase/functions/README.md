# Edge Functions - souza.l

## cleanup-services

**Descrição:** Limpeza automática de serviços expirados (retenção 7 dias).

**Execução:** Cron diário via Dashboard Supabase.

**Schedule:** `0 3 * * *` (3h da manhã, todos os dias)

**Ações:**
1. Notifica usuários sobre serviços que expiram em 24-48h
2. Cria resumo histórico dos serviços expirados
3. Exclui registros, arquivos e dados sensíveis
4. Mantém metadados mínimos (número, data, local, tipo)

**Configuração:**

1. Deploy da função:
```bash
npx supabase functions deploy cleanup-services
```

2. Configurar cron no Dashboard:
- Ir para Database > Cron Jobs (ou Edge Functions > Schedules)
- Criar schedule: `0 3 * * *`
- Endpoint: `/cleanup-services`
- Authorization: Service role key

3. Testar manualmente:
```bash
curl -X POST https://YOUR_PROJECT.supabase.co/functions/v1/cleanup-services \
  -H "Authorization: Bearer YOUR_SERVICE_ROLE_KEY"
```

**Segurança:**
- Apenas service role pode executar
- Idempotente (seguro re-executar)
- Processa em lotes (100 serviços por vez)
- Registra erros sem parar processo

**Monitoramento:**
- Logs em Dashboard > Edge Functions > Logs
- Retorna JSON com contadores
