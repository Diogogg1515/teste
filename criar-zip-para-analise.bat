@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

echo ================================================================================
echo CRIAR ZIP DO PROJETO SOUZA.L PARA ANÁLISE
echo ================================================================================
echo.

:: Configuração
set "PROJETO=C:\Users\User\souza.l"
set "STAGING=%TEMP%\souza-l-staging"
set "DESTINO=C:\Users\User\Documents\souza-l-analise-%date:~-4%%date:~3,2%%date:~0,2%-%time:~0,2%%time:~3,2%.zip"
set "DESTINO=%DESTINO: =0%"

echo [1/5] Limpando staging anterior...
if exist "%STAGING%" rd /s /q "%STAGING%"
mkdir "%STAGING%"
echo      OK: %STAGING%
echo.

echo [2/5] Copiando projeto (excluindo node_modules, .git, .env...)
robocopy "%PROJETO%" "%STAGING%" /E ^
  /XD node_modules .next .git .vercel .turbo coverage playwright-report test-results dist build .idea ^
  /XF .env .env.local .env.development .env.production .env.test .env.*.local *.tsbuildinfo *.log *.pem *.key ^
  /MAX:2097152 ^
  /NFL /NDL /NP

if %errorlevel% geq 8 (
    echo      ERRO: robocopy falhou com código %errorlevel%
    pause
    exit /b 1
)
echo      OK: Arquivos copiados
echo.

echo [3/5] Criando _INVENTARIO.txt...
cd /d "%PROJETO%"

(
echo ================================================================================
echo INVENTÁRIO DO PROJETO SOUZA.L
echo ================================================================================
echo.
echo Data/Hora: %date% %time%
echo Projeto Original: %PROJETO%
echo.
echo --------------------------------------------------------------------------------
echo VERSÕES
echo --------------------------------------------------------------------------------
node -v 2>nul || echo Node: não disponível
npm -v 2>nul || echo NPM: não disponível
echo.
echo --------------------------------------------------------------------------------
echo PACKAGE.JSON
echo --------------------------------------------------------------------------------
type package.json
echo.
echo --------------------------------------------------------------------------------
echo GIT
echo --------------------------------------------------------------------------------
git branch --show-current 2>nul || echo Branch: não disponível
echo.
git log --oneline -30 2>nul || echo Log: não disponível
echo.
git status --short 2>nul || echo Status: não disponível
echo.
git remote -v 2>nul | findstr /v "://" || git remote -v 2>nul || echo Remote: não disponível
echo.
echo --------------------------------------------------------------------------------
echo MIGRATIONS
echo --------------------------------------------------------------------------------
dir /b supabase\migrations 2>nul || echo Migrations: pasta não encontrada
echo.
echo --------------------------------------------------------------------------------
echo ROTAS (páginas e API)
echo --------------------------------------------------------------------------------
for /r app %%f in (page.tsx route.ts) do (
    set "rota=%%~dpf"
    set "rota=!rota:%PROJETO%\app\=!"
    set "rota=!rota:\=/!"
    echo !rota!%%~nxf
)
echo.
echo --------------------------------------------------------------------------------
echo ENV.EXAMPLE (variáveis)
echo --------------------------------------------------------------------------------
if exist .env.example (
    for /f "tokens=1 delims==" %%a in (.env.example) do echo %%a
) else (
    echo .env.example: não encontrado
)
echo.
echo --------------------------------------------------------------------------------
echo ARQUIVOS EXCLUÍDOS (^>2MB)
echo --------------------------------------------------------------------------------
for /r "%PROJETO%" %%f in (*) do (
    if %%~zf gtr 2097152 (
        set "tamanho=%%~zf"
        set /a mb=!tamanho! / 1048576
        set "caminho=%%f"
        set "caminho=!caminho:%PROJETO%\=!"
        echo !caminho! ^(!mb! MB^)
    )
)
echo.
echo ================================================================================
echo Fim do inventário
echo ================================================================================
) > "%STAGING%\_INVENTARIO.txt"

echo      OK: _INVENTARIO.txt criado
echo.

echo [4/5] Procurando segredos na cópia...
cd /d "%STAGING%"
set "SEGREDOS_ENCONTRADOS=0"

findstr /s /i /c:"sb_secret_" /c:"eyJ" /c:"SUPABASE_SERVICE_ROLE_KEY=" /c:"-----BEGIN PRIVATE KEY-----" *.* 2>nul > "%TEMP%\busca-segredos.txt"

if exist "%TEMP%\busca-segredos.txt" (
    for /f "tokens=*" %%a in (%TEMP%\busca-segredos.txt) do (
        set "SEGREDOS_ENCONTRADOS=1"
        echo      AVISO: %%a
    )
)

if !SEGREDOS_ENCONTRADOS!==0 (
    echo      OK: Nenhum segredo detectado
) else (
    echo.
    echo      ========================================
    echo      ATENÇÃO: POSSÍVEIS SEGREDOS ENCONTRADOS
    echo      ========================================
    echo      Revise os arquivos listados acima antes de compartilhar o ZIP.
    echo      Aperte qualquer tecla para continuar mesmo assim, ou Ctrl+C para cancelar.
    pause >nul
)
echo.

echo [5/5] Criando ZIP...
cd /d "%STAGING%\.."
powershell -NoProfile -Command "Compress-Archive -Path '%STAGING%' -DestinationPath '%DESTINO%' -Force"

if exist "%DESTINO%" (
    echo      OK: ZIP criado
    echo.
    echo ================================================================================
    echo CONCLUÍDO
    echo ================================================================================
    echo ZIP em: %DESTINO%
    for %%f in ("%DESTINO%") do echo Tamanho: %%~zf bytes
    echo.
    echo Limpando staging...
    rd /s /q "%STAGING%"
    echo.
    echo Deseja abrir a pasta? (S/N)
    choice /c SN /n
    if !errorlevel!==1 explorer /select,"%DESTINO%"
) else (
    echo      ERRO: Falha ao criar ZIP
    pause
    exit /b 1
)

echo.
pause
