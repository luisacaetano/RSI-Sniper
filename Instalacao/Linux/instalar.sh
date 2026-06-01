#!/bin/bash
echo "════════════════════════════════════════════════════════════"
echo "  RSI SNIPER - Instalador (Linux)"
echo "════════════════════════════════════════════════════════════"
cd "$(dirname "$0")/.."
python3 install_rsi_sniper.py
echo ""
read -p "Pressione ENTER para fechar..."
