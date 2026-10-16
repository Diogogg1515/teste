#!/bin/bash
# Script de verificação do projeto souza.l
# Execute: bash verificar-projeto.sh

echo "=========================================="
echo "VERIFICAÇÃO AUTOMÁTICA - SOUZA.L"
echo "=========================================="
echo ""

echo "[1/3] ESLint..."
npm run lint
LINT_EXIT=$?
echo ""

echo "[2/3] TypeScript..."
npx tsc --noEmit
TSC_EXIT=$?
echo ""

echo "[3/3] Next.js Build..."
npm run build
BUILD_EXIT=$?
echo ""

echo "=========================================="
echo "RESULTADOS"
echo "=========================================="
echo "ESLint:     $([ $LINT_EXIT -eq 0 ] && echo '✅ PASSOU' || echo '❌ FALHOU')"
echo "TypeScript: $([ $TSC_EXIT -eq 0 ] && echo '✅ PASSOU' || echo '❌ FALHOU')"
echo "Build:      $([ $BUILD_EXIT -eq 0 ] && echo '✅ PASSOU' || echo '❌ FALHOU')"
echo ""

if [ $LINT_EXIT -eq 0 ] && [ $TSC_EXIT -eq 0 ] && [ $BUILD_EXIT -eq 0 ]; then
  echo "✅ TODOS OS TESTES PASSARAM"
  exit 0
else
  echo "❌ ALGUNS TESTES FALHARAM - veja os erros acima"
  exit 1
fi
