╔══════════════════════════════════════════════════════════════╗
║             RSI SNIPER PRO - Guia de Instalação              ║
╠══════════════════════════════════════════════════════════════╣
║  Robô de trading baseado em RSI com painel de controle       ║
║  Compatível: Windows, macOS (Wine) e Linux (Wine)            ║
╚══════════════════════════════════════════════════════════════╝

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  CONTEUDO DO PACOTE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Scripts/ (Arquivos do Robo)
     - RSI_Sniper.mq5    - Expert Advisor principal
     - RSIExport.mqh     - Biblioteca de comunicação
     - rsi_panel.py      - Painel de controle Python

  Instalacao/ (Scripts por Sistema Operacional)
     - Windows/
        - Instalar_RSI_Sniper.bat - Instala os arquivos
        - Abrir_Painel.bat        - Abre o painel
        - LEIA-ME.txt             - Instrucoes

     - macOS/
        - Instalar_RSI_Sniper.app - Instala os arquivos
        - Abrir_Painel.app        - Abre o painel
        - LEIA-ME.txt             - Instrucoes

     - Linux/
        - instalar.sh             - Instala os arquivos
        - painel.sh               - Abre o painel
        - LEIA-ME.txt             - Instrucoes

     - install_rsi_sniper.py      - Instalador via terminal

  Documentacao/
     - MANUAL_FUNCIONAMENTO.txt   - Como usar o sistema
     - PRE_REQUISITOS.txt         - Requisitos de instalacao
     - GUIA_IMPLANTACAO.txt       - Passo a passo

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  INSTALACAO
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  macOS:
  ─────────
  1. Abra a pasta "Instalacao/macOS"
  2. De duplo clique em "Instalar_RSI_Sniper.app"
  3. Siga as instrucoes no Terminal
  4. Compile no MetaEditor (F7)

  Windows:
  ───────────
  1. Abra a pasta "Instalacao/Windows"
  2. De duplo clique em "Instalar_RSI_Sniper.bat"
  3. Siga as instrucoes
  4. Compile no MetaEditor (F7)

  Linux:
  ─────────
  1. Abra a pasta "Instalacao/Linux"
  2. Execute: ./instalar.sh (ou duplo clique)
  3. Siga as instrucoes
  4. Compile no MetaEditor (F7)

  Via Terminal (qualquer SO):
  ──────────────────────────────
  cd Instalacao
  python3 install_rsi_sniper.py

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  USANDO O PAINEL DE CONTROLE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  macOS:     Abra Instalacao/macOS/Abrir_Painel.app
  Windows:   Abra Instalacao/Windows/Abrir_Painel.bat
  Linux:     Execute Instalacao/Linux/painel.sh

  Apos a instalacao, use o atalho criado na Area de Trabalho.

  O painel instala dependencias automaticamente na primeira execucao.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  CONFIGURACAO NO METATRADER 5
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  1. Abra o MetaTrader 5
  2. Va em: Ferramentas > Opcoes > Expert Advisors
  3. Marque:
     [x] Permitir trading algoritmico
     [x] Permitir importacao de DLL
  4. No Navegador, expanda: Expert Advisors > MWM
  5. Arraste "RSI_Sniper" para o grafico desejado
  6. Configure os parametros e clique OK

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ONDE OS ARQUIVOS SAO INSTALADOS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  MQL5/
  |── Experts/
  |   └── MWM/
  |       └── RSI_Sniper.mq5      <- Expert Advisor
  └── Include/
      └── MWM/
          |── RSIExport.mqh       <- Biblioteca
          └── rsi_panel.py        <- Painel Python

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  CARACTERISTICAS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  - Painel de controle moderno com tema escuro
  - Sistema de trailing stop configuravel
  - Filtros de confirmacao (Agressao + Volume Profile)
  - Logs em tempo real
  - Configuracao dinamica sem recompilar
  - Funciona em LIVE e BACKTEST
  - Instalacao automatica multiplataforma
  - Dependencias instaladas automaticamente

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  SUPORTE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Em caso de duvidas ou problemas, verifique:
  - Python 3.8+ esta instalado (python3 --version)
  - MetaTrader 5 esta instalado corretamente
  - O EA foi compilado sem erros no MetaEditor
  - Leia o arquivo LEIA-ME.txt na pasta do seu sistema

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Versao: 1.0 | Projeto MWM | Marco 2026
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
