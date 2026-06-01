#!/bin/bash
# RSI Sniper - Painel de Controle

echo "============================================================"
echo "  RSI SNIPER - Localizando Painel..."
echo "============================================================"
echo ""

# Busca na pasta de dados do MT5 (Wine)
WINE_BASE="$HOME/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users"
PANEL_FOUND=""

if [ -d "$WINE_BASE" ]; then
    for USER_DIR in "$WINE_BASE"/*; do
        if [ -d "$USER_DIR" ]; then
            TERMINAL_PATH="$USER_DIR/AppData/Roaming/MetaQuotes/Terminal"
            if [ -d "$TERMINAL_PATH" ]; then
                for INSTANCE in "$TERMINAL_PATH"/*; do
                    PANEL="$INSTANCE/MQL5/Include/MWM/rsi_panel.py"
                    if [ -f "$PANEL" ]; then
                        PANEL_DIR="$INSTANCE/MQL5/Include/MWM"
                        PANEL_FOUND="1"
                        break 2
                    fi
                done
            fi
        fi
    done
fi

# Fallback: pasta do programa
if [ -z "$PANEL_FOUND" ]; then
    PROG_PANEL="$HOME/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5/Include/MWM/rsi_panel.py"
    if [ -f "$PROG_PANEL" ]; then
        PANEL_DIR="$HOME/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5/Include/MWM"
        PANEL_FOUND="1"
    fi
fi

if [ -n "$PANEL_FOUND" ]; then
    echo "Painel encontrado em:"
    echo "$PANEL_DIR"
    echo ""
    echo "Iniciando painel..."
    cd "$PANEL_DIR"
    python3 rsi_panel.py
else
    echo ""
    echo "============================================================"
    echo "  ERRO: Painel nao encontrado!"
    echo "============================================================"
    echo ""
    echo "Execute o instalador primeiro."
    echo ""
    read -p "Pressione ENTER para fechar..."
fi
