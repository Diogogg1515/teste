import { defineConfig, devices } from '@playwright/test';
import { readFileSync } from 'fs';
import { resolve } from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = resolve(__filename, '..');

// Carrega tests/.env.test explicitamente — OBRIGATÓRIO para execução de testes
// Não usa fallback silencioso para .env.local para evitar vazamento de configuração de produção
function loadTestEnv() {
  const envPath = resolve(__dirname, 'tests', '.env.test');
  let content: string;
  try {
    content = readFileSync(envPath, 'utf-8');
  } catch (e) {
    throw new Error(
      `Arquivo de ambiente de testes não encontrado ou ilegível: ${envPath}. ` +
      'Copie tests/.env.example para tests/.env.test e preencha com as credenciais do projeto Supabase DEDICADO A TESTES. ' +
      'Não use credenciais de produção ou desenvolvimento.'
    );
  }
  for (const line of content.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eqIndex = trimmed.indexOf('=');
    if (eqIndex === -1) continue;
    const key = trimmed.slice(0, eqIndex).trim();
    const value = trimmed.slice(eqIndex + 1).trim();
    if (!(key in process.env)) {
      process.env[key] = value;
    }
  }
}

loadTestEnv();

function validateTestEnvironment() {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  const testProjectId = process.env.TEST_SUPABASE_PROJECT_ID;

  if (!supabaseUrl || !supabaseAnonKey || !testProjectId) {
    throw new Error(
      'Variáveis de ambiente de teste obrigatórias ausentes: ' +
      'NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY, TEST_SUPABASE_PROJECT_ID. ' +
      'Configure tests/.env.test com um projeto Supabase dedicado para testes.'
    );
  }

  const match = supabaseUrl.match(/^https:\/\/([^.]+)\.supabase\.co$/);
  if (!match) {
    throw new Error(
      'NEXT_PUBLIC_SUPABASE_URL malformada. Esperado: https://<project-id>.supabase.co'
    );
  }

  const actualProjectId = match[1];

  // ID do projeto de desenvolvimento/produção atual (conhecido)
  // Se a URL apontar para este projeto, a execução deve falhar para evitar uso acidental
  const CURRENT_PROJECT_ID = 'smuiikquxjqfnfoxbnyw';
  if (actualProjectId === CURRENT_PROJECT_ID) {
    throw new Error(
      `A URL Supabase aponta para o projeto de desenvolvimento/produção atual (${CURRENT_PROJECT_ID}). ` +
      'Configure tests/.env.test com um projeto Supabase DEDICADO A TESTES (ID diferente).'
    );
  }

  if (actualProjectId !== testProjectId) {
    throw new Error(
      `Project ID na URL (${actualProjectId}) não corresponde a TEST_SUPABASE_PROJECT_ID (${testProjectId}). ` +
      'Verifique se tests/.env.test aponta para o projeto de testes correto.'
    );
  }
}

validateTestEnvironment();

export default defineConfig({
  testDir: './tests/e2e',
  fullyParallel: false, // Serviços têm estado compartilhado
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: 1, // Um worker (testes sequenciais)
  reporter: 'html',

  use: {
    baseURL: process.env.BASE_URL || 'http://localhost:3000',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },

  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
    {
      name: 'mobile',
      use: { ...devices['iPhone 13'] },
    },
  ],

  webServer: {
    command: 'npm run dev',
    url: 'http://localhost:3000',
    reuseExistingServer: !process.env.CI,
    env: {
      NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL!,
      NEXT_PUBLIC_SUPABASE_ANON_KEY: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
      NEXT_PUBLIC_SITE_URL: process.env.NEXT_PUBLIC_SITE_URL!,
    },
  },
});
