@echo off
chcp 65001 >nul
title RSI Sniper - Painel de Controle

echo ============================================================
echo   RSI SNIPER - Localizando Painel...
echo ============================================================
echo.

REM Procura na pasta de DADOS do MT5 (AppData)
set "FOUND="
for /d %%i in ("%APPDATA%\MetaQuotes\Terminal\*") do (
    if exist "%%i\MQL5\Include\MWM\rsi_panel.py" (
        set "PANEL_DIR=%%i\MQL5\Include\MWM"
        set "FOUND=1"
    )
)

REM Se encontrou na pasta de dados
if defined FOUND (
    echo Painel encontrado em:
    echo %PANEL_DIR%
    echo.
    echo Iniciando painel...
    cd /d "%PANEL_DIR%"
    python rsi_panel.py
    if errorlevel 1 (
        echo.
        echo ERRO: Falha ao executar o painel.
        echo Verifique se Python esta instalado corretamente.
        echo.
        pause
    )
    goto :end
)

REM Fallback: pasta do programa (instalacoes antigas)
if exist "C:\Program Files\MetaTrader 5\MQL5\Include\MWM\rsi_panel.py" (
    echo Painel encontrado em:
    echo C:\Program Files\MetaTrader 5\MQL5\Include\MWM
    echo.
    echo Iniciando painel...
    cd /d "C:\Program Files\MetaTrader 5\MQL5\Include\MWM"
    python rsi_panel.py
    goto :end
)

REM Nao encontrou
echo.
echo ============================================================
echo   ERRO: Painel nao encontrado!
echo ============================================================
echo.
echo O arquivo rsi_panel.py nao foi encontrado.
echo.
echo Possiveis solucoes:
echo   1. Execute o instalador primeiro (Instalar_RSI_Sniper.bat)
echo   2. Verifique se o MetaTrader 5 esta instalado
echo   3. Verifique se Python esta instalado
echo.
pause

:end
