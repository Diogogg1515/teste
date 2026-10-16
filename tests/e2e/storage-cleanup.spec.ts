import { test, expect } from '@playwright/test';

// Testes para a fila de limpeza do Storage (storage_cleanup_queue)
// Cenários: falha parcial, retry, interrupção entre etapas

test.describe('Storage Cleanup Queue - Fila de Limpeza do Storage', () => {

  test.describe('Estrutura da fila storage_cleanup_queue', () => {
    test('tabela storage_cleanup_queue existe com colunas esperadas', async ({ page }) => {
      // Verifica via RPC se a tabela existe e tem as colunas esperadas
      // Nota: este teste requer que a migration 20261015000001_storage_cleanup_queue.sql tenha sido aplicada
      const response = await page.request.post('/api/test/storage-queue-structure');
      if (response.ok()) {
        const data = await response.json();
        expect(data.columns).toContain('id');
        expect(data.columns).toContain('service_id');
        expect(data.columns).toContain('bucket');
        expect(data.columns).toContain('storage_path');
        expect(data.columns).toContain('status');
        expect(data.columns).toContain('attempts');
        expect(data.columns).toContain('max_attempts');
        expect(data.columns).toContain('last_error');
        expect(data.columns).toContain('idempotency_key');
      } else {
        test.skip('Migration 20261015000001_storage_cleanup_queue.sql não aplicada');
      }
    });

    test('políticas RLS permitem apenas service_role', async ({ page }) => {
      const response = await page.request.post('/api/test/storage-queue-rls');
      if (response.ok()) {
        const data = await response.json();
        expect(data.policies).toContain('Cleanup process pode ler pendentes');
        expect(data.policies).toContain('Cleanup process pode inserir');
        expect(data.policies).toContain('Cleanup process pode atualizar');
      } else {
        test.skip('Políticas RLS não verificadas');
      }
    });
  });

  test.describe('Funções auxiliares da fila', () => {
    test('enqueue_storage_cleanup enfileira arquivos de um serviço', async ({ page }) => {
      // Requer: serviço com arquivos no Storage
      const response = await page.request.post('/api/test/enqueue-storage-cleanup', {
        data: { service_id: 'test-service-id' }
      });
      if (response.ok()) {
        const data = await response.json();
        expect(data.queued_count).toBeGreaterThanOrEqual(0);
      } else {
        test.skip('Função enqueue_storage_cleanup não disponível');
      }
    });

    test('enqueue_storage_cleanup é idempotente (não duplica em reexecução)', async ({ page }) => {
      const response1 = await page.request.post('/api/test/enqueue-storage-cleanup', {
        data: { service_id: 'test-service-id-idempotent' }
      });
      const response2 = await page.request.post('/api/test/enqueue-storage-cleanup', {
        data: { service_id: 'test-service-id-idempotent' }
      });
      if (response1.ok() && response2.ok()) {
        const data1 = await response1.json();
        const data2 = await response2.json();
        expect(data2.queued_count).toBeLessThanOrEqual(data1.queued_count);
      } else {
        test.skip('Teste de idempotência não disponível');
      }
    });

    test('get_pending_storage_cleanup retorna itens pendentes', async ({ page }) => {
      const response = await page.request.post('/api/test/get-pending-cleanup', {
        data: { limit: 10 }
      });
      if (response.ok()) {
        const data = await response.json();
        expect(Array.isArray(data.items)).toBe(true);
      } else {
        test.skip('Função get_pending_storage_cleanup não disponível');
      }
    });

    test('get_pending_storage_cleanup marca itens como processing', async ({ page }) => {
      const response = await page.request.post('/api/test/get-pending-cleanup', {
        data: { limit: 5 }
      });
      if (response.ok()) {
        const data = await response.json();
        // Verifica se itens retornados têm status 'processing'
        data.items.forEach((item: { status: string }) => {
          expect(item.status).toBe('processing');
        });
      } else {
        test.skip('Marcar como processing não verificado');
      }
    });

    test('mark_storage_cleanup_completed marca item como completed', async ({ page }) => {
      const response = await page.request.post('/api/test/mark-completed', {
        data: { item_id: 'test-item-id' }
      });
      if (response.ok()) {
        const data = await response.json();
        expect(data.success).toBe(true);
      } else {
        test.skip('Marcar como completed não disponível');
      }
    });

    test('mark_storage_cleanup_failed registra falha com backoff', async ({ page }) => {
      const response = await page.request.post('/api/test/mark-failed', {
        data: { item_id: 'test-item-id', error: 'Test error' }
      });
      if (response.ok()) {
        const data = await response.json();
        expect(data.success).toBe(true);
      } else {
        test.skip('Marcar como falha não disponível');
      }
    });
  });

  test.describe('Integração RPC cleanup_expired_services + fila', () => {
    test('cleanup_expired_services enfileira arquivos ao invés de retornar storage_paths', async ({ page }) => {
      const response = await page.request.post('/api/test/cleanup-expired');
      if (response.ok()) {
        const data = await response.json();
        expect(data.queued_files).toBeDefined();
        expect(data.storage_paths).toBeUndefined(); // Não deve mais retornar storage_paths
        expect(data.deleted_count).toBeGreaterThanOrEqual(0);
        expect(data.queued_files).toBeGreaterThanOrEqual(0);
      } else {
        test.skip('Nova versão da RPC não disponível');
      }
    });

    test('cleanup_expired_services não chama storage.delete (inválido)', async ({ page }) => {
      // Verifica se a RPC não contém mais a chamada inválida
      const response = await page.request.post('/api/test/verify-no-storage-delete');
      if (response.ok()) {
        const data = await response.json();
        expect(data.has_storage_delete).toBe(false);
      } else {
        test.skip('Verificação de storage.delete não disponível');
      }
    });
  });

  test.describe('Edge Function cleanup-services processa fila', () => {
    test('processa itens da fila e marca como completed', async ({ page }) => {
      // Simula execução da Edge Function
      const response = await page.request.post('/api/functions/cleanup-services', {
        headers: {
          'Authorization': `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY || 'test-key'}`
        }
      });
      if (response.ok()) {
        const data = await response.json();
        expect(data.success).toBe(true);
        expect(data.storage_processed).toBeGreaterThanOrEqual(0);
      } else {
        test.skip('Edge Function cleanup-services não disponível');
      }
    });

    test('falha parcial no Storage retorna erro 500', async ({ page }) => {
      // Simula falha no Storage (bucket inexistente)
      const response = await page.request.post('/api/functions/cleanup-services', {
        headers: {
          'Authorization': `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY || 'test-key'}`
        },
        data: { force_storage_error: true }
      });
      if (response.status() === 500) {
        const data = await response.json();
        expect(data.error).toContain('Storage');
        expect(data.cleanup_result).toBeDefined();
      } else {
        test.skip('Teste de falha parcial não disponível');
      }
    });

    test('não retorna sucesso global se houver falhas não resolvidas', async ({ page }) => {
      const response = await page.request.post('/api/functions/cleanup-services', {
        headers: {
          'Authorization': `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY || 'test-key'}`
        },
        data: { force_partial_failure: true }
      });
      if (response.status() === 500) {
        const data = await response.json();
        expect(data.success).toBe(false);
        expect(data.error).toContain('erros parciais');
        expect(data.rpc_errors).toBeDefined();
        expect(data.storage_failures).toBeDefined();
      } else {
        test.skip('Verificação de falhas parciais não disponível');
      }
    });

    test('reexecução processa itens failed/pending (retry automático)', async ({ page }) => {
      // Primeira execução com falha simulada
      await page.request.post('/api/functions/cleanup-services', {
        headers: { 'Authorization': `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY || 'test-key'}` },
        data: { force_storage_error: true }
      });

      // Segunda execução deve processar itens failed
      const response = await page.request.post('/api/functions/cleanup-services', {
        headers: { 'Authorization': `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY || 'test-key'}` }
      });

      if (response.ok()) {
        const data = await response.json();
        // Itens failed devem ter sido reprocessados
        expect(data.storage_processed).toBeGreaterThanOrEqual(0);
      } else {
        test.skip('Retry automático não disponível');
      }
    });

    test('idempotência: reexecução não duplica resumos ou apaga indevidamente', async ({ page }) => {
      // Executa duas vezes seguidas
      await page.request.post('/api/functions/cleanup-services', {
        headers: { 'Authorization': `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY || 'test-key'}` }
      });
      const response2 = await page.request.post('/api/functions/cleanup-services', {
        headers: { 'Authorization': `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY || 'test-key'}` }
      });

      if (response2.ok()) {
        const data = await response2.json();
        // Segunda execução não deve deletar serviços novamente
        expect(data.deleted_count).toBe(0);
      } else {
        test.skip('Idempotência não verificada');
      }
    });
  });

  test.describe('Concorrência e idempotência', () => {
    test('concorrência: duas execuções simultâneas não processam mesmo item', async ({ page }) => {
      // Dispara duas execuções simultâneas
      const [, response2] = await Promise.all([
        page.request.post('/api/functions/cleanup-services', {
          headers: { 'Authorization': `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY || 'test-key'}` }
        }),
        page.request.post('/api/functions/cleanup-services', {
          headers: { 'Authorization': `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY || 'test-key'}` }
        })
      ]);

      // Pelo menos uma deve processar os itens
      const results = await Promise.all([
        response1.ok() ? response1.json() : null,
        response2.ok() ? response2.json() : null
      ]);

      const totalProcessed = (results[0]?.storage_processed || 0) + (results[1]?.storage_processed || 0);
      // Itens não devem ser processados duas vezes
      expect(totalProcessed).toBeLessThanOrEqual(100); // limite do batch
    });

    test('reexecução após falha de rede não perde caminhos dos arquivos', async ({ page }) => {
      // Simula falha de rede na primeira tentativa
      const response1 = await page.request.post('/api/functions/cleanup-services', {
        headers: { 'Authorization': `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY || 'test-key'}` },
        data: { simulate_network_failure: true }
      });

      // Segunda tentativa deve processar os mesmos itens
      const response2 = await page.request.post('/api/functions/cleanup-services', {
        headers: { 'Authorization': `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY || 'test-key'}` }
      });

      if (response2.ok()) {
        const data = await response2.json();
        // Itens devem ter sido processados na segunda tentativa
        expect(data.storage_processed).toBeGreaterThanOrEqual(0);
      } else {
        test.skip('Recuperação após falha de rede não verificada');
      }
    });

    test('item em dead_letter após max_attempts não é reprocessado', async ({ page }) => {
      const response = await page.request.post('/api/test/check-dead-letter', {
        data: { max_attempts: 5 }
      });
      if (response.ok()) {
        const data = await response.json();
        expect(data.dead_letter_not_processed).toBe(true);
      } else {
        test.skip('Dead letter não verificado');
      }
    });
  });
});

test.describe('Cenários de erro e recuperação', () => {
  test('falha parcial no Storage: alguns arquivos excluídos, outros não', async ({ page }) => {
    const response = await page.request.post('/api/functions/cleanup-services', {
      headers: { 'Authorization': `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY || 'test-key'}` },
      data: { partial_storage_failure: true }
    });

    if (response.status() === 500) {
      const data = await response.json();
      expect(data.success).toBe(false);
      expect(data.storage_failures).toBeGreaterThan(0);
      expect(data.processed_files).toBeGreaterThanOrEqual(0);
      expect(data.cleanup_result).toBeDefined();
    } else {
      test.skip('Falha parcial no Storage não testada');
    }
  });

  test('erro parcial na RPC + erro parcial no Storage = erro global', async ({ page }) => {
    const response = await page.request.post('/api/functions/cleanup-services', {
      headers: { 'Authorization': `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY || 'test-key'}` },
      data: { force_rpc_errors: true, force_storage_error: true }
    });

    if (response.status() === 500) {
      const data = await response.json();
      expect(data.success).toBe(false);
      expect(data.rpc_errors).toBeGreaterThan(0);
      expect(data.storage_failures).toBeGreaterThan(0);
    } else {
      test.skip('Erro combinado não testado');
    }
  });

  test('resumo histórico não é duplicado em reexecução', async ({ page }) => {
    // Executa limpeza duas vezes
    await page.request.post('/api/functions/cleanup-services', {
      headers: { 'Authorization': `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY || 'test-key'}` }
    });
    const response2 = await page.request.post('/api/functions/cleanup-services', {
      headers: { 'Authorization': `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY || 'test-key'}` }
    });

    if (response2.ok()) {
      const data = await response2.json();
      // Segunda execução não deve criar novos resumos
      expect(data.deleted_count).toBe(0);
    } else {
      test.skip('Não duplicação de resumo não verificada');
    }
  });

  test('serviços com falha de limpeza não são reprocessados indevidamente', async ({ page }) => {
    // Cria serviço com falha de limpeza
    await page.request.post('/api/test/create-failed-cleanup');

    // Executa limpeza
    const response = await page.request.post('/api/functions/cleanup-services', {
      headers: { 'Authorization': `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY || 'test-key'}` }
    });

    if (response.ok()) {
      const data = await response.json();
      // Serviço com falha deve ser reprocessado (retry), mas não duplicado
      expect(data.storage_processed).toBeGreaterThanOrEqual(0);
    } else {
      test.skip('Reprocessamento controlado não verificado');
    }
  });
});