# Testes E2E - souza.l

## Setup

```bash
cd tests
npm install
npx playwright install
```

## Executar

```bash
# Dev local (precisa app rodando em localhost:3000)
npm test

# UI mode (debug visual)
npm run test:ui

# Headed (vê navegador)
npm run test:headed

# Debug específico
npx playwright test tests/e2e/fluxo-completo.spec.ts --debug
```

## Variáveis ambiente

`.env.test`:
```
BASE_URL=http://localhost:3000
WORKER_EMAIL=worker@souza.local
WORKER_PASSWORD=senha123
```

## CI/CD

GitHub Actions (`.github/workflows/e2e.yml`):
```yaml
name: E2E Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
      - run: npm ci
      - run: npx playwright install --with-deps
      - run: npm test
        env:
          BASE_URL: ${{ secrets.STAGING_URL }}
          WORKER_EMAIL: ${{ secrets.TEST_WORKER_EMAIL }}
```

## Cobertura

Testes implementados:
- ✅ Cadastro cliente
- ✅ Login trabalhador + criar pedido
- ✅ Cliente aceita pedido
- ✅ Registros (cliente + trabalhador)
- ✅ Conclusão serviço
- ✅ Download informações
- ⏳ Laudo (solicitar + gerar + baixar)

## Fixtures

Cria pasta `tests/fixtures/` com:
- `photo.jpg` (foto teste upload)
- `client-seed.json` (dados teste)
