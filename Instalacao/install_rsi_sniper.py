#!/usr/bin/env python3
"""
RSI SNIPER - Instalador Automático Multiplataforma
Detecta a pasta de DADOS do MetaTrader 5 (onde fica o MQL5)
Compatível: Windows, macOS (Wine), Linux (Wine)
"""

import os
import sys
import platform
from pathlib import Path
import shutil

class RSISniperInstaller:
    def __init__(self):
        self.sistema = platform.system()
        self.mql5_path = None  # Pasta MQL5 de dados (não a do programa!)
        self.arquivos_instalados = []

    def encontrar_pastas_mql5(self):
        """
        Encontra todas as pastas MQL5 de dados do MetaTrader 5.

        IMPORTANTE: O MT5 tem duas pastas diferentes:
        - Pasta do PROGRAMA: C:/Program Files/MetaTrader 5/ (onde esta o .exe)
        - Pasta de DADOS: %APPDATA%/MetaQuotes/Terminal/<ID>/MQL5/ (onde ficam os EAs)

        Esta funcao procura a pasta de DADOS, que e onde devemos instalar.
        """
        home = Path.home()
        pastas_encontradas = []

        if self.sistema == "Darwin":  # macOS
            # Wine prefix padrão do MT5 no macOS
            wine_appdata = home / "Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users"

            # Procura em todas as pastas de usuário do Wine
            if wine_appdata.exists():
                for user_folder in wine_appdata.iterdir():
                    if user_folder.is_dir():
                        terminal_path = user_folder / "AppData/Roaming/MetaQuotes/Terminal"
                        if terminal_path.exists():
                            for instance in terminal_path.iterdir():
                                mql5_path = instance / "MQL5"
                                try:
                                    if mql5_path.exists() and instance.name != "Common":
                                        pastas_encontradas.append(mql5_path)
                                except PermissionError:
                                    pass

            # Fallback: pasta do programa (alguns setups antigos)
            programa_path = home / "Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5"
            if programa_path.exists() and programa_path not in pastas_encontradas:
                pastas_encontradas.append(programa_path)

        elif self.sistema == "Windows":
            # Pasta de dados do Windows
            appdata = Path(os.environ.get("APPDATA", ""))
            terminal_path = appdata / "MetaQuotes/Terminal"

            if terminal_path.exists():
                for instance in terminal_path.iterdir():
                    mql5_path = instance / "MQL5"
                    try:
                        if mql5_path.exists() and instance.name != "Common":
                            pastas_encontradas.append(mql5_path)
                    except PermissionError:
                        # Ignora pastas sem permissao de acesso
                        pass

            # Fallback: pasta do programa
            for prog_path in [Path("C:/Program Files/MetaTrader 5/MQL5"),
                              Path("C:/Program Files (x86)/MetaTrader 5/MQL5")]:
                if prog_path.exists() and prog_path not in pastas_encontradas:
                    pastas_encontradas.append(prog_path)

        else:  # Linux
            # Wine prefix padrão
            wine_appdata = home / ".wine/drive_c/users"

            if wine_appdata.exists():
                for user_folder in wine_appdata.iterdir():
                    if user_folder.is_dir():
                        terminal_path = user_folder / "AppData/Roaming/MetaQuotes/Terminal"
                        if terminal_path.exists():
                            for instance in terminal_path.iterdir():
                                mql5_path = instance / "MQL5"
                                try:
                                    if mql5_path.exists() and instance.name != "Common":
                                        pastas_encontradas.append(mql5_path)
                                except PermissionError:
                                    pass

        return pastas_encontradas

    def detectar_mt5(self):
        """Detecta automaticamente a pasta MQL5 do MetaTrader 5"""
        print(f"\n{'='*60}")
        print(f"  🎯 RSI SNIPER - Instalador ({self.sistema})")
        print(f"{'='*60}\n")
        print("🔍 Procurando pasta de dados do MetaTrader 5...\n")

        pastas = self.encontrar_pastas_mql5()

        if not pastas:
            print("❌ Nenhuma instalacao do MetaTrader 5 encontrada.\n")
            print("Deseja informar o caminho manualmente? (s/n): ", end="")
            resp = input().strip().lower()
            if resp == 's' or resp == 'sim':
                return self._solicitar_caminho_manual()
            else:
                print("\n")
                self._mostrar_instrucoes_manuais()
                return False

        if len(pastas) == 1:
            self.mql5_path = pastas[0]
            print(f"✅ Pasta MQL5 encontrada:\n   {self.mql5_path}\n")
            return True

        # Múltiplas instalações - deixa o usuário escolher
        print(f"📂 {len(pastas)} instalação(ões) encontrada(s):\n")
        for i, pasta in enumerate(pastas, 1):
            # Mostra o ID da instância para ajudar a identificar
            instance_id = pasta.parent.name[:8] if len(pasta.parent.name) > 8 else pasta.parent.name
            print(f"   [{i}] {pasta}")
            print(f"       (ID: {instance_id}...)\n")

        while True:
            try:
                escolha = input(f"Escolha uma opção (1-{len(pastas)}): ").strip()
                idx = int(escolha) - 1
                if 0 <= idx < len(pastas):
                    self.mql5_path = pastas[idx]
                    print(f"\n✅ Usando: {self.mql5_path}\n")
                    return True
                else:
                    print("❌ Opção inválida. Tente novamente.")
            except ValueError:
                print("❌ Digite um número válido.")

    def _solicitar_caminho_manual(self):
        """Solicita o caminho manualmente"""
        print("📝 Por favor, informe o caminho da pasta MQL5 manualmente.")
        print("   (É a pasta que contém Experts, Include, Indicators, etc.)\n")

        if self.sistema == "Windows":
            print("   Exemplo: C:/Users/SeuUsuario/AppData/Roaming/MetaQuotes/Terminal/XXXXX/MQL5")
        elif self.sistema == "Darwin":
            print("   Exemplo: ~/Library/Application Support/.../Terminal/XXXXX/MQL5")
        else:
            print("   Exemplo: ~/.wine/drive_c/users/.../Terminal/XXXXX/MQL5")

        print()
        caminho = input("Caminho do MQL5: ").strip()

        if caminho:
            caminho_path = Path(caminho).expanduser()
            try:
                if caminho_path.exists():
                    # Verifica se é uma pasta MQL5 válida
                    try:
                        experts_exists = (caminho_path / "Experts").exists()
                        include_exists = (caminho_path / "Include").exists()
                        if experts_exists or include_exists:
                            self.mql5_path = caminho_path
                            print(f"\n✅ Usando: {self.mql5_path}\n")
                            return True
                        else:
                            print("\n⚠️  Esta pasta não parece ser uma pasta MQL5 válida.")
                            print("    Procure pela pasta que contém 'Experts' e 'Include'.\n")
                    except PermissionError:
                        # Mesmo sem permissao para verificar subpastas, tenta usar
                        self.mql5_path = caminho_path
                        print(f"\n✅ Usando: {self.mql5_path}\n")
                        return True
                else:
                    print(f"\n❌ Caminho não encontrado: {caminho_path}\n")
            except PermissionError:
                print("\n" + "="*60)
                print("  INSTALACAO MANUAL NECESSARIA")
                print("="*60)
                print("\nVoce nao tem permissao para acessar a pasta MQL5.")
                print("Siga os passos abaixo para instalar manualmente:\n")
                self._mostrar_instrucoes_manuais()
                return False

        return False

    def _mostrar_instrucoes_manuais(self):
        """Mostra instrucoes para instalacao manual"""
        print("PASSO 1: Abra o MetaTrader 5")
        print("         Va em: Arquivo > Abrir Pasta de Dados")
        print("         Isso abrira a pasta MQL5 no Explorer\n")

        print("PASSO 2: Crie as pastas (se nao existirem):")
        print("         MQL5/Experts/MWM/")
        print("         MQL5/Include/MWM/\n")

        print("PASSO 3: Copie os arquivos da pasta 'Scripts/':")
        print("         RSI_Sniper.mq5  ->  MQL5/Experts/MWM/")
        print("         RSIExport.mqh   ->  MQL5/Include/MWM/")
        print("         rsi_panel.py    ->  MQL5/Include/MWM/\n")

        print("PASSO 4: Compile no MetaEditor")
        print("         Abra o MetaEditor (F4 no MT5)")
        print("         Navegue ate: Experts > MWM > RSI_Sniper")
        print("         Pressione F7 para compilar\n")

        print("="*60)

    def criar_diretorios(self):
        """Cria as pastas necessárias"""
        print("📁 Criando estrutura de pastas...\n")

        pastas = [
            self.mql5_path / "Experts/MWM",
            self.mql5_path / "Include/MWM",
        ]

        for pasta in pastas:
            pasta.mkdir(parents=True, exist_ok=True)
            try:
                rel_path = pasta.relative_to(self.mql5_path)
                print(f"   ✓ MQL5/{rel_path}")
            except ValueError:
                print(f"   ✓ {pasta}")

        print()

    def instalar_arquivos(self):
        """Instala os arquivos do pacote automaticamente"""
        print("📦 Instalando arquivos do RSI Sniper...\n")

        # Detecta pasta raiz e pasta Scripts (onde estão os arquivos do robô)
        pasta_instalador = Path(__file__).parent.parent.resolve() / "Scripts"

        # Define mapeamento: arquivo → pasta destino
        mapeamento = {
            'RSI_Sniper.mq5': self.mql5_path / "Experts/MWM",
            'RSIExport.mqh': self.mql5_path / "Include/MWM",
            'rsi_panel.py': self.mql5_path / "Include/MWM",
        }

        arquivos_copiados = 0
        arquivos_faltando = []

        for nome_arquivo, destino in mapeamento.items():
            origem = pasta_instalador / nome_arquivo

            if origem.exists():
                shutil.copy2(origem, destino / nome_arquivo)
                try:
                    rel_destino = destino.relative_to(self.mql5_path)
                    print(f"   ✓ {nome_arquivo} → MQL5/{rel_destino}")
                except ValueError:
                    print(f"   ✓ {nome_arquivo} → {destino}")
                self.arquivos_instalados.append(str(destino / nome_arquivo))
                arquivos_copiados += 1
            else:
                arquivos_faltando.append(nome_arquivo)
                print(f"   ⚠️  {nome_arquivo} não encontrado na pasta do instalador")

        print()

        if arquivos_copiados == 0:
            print("❌ Nenhum arquivo encontrado para instalar!\n")
            print("📋 Certifique-se de que os seguintes arquivos estão na mesma pasta do instalador:")
            print(f"   {pasta_instalador}\n")
            for arquivo in mapeamento.keys():
                print(f"   - {arquivo}")
            print()
            return False

        if arquivos_faltando:
            print(f"⚠️  {len(arquivos_faltando)} arquivo(s) não encontrado(s):")
            for arquivo in arquivos_faltando:
                print(f"   - {arquivo}")
            print()

        print(f"✅ {arquivos_copiados} arquivo(s) instalado(s) com sucesso!\n")
        return True

    def criar_atalho_desktop(self):
        """Cria um atalho do painel na Área de Trabalho"""
        print("🖥️  Criando executável na Área de Trabalho...\n")

        home = Path.home()
        desktop = home / "Desktop"

        # Tenta outras localizações comuns para Desktop
        if not desktop.exists():
            desktop = home / "Área de Trabalho"
        if not desktop.exists():
            desktop = home / "Escritorio"
        if not desktop.exists():
            print("   ⚠️  Área de Trabalho não encontrada. Atalho não criado.\n")
            return None

        painel_path = self.mql5_path / "Include/MWM/rsi_panel.py"
        atalho = None

        if self.sistema == "Darwin":  # macOS
            # Cria um .command com busca inteligente
            atalho = desktop / "RSI_Sniper_Painel.command"
            script_content = '''#!/bin/bash
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
'''
            with open(atalho, 'w') as f:
                f.write(script_content)
            os.chmod(atalho, 0o755)
            print(f"   ✓ Criado: {atalho}\n")

        elif self.sistema == "Windows":
            # Cria um .bat com busca inteligente
            atalho = desktop / "RSI_Sniper_Painel.bat"
            script_content = '''@echo off
chcp 65001 >nul
title RSI Sniper - Painel de Controle

echo ============================================================
echo   RSI SNIPER - Localizando Painel...
echo ============================================================
echo.

REM Procura na pasta de DADOS do MT5 (AppData)
set "FOUND="
for /d %%i in ("%APPDATA%\\MetaQuotes\\Terminal\\*") do (
    if exist "%%i\\MQL5\\Include\\MWM\\rsi_panel.py" (
        set "PANEL_DIR=%%i\\MQL5\\Include\\MWM"
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

REM Fallback: pasta do programa
if exist "C:\\Program Files\\MetaTrader 5\\MQL5\\Include\\MWM\\rsi_panel.py" (
    echo Painel encontrado em:
    echo C:\\Program Files\\MetaTrader 5\\MQL5\\Include\\MWM
    echo.
    echo Iniciando painel...
    cd /d "C:\\Program Files\\MetaTrader 5\\MQL5\\Include\\MWM"
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
echo   1. Execute o instalador primeiro
echo   2. Verifique se o MetaTrader 5 esta instalado
echo   3. Verifique se Python esta instalado
echo.
pause

:end
'''
            with open(atalho, 'w') as f:
                f.write(script_content)
            print(f"   ✓ Criado: {atalho}\n")

        else:  # Linux
            # Cria um .sh com busca inteligente
            atalho = desktop / "RSI_Sniper_Painel.sh"
            script_content = '''#!/bin/bash
# RSI Sniper - Painel de Controle

echo "============================================================"
echo "  RSI SNIPER - Localizando Painel..."
echo "============================================================"
echo ""

# Busca na pasta de dados do MT5 (Wine)
WINE_BASE="$HOME/.wine/drive_c/users"
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
'''
            with open(atalho, 'w') as f:
                f.write(script_content)
            os.chmod(atalho, 0o755)
            print(f"   ✓ Criado: {atalho}\n")

        return atalho

    def exibir_proximos_passos(self, atalho_desktop=None):
        """Mostra instruções de próximos passos"""
        print(f"\n{'='*60}")
        print("  ✅ INSTALAÇÃO CONCLUÍDA!")
        print(f"{'='*60}\n")

        # Destaque para o executável criado
        if atalho_desktop:
            print(f"{'='*60}")
            print("  🖥️  EXECUTÁVEL CRIADO NA ÁREA DE TRABALHO:")
            print(f"{'='*60}")
            print(f"\n   → {atalho_desktop.name}\n")
            print("   Dê duplo clique para abrir o Painel de Controle!")
            print(f"\n{'='*60}\n")

        print("📋 PRÓXIMOS PASSOS:\n")

        print("1️⃣  Abra o MetaEditor do MetaTrader 5")
        print("   (Pressione F4 dentro do MT5)\n")

        print("2️⃣  Compile o Expert Advisor:")
        print("   • Navegue até: Experts → MWM → RSI_Sniper.mq5")
        print("   • Pressione F7 para compilar\n")

        print("3️⃣  Execute o painel de controle:")
        if atalho_desktop:
            print(f"   • Dê duplo clique em: {atalho_desktop.name}")
        else:
            print("   • Use o atalho na Área de Trabalho")
        print("   • (Localizado na sua Área de Trabalho)\n")

        print("4️⃣  No MetaTrader 5:")
        print("   • Navegador → Expert Advisors → MWM → RSI_Sniper")
        print("   • Arraste para o gráfico do ativo desejado")
        print("   • Configure os parâmetros e clique OK\n")

        print(f"{'='*60}")
        print("  📁 ARQUIVOS INSTALADOS:")
        print(f"{'='*60}\n")

        for arquivo in self.arquivos_instalados:
            print(f"   ✓ {arquivo}")

        if atalho_desktop:
            print(f"   ✓ {atalho_desktop} (Área de Trabalho)")

        print(f"\n{'='*60}\n")

    def executar(self):
        """Executa o instalador"""
        try:
            if not self.detectar_mt5():
                return False

            self.criar_diretorios()

            if not self.instalar_arquivos():
                print("⚠️  Instalação incompleta. Verifique os arquivos faltantes.\n")
                return False

            atalho = self.criar_atalho_desktop()
            self.exibir_proximos_passos(atalho)
            return True

        except KeyboardInterrupt:
            print("\n\n⚠️  Instalação cancelada pelo usuário.\n")
            return False
        except Exception as e:
            print(f"\n\n❌ Erro durante instalação: {e}\n")
            import traceback
            traceback.print_exc()
            return False

def main():
    """Função principal"""
    instalador = RSISniperInstaller()
    sucesso = instalador.executar()

    # Pausa para o usuário ler (útil quando executado via duplo-clique)
    input("\nPressione ENTER para fechar...")
    sys.exit(0 if sucesso else 1)

if __name__ == "__main__":
    main()
