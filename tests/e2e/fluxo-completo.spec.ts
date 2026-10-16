import { test, expect } from '@playwright/test';

// Fluxo completo V1: cadastro cliente → pedido trabalhador → aceite → registros → conclusão

test.describe('Fluxo completo V1', () => {
  const timestamp = Date.now();
  const clientEmail = `cliente-${timestamp}@teste.local`;
  const clientPassword = 'Senha123!';
  let clientCode = '';

  test('1. Cliente: cadastro', async ({ page }) => {
    await page.goto('/cadastro');

    await page.fill('input[name="name"]', 'Cliente Teste E2E');
    await page.fill('input[name="email"]', clientEmail);
    await page.fill('input[name="password"]', clientPassword);

    await page.click('button[type="submit"]');

    // Aguarda redirect para painel
    await expect(page).toHaveURL(/\/painel/);

    // Captura código do cliente
    const codeElement = page.locator('text=/[A-Z0-9]{6}/');
    clientCode = await codeElement.textContent() || '';

    expect(clientCode).toMatch(/^[A-Z0-9]{6}$/);
    console.log('Código cliente:', clientCode);
  });

  test('2. Trabalhador: login e cria pedido', async ({ page }) => {
    // Login trabalhador (credenciais de dev/seed)
    await page.goto('/login');
    await page.fill('input[type="email"]', process.env.WORKER_EMAIL || 'worker@souza.local');
    await page.fill('input[type="password"]', process.env.WORKER_PASSWORD || 'senha123');
    await page.click('button[type="submit"]');

    await expect(page).toHaveURL(/\/painel/);

    // Novo serviço
    await page.click('a[href="/pedidos/novo"]');

    // Procura cliente por código
    await page.fill('input[name="client_code"]', clientCode);
    await page.click('button:has-text("Procurar")');

    // Preenche pedido
    await page.fill('input[name="service_type"]', 'Reparo vazamento - E2E Test');
    await page.click('button[type="submit"]');

    await expect(page.locator('text=/enviado|criado/i')).toBeVisible();
  });

  test('3. Cliente: aceita pedido', async ({ page, context }) => {
    // Login cliente
    await page.goto('/login');
    await page.fill('input[type="email"]', clientEmail);
    await page.fill('input[type="password"]', clientPassword);
    await page.click('button[type="submit"]');

    await expect(page).toHaveURL(/\/painel/);

    // Vê pedido pendente
    const pedidoCard = page.locator('[href*="/pedidos/"]').first();
    await expect(pedidoCard).toBeVisible();
    await pedidoCard.click();

    // Aceita
    await page.fill('input[name="address"]', 'Rua Teste E2E, 123 - São Paulo');
    await page.click('button:has-text("Aceitar")');

    // Redirect para serviço
    await expect(page).toHaveURL(/\/servicos\//);
    await expect(page.locator('text=/EM ANDAMENTO/i')).toBeVisible();
  });

  test('4. Cliente: adiciona registro com foto', async ({ page }) => {
    // Login cliente
    await page.goto('/login');
    await page.fill('input[type="email"]', clientEmail);
    await page.fill('input[type="password"]', clientPassword);
    await page.click('button[type="submit"]');

    // Vai para serviço (primeiro da lista)
    await page.click('[href*="/servicos/"]');

    // Adiciona registro
    await page.fill('textarea[name="content"]', 'Vazamento começou ontem à noite. Teste E2E.');

    // Upload foto (opcional - cria arquivo teste)
    // await page.setInputFiles('input[type="file"]', 'tests/fixtures/photo.jpg');

    await page.click('button:has-text("Salvar registro")');

    await expect(page.locator('text=/Registro do Cliente/i')).toBeVisible();
  });

  test('5. Trabalhador: adiciona registro técnico', async ({ page }) => {
    // Login trabalhador
    await page.goto('/login');
    await page.fill('input[type="email"]', process.env.WORKER_EMAIL || 'worker@souza.local');
    await page.fill('input[type="password"]', process.env.WORKER_PASSWORD || 'senha123');
    await page.click('button[type="submit"]');

    // Vai para serviço (busca por "E2E Test")
    await page.click('a:has-text("E2E Test")');

    // Adiciona registro
    await page.fill('textarea[name="content"]', 'Problema identificado: conexão da válvula. Substituído. Teste E2E.');
    await page.click('button:has-text("Salvar registro")');

    await expect(page.locator('text=/Registro do Trabalhador/i')).toBeVisible();
  });

  test('6. Trabalhador: conclui serviço', async ({ page }) => {
    // Login trabalhador
    await page.goto('/login');
    await page.fill('input[type="email"]', process.env.WORKER_EMAIL || 'worker@souza.local');
    await page.fill('input[type="password"]', process.env.WORKER_PASSWORD || 'senha123');
    await page.click('button[type="submit"]');

    // Vai para serviço
    await page.click('a:has-text("E2E Test")');

    // Expande acordeão "Marcar como Concluído"
    await page.click('summary:has-text("Concluído")');

    // Confirma
    await page.click('button:has-text("Confirmar")');

    await expect(page.locator('text=/CONCLUÍDO/i')).toBeVisible();
  });

  test('7. Cliente: solicita e baixa laudo', async ({ page }) => {
    // Login cliente
    await page.goto('/login');
    await page.fill('input[type="email"]', clientEmail);
    await page.fill('input[type="password"]', clientPassword);
    await page.click('button[type="submit"]');

    // Vai para serviço
    await page.click('[href*="/servicos/"]');

    // Solicita laudo
    await page.click('button:has-text("Solicitar Laudo")');
    await expect(page.locator('text=/solicitado/i')).toBeVisible();

    // TODO: Trabalhador gera laudo (test 8)
    // TODO: Cliente baixa (test 9)
  });

  test('8. Cliente: baixa informações completas', async ({ page }) => {
    // Login cliente
    await page.goto('/login');
    await page.fill('input[type="email"]', clientEmail);
    await page.fill('input[type="password"]', clientPassword);
    await page.click('button[type="submit"]');

    // Vai para serviço
    await page.click('[href*="/servicos/"]');

    // Download TXT
    const downloadPromise = page.waitForEvent('download');
    await page.click('a:has-text("Baixar TXT")');
    const download = await downloadPromise;

    expect(download.suggestedFilename()).toMatch(/servico-\d+-.*\.txt/);
  });
});
