@echo off
chcp 65001 >nul
title RSI Sniper - Instalador
cd /d "%~dp0.."
python install_rsi_sniper.py
echo.
echo Pressione qualquer tecla para fechar...
pause >nul
