"""
+------------------------------------------------------------------+
|                    RSI SNIPER PRO - Painel                       |
|                                                                  |
| Painel de controle para o robô RSI Sniper (MetaTrader 5)         |
| - Monitora posições, lucro, RSI e filtros em tempo real          |
| - Envia comandos: pausar, fechar posições, salvar configs        |
| - Comunicação via arquivos JSON na pasta Common/Files            |
|                                                                  |
| Compatível com: Windows, macOS (Wine) e Linux (Wine)             |
+------------------------------------------------------------------+
"""

# ═══════════════════════════════════════════════════════════════
# VERIFICAÇÃO E INSTALAÇÃO AUTOMÁTICA DE DEPENDÊNCIAS
# ═══════════════════════════════════════════════════════════════
import subprocess
import sys

def instalar_dependencias():
    """Verifica e instala dependências necessárias automaticamente."""
    dependencias = {
        'customtkinter': 'customtkinter',
    }

    for modulo, pacote in dependencias.items():
        try:
            __import__(modulo)
        except ImportError:
            print(f"Instalando {pacote}...")
            try:
                subprocess.check_call([
                    sys.executable, '-m', 'pip', 'install', pacote, '--quiet'
                ])
                print(f"✓ {pacote} instalado com sucesso!")
            except subprocess.CalledProcessError:
                print(f"✗ Erro ao instalar {pacote}.")
                print(f"  Execute manualmente: pip install {pacote}")
                input("Pressione ENTER para sair...")
                sys.exit(1)

# Executa verificação antes de importar
instalar_dependencias()

import customtkinter as ctk
from tkinter import messagebox
import json
import os
from datetime import datetime
import time
from pathlib import Path
import platform

# Tema escuro é padrão para trading (menos cansaço visual)
ctk.set_appearance_mode("dark")
ctk.set_default_color_theme("blue")


class RSIPanelModern(ctk.CTk):
    """
    Painel principal do RSI Sniper.

    O painel lê dados do EA via arquivo JSON (rsi_data_LIVE.json ou rsi_data_BACKTEST.json)
    e envia comandos via arquivo TXT (rsi_commands_*.txt).

    O EA exporta os dados a cada tick, e o painel atualiza a cada 250ms.
    """
    def __init__(self):
        super().__init__()

        self.sistema = platform.system()

        # ═══════════════════════════════════════════════════════════════
        # PALETA DE CORES - Estilo Trading Dashboard
        # Mantém consistência visual em todo o painel
        # ═══════════════════════════════════════════════════════════════
        self.colors = {
            # Fundos (escuros para reduzir cansaço visual em longas sessões)
            'bg_primary': '#0a0e14',      # Fundo principal (preto profundo)
            'bg_secondary': '#111820',    # Card background
            'bg_tertiary': '#1a2332',     # Input/elevated
            'bg_hover': '#232d3f',         # Hover states

            # Accent Colors
            'accent_cyan': '#00d4ff',      # Primary accent
            'accent_green': '#00ff88',     # Profit/Success
            'accent_red': '#ff3366',       # Loss/Error
            'accent_yellow': '#ffcc00',    # Warning
            'accent_purple': '#a855f7',    # Secondary accent
            'accent_blue': '#3b82f6',      # Info

            # Text
            'text_primary': '#ffffff',
            'text_secondary': '#94a3b8',
            'text_muted': '#64748b',

            # Borders & Effects
            'border': '#1e293b',
            'border_glow': '#00d4ff',
            'gradient_start': '#0a0e14',
            'gradient_end': '#111820',
        }

        # Window setup - tamanho compacto
        self.title(f"RSI SNIPER PRO")
        self.geometry("1150x750")
        self.configure(fg_color=self.colors['bg_primary'])
        self.minsize(1000, 650)

        # Detecta caminho do MetaTrader
        self.common_path = self._detectar_caminho()
        self.modo_atual = self._detectar_modo()
        self._atualizar_arquivos()

        print("=" * 60)
        print(f"  RSI SNIPER PRO - Trading Dashboard ({self.sistema})")
        print("=" * 60)
        print(f"  Modo: {self.modo_atual}")
        print(f"  Dados: {self.data_file}")
        print("=" * 60)

        os.makedirs(self.common_path, exist_ok=True)

        # Variáveis de controle
        self.trailing_var = ctk.BooleanVar(value=True)
        self.agressao_var = ctk.BooleanVar(value=False)
        self.volume_profile_var = ctk.BooleanVar(value=False)
        self.ultimo_timestamp = None
        self.conexao_ativa = False
        self.checkboxes_sincronizados = False
        self.info_labels = {}
        self.entries = {}

        # Controle de timeout de conexão (15 segundos sem dados = desconectado)
        # Aumentado para 15s porque no backtest pode haver gaps sem ticks
        self.ultima_atualizacao_real = None  # Momento real que recebeu dados
        self.timeout_conexao = 15  # Segundos para considerar desconectado

        self._criar_interface()
        self._atualizar_dados()

    def _detectar_modo(self):
        """
        Detecta automaticamente se está rodando BACKTEST ou LIVE.
        Usa o arquivo modificado mais recentemente como referência.
        Isso permite alternar entre modos sem reiniciar o painel.
        """
        backtest_file = os.path.join(self.common_path, "rsi_data_BACKTEST.json")
        live_file = os.path.join(self.common_path, "rsi_data_LIVE.json")
        legacy_file = os.path.join(self.common_path, "rsi_data.json")

        files = {}
        for nome, path in [("BACKTEST", backtest_file), ("LIVE", live_file), ("LEGACY", legacy_file)]:
            if os.path.exists(path):
                files[nome] = os.path.getmtime(path)

        if not files:
            return "BACKTEST"
        return max(files, key=files.get)

    def _atualizar_arquivos(self):
        if self.modo_atual == "LEGACY":
            self.data_file = os.path.join(self.common_path, "rsi_data.json")
            self.command_file = os.path.join(self.common_path, "rsi_commands.txt")
        else:
            sufixo = f"_{self.modo_atual}"
            self.data_file = os.path.join(self.common_path, f"rsi_data{sufixo}.json")
            self.command_file = os.path.join(self.common_path, f"rsi_commands{sufixo}.txt")

    def _detectar_caminho(self):
        """
        Encontra a pasta Common/Files do MetaTrader automaticamente.

        - macOS: usa Wine prefix em ~/Library/Application Support/...
        - Windows: usa %APPDATA%/MetaQuotes/...
        - Linux: usa ~/.wine/drive_c/...

        Tenta múltiplos caminhos possíveis e retorna o primeiro que existir.
        """
        sistema = platform.system()
        home = Path.home()
        usuario_sistema = os.getenv("USER", "user")

        if sistema == "Darwin":
            wine_prefix = home / "Library/Application Support/net.metaquotes.wine.metatrader5/drive_c"
            caminhos_possiveis = []

            users_dir = wine_prefix / "users"
            if users_dir.exists():
                for user_folder in users_dir.iterdir():
                    if user_folder.is_dir():
                        common_path = user_folder / "AppData/Roaming/MetaQuotes/Terminal/Common/Files"
                        if common_path.exists():
                            caminhos_possiveis.insert(0, common_path)

            caminhos_possiveis.extend([
                wine_prefix / "users" / usuario_sistema / "AppData/Roaming/MetaQuotes/Terminal/Common/Files",
                wine_prefix / "users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files",
            ])
        elif sistema == "Windows":
            caminhos_possiveis = [
                Path(os.environ.get("APPDATA", "")) / "MetaQuotes/Terminal/Common/Files",
            ]
        else:
            caminhos_possiveis = [
                home / ".wine/drive_c/users" / usuario_sistema / "AppData/Roaming/MetaQuotes/Terminal/Common/Files",
            ]

        for caminho in caminhos_possiveis:
            if caminho.exists():
                return str(caminho)

        return str(caminhos_possiveis[0] if caminhos_possiveis else home / "MetaQuotes/Terminal/Common/Files")

    # ═══════════════════════════════════════════════════════════════
    # INTERFACE - Modern Trading Dashboard
    # ═══════════════════════════════════════════════════════════════

    def _criar_interface(self):
        # Header
        self._criar_header()

        # Main container
        main_container = ctk.CTkFrame(self, fg_color="transparent")
        main_container.pack(fill="both", expand=True, padx=15, pady=(0, 10))

        # Grid layout - 3 colunas
        main_container.grid_columnconfigure(0, weight=1, uniform="cols")
        main_container.grid_columnconfigure(1, weight=1, uniform="cols")
        main_container.grid_columnconfigure(2, weight=1, uniform="cols")
        main_container.grid_rowconfigure(0, weight=1)

        # Colunas
        self._criar_coluna_monitor(main_container)
        self._criar_coluna_monitoramento(main_container)
        self._criar_coluna_configuracoes(main_container)


    def _criar_header(self):
        header = ctk.CTkFrame(self, fg_color="transparent", height=60)
        header.pack(fill="x", padx=20, pady=(15, 8))
        header.pack_propagate(False)

        # Logo e título
        title_frame = ctk.CTkFrame(header, fg_color="transparent")
        title_frame.pack(side="left", fill="y")

        # Logo icon (simulated with Unicode)
        logo_label = ctk.CTkLabel(
            title_frame,
            text="🎯",
            font=ctk.CTkFont(size=36, weight="bold"),
            text_color=self.colors['accent_cyan']
        )
        logo_label.pack(side="left", padx=(0, 12))

        title_text_frame = ctk.CTkFrame(title_frame, fg_color="transparent")
        title_text_frame.pack(side="left")

        ctk.CTkLabel(
            title_text_frame,
            text="RSI SNIPER",
            font=ctk.CTkFont(family="Helvetica", size=28, weight="bold"),
            text_color=self.colors['text_primary']
        ).pack(anchor="w")

        ctk.CTkLabel(
            title_text_frame,
            text="Professional Trading Dashboard",
            font=ctk.CTkFont(size=12),
            text_color=self.colors['text_muted']
        ).pack(anchor="w")

        # Status de conexão (direita)
        status_frame = ctk.CTkFrame(header, fg_color="transparent")
        status_frame.pack(side="right", fill="y")

        self.status_indicator = ctk.CTkFrame(
            status_frame,
            width=12, height=12,
            corner_radius=6,
            fg_color=self.colors['accent_yellow']
        )
        self.status_indicator.pack(side="right", pady=20)

        self.lbl_conexao = ctk.CTkLabel(
            status_frame,
            text="Conectando...",
            font=ctk.CTkFont(size=13, weight="bold"),
            text_color=self.colors['accent_yellow']
        )
        self.lbl_conexao.pack(side="right", padx=(0, 10), pady=20)

        # Modo badge
        self.modo_badge = ctk.CTkLabel(
            status_frame,
            text=f"● {self.modo_atual}",
            font=ctk.CTkFont(size=11),
            text_color=self.colors['accent_purple'],
            fg_color=self.colors['bg_tertiary'],
            corner_radius=12,
            padx=12, pady=4
        )
        self.modo_badge.pack(side="right", padx=(0, 15), pady=18)

    def _criar_card(self, parent, titulo, row=0, col=0, icon=""):
        """Cria um card moderno compacto"""
        card = ctk.CTkFrame(
            parent,
            fg_color=self.colors['bg_secondary'],
            corner_radius=12,
            border_width=1,
            border_color=self.colors['border']
        )
        card.grid(row=row, column=col, sticky="nsew", padx=6, pady=6)

        # Header do card
        header_frame = ctk.CTkFrame(card, fg_color="transparent")
        header_frame.pack(fill="x", padx=15, pady=(12, 0))

        title_with_icon = f"{icon} {titulo}" if icon else titulo
        ctk.CTkLabel(
            header_frame,
            text=title_with_icon,
            font=ctk.CTkFont(size=14, weight="bold"),
            text_color=self.colors['accent_cyan']
        ).pack(side="left")

        # Separator line
        sep_frame = ctk.CTkFrame(card, fg_color="transparent", height=2)
        sep_frame.pack(fill="x", padx=15, pady=(10, 0))

        sep = ctk.CTkFrame(sep_frame, height=1, fg_color=self.colors['border'])
        sep.pack(fill="x")

        # Content area
        content = ctk.CTkFrame(card, fg_color="transparent")
        content.pack(fill="both", expand=True, padx=15, pady=12)

        return content, card

    def _criar_info_row(self, parent, label, key, is_value_large=False):
        """Cria uma linha de informação estilizada"""
        row = ctk.CTkFrame(parent, fg_color="transparent")
        row.pack(fill="x", pady=8)

        ctk.CTkLabel(
            row,
            text=label,
            font=ctk.CTkFont(size=15),
            text_color=self.colors['text_secondary'],
            anchor="w",
            width=120
        ).pack(side="left")

        font_size = 18 if is_value_large else 16
        lbl = ctk.CTkLabel(
            row,
            text="--",
            font=ctk.CTkFont(size=font_size, weight="bold"),
            text_color=self.colors['accent_cyan'],
            anchor="e"
        )
        lbl.pack(side="right")
        self.info_labels[key] = lbl

        return row

    def _criar_coluna_monitor(self, parent):
        col_frame = ctk.CTkFrame(parent, fg_color="transparent")
        col_frame.grid(row=0, column=0, sticky="nsew")
        col_frame.grid_rowconfigure(0, weight=1)
        col_frame.grid_rowconfigure(1, weight=0)
        col_frame.grid_columnconfigure(0, weight=1)

        # Card Monitor
        content, card = self._criar_card(col_frame, "MONITOR", 0, 0, "📊")

        # Status badge grande
        status_container = ctk.CTkFrame(content, fg_color="transparent")
        status_container.pack(fill="x", pady=(0, 15))

        self.status_badge = ctk.CTkLabel(
            status_container,
            text="● DESCONECTADO",
            font=ctk.CTkFont(size=13, weight="bold"),
            text_color=self.colors['accent_yellow'],
            fg_color=self.colors['bg_tertiary'],
            corner_radius=8,
            padx=16, pady=8
        )
        self.status_badge.pack(side="left")

        # Informações principais
        self._criar_info_row(content, "Ativo:", "ativo")
        self._criar_info_row(content, "Posições:", "posicoes")
        self._criar_info_row(content, "RSI:", "rsi")

        # Separator
        ctk.CTkFrame(content, height=1, fg_color=self.colors['border']).pack(fill="x", pady=10)

        # Valores financeiros (destaque)
        finance_frame = ctk.CTkFrame(content, fg_color=self.colors['bg_tertiary'], corner_radius=10)
        finance_frame.pack(fill="x", pady=3)

        finance_inner = ctk.CTkFrame(finance_frame, fg_color="transparent")
        finance_inner.pack(fill="x", padx=12, pady=10)

        # Lucro do Dia - Grande
        ctk.CTkLabel(
            finance_inner,
            text="LUCRO DO DIA",
            font=ctk.CTkFont(size=10),
            text_color=self.colors['text_muted']
        ).pack(anchor="w")

        self.info_labels['lucro_dia'] = ctk.CTkLabel(
            finance_inner,
            text="R$ 0.00",
            font=ctk.CTkFont(size=28, weight="bold"),
            text_color=self.colors['accent_green']
        )
        self.info_labels['lucro_dia'].pack(anchor="w", pady=(2, 10))

        # Saldo e Lucro Aberto
        sub_frame = ctk.CTkFrame(finance_inner, fg_color="transparent")
        sub_frame.pack(fill="x")

        # Saldo
        saldo_col = ctk.CTkFrame(sub_frame, fg_color="transparent")
        saldo_col.pack(side="left", expand=True, fill="x")

        ctk.CTkLabel(
            saldo_col,
            text="Saldo",
            font=ctk.CTkFont(size=10),
            text_color=self.colors['text_muted']
        ).pack(anchor="w")

        self.info_labels['saldo'] = ctk.CTkLabel(
            saldo_col,
            text="R$ 0.00",
            font=ctk.CTkFont(size=14, weight="bold"),
            text_color=self.colors['text_primary']
        )
        self.info_labels['saldo'].pack(anchor="w")

        # Lucro Aberto
        lucro_col = ctk.CTkFrame(sub_frame, fg_color="transparent")
        lucro_col.pack(side="right", expand=True, fill="x")

        ctk.CTkLabel(
            lucro_col,
            text="Lucro Aberto",
            font=ctk.CTkFont(size=10),
            text_color=self.colors['text_muted']
        ).pack(anchor="e")

        self.info_labels['lucro_aberto'] = ctk.CTkLabel(
            lucro_col,
            text="R$ 0.00",
            font=ctk.CTkFont(size=14, weight="bold"),
            text_color=self.colors['accent_green']
        )
        self.info_labels['lucro_aberto'].pack(anchor="e")

        # Lucro Total (apenas em BACKTEST) - acumula todo o backtest
        self.lucro_total_frame = ctk.CTkFrame(finance_frame, fg_color="transparent")
        self.lucro_total_frame.pack(fill="x", padx=12, pady=(5, 10))

        ctk.CTkLabel(
            self.lucro_total_frame,
            text="LUCRO TOTAL (BACKTEST)",
            font=ctk.CTkFont(size=10),
            text_color=self.colors['accent_purple']
        ).pack(side="left")

        self.info_labels['lucro_total'] = ctk.CTkLabel(
            self.lucro_total_frame,
            text="R$ 0.00",
            font=ctk.CTkFont(size=16, weight="bold"),
            text_color=self.colors['accent_cyan']
        )
        self.info_labels['lucro_total'].pack(side="right")

        # Oculta frame de lucro total se não for BACKTEST
        if self.modo_atual != "BACKTEST":
            self.lucro_total_frame.pack_forget()

        # Botões de ação
        btn_card = ctk.CTkFrame(col_frame, fg_color=self.colors['bg_secondary'], corner_radius=12)
        btn_card.grid(row=1, column=0, sticky="ew", padx=6, pady=6)

        btn_frame = ctk.CTkFrame(btn_card, fg_color="transparent")
        btn_frame.pack(pady=12, padx=15, fill="x")

        ctk.CTkButton(
            btn_frame,
            text="⏸ PAUSAR",
            font=ctk.CTkFont(size=13, weight="bold"),
            fg_color=self.colors['accent_yellow'],
            hover_color="#cc9900",
            text_color="#000000",
            corner_radius=8,
            height=38,
            command=self._pausar_retomar
        ).pack(side="left", expand=True, fill="x", padx=(0, 6))

        ctk.CTkButton(
            btn_frame,
            text="✕ FECHAR TUDO",
            font=ctk.CTkFont(size=13, weight="bold"),
            fg_color=self.colors['accent_red'],
            hover_color="#cc2952",
            text_color="#ffffff",
            corner_radius=8,
            height=38,
            command=self._fechar_tudo
        ).pack(side="right", expand=True, fill="x", padx=(6, 0))

        # Botão PARAR EA - largura total (abaixo dos outros)
        ctk.CTkButton(
            btn_card,
            text="⏹ PARAR EA",
            font=ctk.CTkFont(size=14, weight="bold"),
            fg_color="#7f1d1d",
            hover_color="#991b1b",
            text_color="#ffffff",
            corner_radius=8,
            height=42,
            command=self._parar_ea
        ).pack(fill="x", padx=15, pady=(0, 12))

    def _criar_coluna_monitoramento(self, parent):
        col_frame = ctk.CTkFrame(parent, fg_color="transparent")
        col_frame.grid(row=0, column=1, sticky="nsew")
        col_frame.grid_rowconfigure(0, weight=1)
        col_frame.grid_columnconfigure(0, weight=1)

        content, card = self._criar_card(col_frame, "MONITORAMENTO", 0, 0, "📈")

        # ═══ AGRESSÃO ═══
        agressao_header = ctk.CTkFrame(content, fg_color="transparent")
        agressao_header.pack(fill="x", pady=(0, 10))

        ctk.CTkLabel(
            agressao_header,
            text="⚡ AGRESSÃO",
            font=ctk.CTkFont(size=12, weight="bold"),
            text_color=self.colors['accent_green']
        ).pack(side="left")

        self.lbl_agressao_status = ctk.CTkLabel(
            agressao_header,
            text="DESATIVADO",
            font=ctk.CTkFont(size=10, weight="bold"),
            text_color=self.colors['accent_red']
        )
        self.lbl_agressao_status.pack(side="right")

        # Campos Agressão
        for label, key in [("Compra:", "agressao_compra"), ("Venda:", "agressao_venda"),
                           ("Volume:", "agressao_vol"), ("Direção:", "agressao_direcao")]:
            row = ctk.CTkFrame(content, fg_color="transparent")
            row.pack(fill="x", pady=5)

            ctk.CTkLabel(row, text=label, font=ctk.CTkFont(size=14),
                        text_color=self.colors['text_muted'], width=90, anchor="w").pack(side="left")

            lbl = ctk.CTkLabel(row, text="--", font=ctk.CTkFont(size=14, weight="bold"),
                              text_color=self.colors['text_secondary'], anchor="e")
            lbl.pack(side="right")
            self.info_labels[key] = lbl

        # Separator
        ctk.CTkFrame(content, height=1, fg_color=self.colors['border']).pack(fill="x", pady=10)

        # ═══ VOLUME PROFILE ═══
        vp_header = ctk.CTkFrame(content, fg_color="transparent")
        vp_header.pack(fill="x", pady=(0, 10))

        ctk.CTkLabel(
            vp_header,
            text="📊 VOLUME PROFILE",
            font=ctk.CTkFont(size=12, weight="bold"),
            text_color=self.colors['accent_purple']
        ).pack(side="left")

        self.lbl_vp_status = ctk.CTkLabel(
            vp_header,
            text="DESATIVADO",
            font=ctk.CTkFont(size=10, weight="bold"),
            text_color=self.colors['accent_red']
        )
        self.lbl_vp_status.pack(side="right")

        # Campos Volume Profile
        for label, key in [("POC:", "vp_poc"), ("VAH:", "vp_vah"),
                           ("VAL:", "vp_val"), ("Zona:", "vp_zona")]:
            row = ctk.CTkFrame(content, fg_color="transparent")
            row.pack(fill="x", pady=5)

            ctk.CTkLabel(row, text=label, font=ctk.CTkFont(size=14),
                        text_color=self.colors['text_muted'], width=90, anchor="w").pack(side="left")

            lbl = ctk.CTkLabel(row, text="--", font=ctk.CTkFont(size=14, weight="bold"),
                              text_color=self.colors['text_secondary'], anchor="e")
            lbl.pack(side="right")
            self.info_labels[key] = lbl

        # Separator
        ctk.CTkFrame(content, height=1, fg_color=self.colors['border']).pack(fill="x", pady=10)

        # ═══ STATUS DO SINAL ═══
        ctk.CTkLabel(
            content,
            text="STATUS",
            font=ctk.CTkFont(size=10),
            text_color=self.colors['text_muted']
        ).pack(anchor="w")

        self.lbl_sinal_status = ctk.CTkLabel(
            content,
            text="Aguardando sinal...",
            font=ctk.CTkFont(size=14, weight="bold"),
            text_color=self.colors['accent_yellow'],
            wraplength=280
        )
        self.lbl_sinal_status.pack(anchor="w", pady=(5, 0))

    def _criar_coluna_configuracoes(self, parent):
        col_frame = ctk.CTkFrame(parent, fg_color="transparent")
        col_frame.grid(row=0, column=2, sticky="nsew")
        col_frame.grid_rowconfigure(0, weight=1)
        col_frame.grid_columnconfigure(0, weight=1)

        content, card = self._criar_card(col_frame, "CONFIGURAÇÕES", 0, 0, "⚙️")

        # Campos de entrada
        for label, key, default in [("Lote:", "lote", "1.0"),
                                     ("Stop Loss:", "sl", "200"),
                                     ("Take Profit:", "tp", "350")]:
            row = ctk.CTkFrame(content, fg_color="transparent")
            row.pack(fill="x", pady=6)

            ctk.CTkLabel(row, text=label, font=ctk.CTkFont(size=12),
                        text_color=self.colors['text_primary'], width=100, anchor="w").pack(side="left")

            entry = ctk.CTkEntry(
                row,
                font=ctk.CTkFont(size=12),
                fg_color=self.colors['bg_tertiary'],
                border_color=self.colors['border'],
                text_color=self.colors['text_primary'],
                corner_radius=8,
                height=36,
                width=120
            )
            entry.pack(side="right")
            entry.insert(0, default)
            self.entries[key] = entry

        # Trailing Stop
        trailing_frame = ctk.CTkFrame(content, fg_color="transparent")
        trailing_frame.pack(fill="x", pady=(15, 8))

        self.chk_trailing = ctk.CTkCheckBox(
            trailing_frame,
            text="Usar Trailing Stop",
            font=ctk.CTkFont(size=12),
            text_color=self.colors['text_primary'],
            fg_color=self.colors['accent_cyan'],
            hover_color=self.colors['accent_blue'],
            variable=self.trailing_var
        )
        self.chk_trailing.pack(anchor="w")

        trailing_pts_frame = ctk.CTkFrame(content, fg_color="transparent")
        trailing_pts_frame.pack(fill="x", pady=6)

        ctk.CTkLabel(trailing_pts_frame, text="Trailing:", font=ctk.CTkFont(size=12),
                    text_color=self.colors['text_primary'], width=100, anchor="w").pack(side="left")

        self.entry_trailing = ctk.CTkEntry(
            trailing_pts_frame,
            font=ctk.CTkFont(size=12),
            fg_color=self.colors['bg_tertiary'],
            border_color=self.colors['border'],
            text_color=self.colors['text_primary'],
            corner_radius=8,
            height=36,
            width=120
        )
        self.entry_trailing.pack(side="right")
        self.entry_trailing.insert(0, "150")

        # Separator
        ctk.CTkFrame(content, height=1, fg_color=self.colors['border']).pack(fill="x", pady=10)

        # Filtros de confirmação
        ctk.CTkLabel(
            content,
            text="FILTROS DE CONFIRMAÇÃO",
            font=ctk.CTkFont(size=11, weight="bold"),
            text_color=self.colors['accent_purple']
        ).pack(anchor="w", pady=(0, 10))

        self.chk_agressao = ctk.CTkCheckBox(
            content,
            text="Usar Agressão (Fluxo)",
            font=ctk.CTkFont(size=12),
            text_color=self.colors['text_primary'],
            fg_color=self.colors['accent_green'],
            hover_color="#00cc77",
            variable=self.agressao_var
        )
        self.chk_agressao.pack(anchor="w", pady=5)

        self.chk_volume_profile = ctk.CTkCheckBox(
            content,
            text="Usar Volume Profile",
            font=ctk.CTkFont(size=12),
            text_color=self.colors['text_primary'],
            fg_color=self.colors['accent_purple'],
            hover_color="#9333ea",
            variable=self.volume_profile_var
        )
        self.chk_volume_profile.pack(anchor="w", pady=5)

        # Botões
        btn_frame = ctk.CTkFrame(content, fg_color="transparent")
        btn_frame.pack(fill="x", pady=(12, 6))

        ctk.CTkButton(
            btn_frame,
            text="💾 SALVAR",
            font=ctk.CTkFont(size=12, weight="bold"),
            fg_color=self.colors['accent_green'],
            hover_color="#00cc77",
            text_color="#000000",
            corner_radius=8,
            height=36,
            command=self._salvar_config
        ).pack(side="left", expand=True, fill="x", padx=(0, 4))

        ctk.CTkButton(
            btn_frame,
            text="↺ RESETAR",
            font=ctk.CTkFont(size=12, weight="bold"),
            fg_color=self.colors['text_muted'],
            hover_color="#4b5563",
            text_color="#ffffff",
            corner_radius=8,
            height=36,
            command=self._resetar_config
        ).pack(side="right", expand=True, fill="x", padx=(4, 0))

        # Botões Diagnóstico e Ajuda
        btn_frame2 = ctk.CTkFrame(content, fg_color="transparent")
        btn_frame2.pack(fill="x", pady=(4, 6))

        ctk.CTkButton(
            btn_frame2,
            text="🔍 DIAGNÓSTICO",
            font=ctk.CTkFont(size=12, weight="bold"),
            fg_color=self.colors['accent_blue'],
            hover_color="#2563eb",
            corner_radius=8,
            height=36,
            command=self._diagnostico
        ).pack(side="left", expand=True, fill="x", padx=(0, 4))

        ctk.CTkButton(
            btn_frame2,
            text="❓ AJUDA",
            font=ctk.CTkFont(size=12, weight="bold"),
            fg_color=self.colors['accent_purple'],
            hover_color="#7c3aed",
            corner_radius=8,
            height=36,
            command=self._ajuda
        ).pack(side="right", expand=True, fill="x", padx=(4, 0))

        # Status label
        self.lbl_status_config = ctk.CTkLabel(
            content,
            text="Aguardando EA...",
            font=ctk.CTkFont(size=10),
            text_color=self.colors['text_muted']
        )
        self.lbl_status_config.pack(pady=5)


    # ═══════════════════════════════════════════════════════════════
    # FUNÇÕES DE DADOS
    # ═══════════════════════════════════════════════════════════════

    def _ler_dados(self):
        """
        Lê o arquivo JSON exportado pelo EA.

        Usa retry (3 tentativas) porque o EA pode estar escrevendo no momento.
        Isso evita erros de "arquivo em uso" ou JSON incompleto.
        """
        if not os.path.exists(self.data_file):
            return None

        # Tenta 3x com intervalo de 100ms entre tentativas
        for _ in range(3):
            try:
                with open(self.data_file, "r", encoding="utf-8") as f:
                    conteudo = f.read()
                    if conteudo.strip():
                        return json.loads(conteudo)
            except (PermissionError, json.JSONDecodeError):
                time.sleep(0.1)  # Arquivo em uso, aguarda
            except Exception as e:
                print(f"Erro ao ler dados: {e}")
                break
        return None

    def _atualizar_dados(self):
        """
        Loop principal de atualização - roda a cada 250ms.

        1. Verifica se o modo mudou (LIVE <-> BACKTEST)
        2. Lê dados do arquivo JSON exportado pelo EA
        3. Atualiza todos os labels e indicadores visuais
        4. Sincroniza campos de configuração (apenas se não tiverem foco)
        """
        try:
            # Permite alternar entre LIVE e BACKTEST sem reiniciar
            novo_modo = self._detectar_modo()
            if novo_modo != self.modo_atual:
                self.modo_atual = novo_modo
                self._atualizar_arquivos()
                self.modo_badge.configure(text=f"● {self.modo_atual}")
                self.checkboxes_sincronizados = False

                # Mostra/oculta Lucro Total baseado no modo
                if self.modo_atual == "BACKTEST":
                    self.lucro_total_frame.pack(fill="x", padx=12, pady=(5, 10))
                else:
                    self.lucro_total_frame.pack_forget()

            dados = self._ler_dados()
            agora = time.time()

            if dados:
                novo_timestamp = dados.get('timestamp', '')

                # Verifica se recebeu dados NOVOS (timestamp diferente)
                if novo_timestamp != self.ultimo_timestamp:
                    self.ultimo_timestamp = novo_timestamp
                    self.ultima_atualizacao_real = agora  # Marca momento real

                # Em BACKTEST: sem verificação de timeout (dados chegam em rajadas)
                # Em LIVE: usa timeout para detectar desconexão
                if self.modo_atual == "BACKTEST":
                    # BACKTEST: sempre conectado se temos dados válidos
                    self.conexao_ativa = True
                    self.lbl_conexao.configure(text="CONECTADO", text_color=self.colors['accent_green'])
                    self.status_indicator.configure(fg_color=self.colors['accent_green'])

                    # Status do robô direto do EA
                    status = dados.get('status', 'ATIVO')
                    if status == "ATIVO":
                        self.status_badge.configure(text="● ATIVO", text_color=self.colors['accent_green'],
                                                   fg_color=self.colors['bg_tertiary'])
                    elif status == "PAUSADO":
                        self.status_badge.configure(text="● PAUSADO", text_color=self.colors['accent_yellow'],
                                                   fg_color=self.colors['bg_tertiary'])
                    else:
                        self.status_badge.configure(text=f"● {status}", text_color=self.colors['accent_cyan'],
                                                   fg_color=self.colors['bg_tertiary'])
                else:
                    # LIVE: Verifica timeout para detectar desconexão real
                    if self.ultima_atualizacao_real:
                        tempo_sem_dados = agora - self.ultima_atualizacao_real
                        if tempo_sem_dados > self.timeout_conexao:
                            # EA parou de enviar dados (travou ou fechou)
                            self.conexao_ativa = False
                            self.lbl_conexao.configure(text="DESCONECTADO", text_color=self.colors['accent_red'])
                            self.status_indicator.configure(fg_color=self.colors['accent_red'])
                            self.status_badge.configure(text="● DESCONECTADO", text_color=self.colors['accent_red'],
                                                       fg_color=self.colors['bg_tertiary'])
                        else:
                            # EA está enviando dados normalmente
                            self.conexao_ativa = True
                            self.lbl_conexao.configure(text="CONECTADO", text_color=self.colors['accent_green'])
                            self.status_indicator.configure(fg_color=self.colors['accent_green'])

                            # Status do robô (só mostra se conectado)
                            status = dados.get('status', 'DESCONHECIDO')
                            if status == "ATIVO":
                                self.status_badge.configure(text="● ATIVO", text_color=self.colors['accent_green'],
                                                           fg_color=self.colors['bg_tertiary'])
                            elif status == "PAUSADO":
                                self.status_badge.configure(text="● PAUSADO", text_color=self.colors['accent_yellow'],
                                                           fg_color=self.colors['bg_tertiary'])
                            else:
                                self.status_badge.configure(text=f"● {status}", text_color=self.colors['accent_cyan'],
                                                           fg_color=self.colors['bg_tertiary'])
                    else:
                        # Primeira vez recebendo dados
                        self.ultima_atualizacao_real = agora
                        self.conexao_ativa = True
                        self.lbl_conexao.configure(text="CONECTADO", text_color=self.colors['accent_green'])
                        self.status_indicator.configure(fg_color=self.colors['accent_green'])

                # Atualiza dados visuais (independente do timeout, mostra últimos dados)
                if self.conexao_ativa:

                    # Atualiza labels
                    self.info_labels['ativo'].configure(text=dados.get('ativo', '--'))
                    self.info_labels['posicoes'].configure(text=str(dados.get('posicoes', 0)))
                    self.info_labels['rsi'].configure(text=f"{dados.get('rsi', 0):.2f}")

                    # Lucro dia
                    lucro_dia = dados.get('lucro_dia', 0)
                    cor_lucro = self.colors['accent_green'] if lucro_dia >= 0 else self.colors['accent_red']
                    self.info_labels['lucro_dia'].configure(text=f"R$ {lucro_dia:.2f}", text_color=cor_lucro)

                    # Saldo
                    self.info_labels['saldo'].configure(text=f"R$ {dados.get('saldo', 0):.2f}")

                    # Lucro aberto
                    lucro_aberto = dados.get('lucro_aberto', 0)
                    cor_aberto = self.colors['accent_green'] if lucro_aberto >= 0 else self.colors['accent_red']
                    self.info_labels['lucro_aberto'].configure(text=f"R$ {lucro_aberto:.2f}", text_color=cor_aberto)

                    # Lucro total (apenas em BACKTEST)
                    if self.modo_atual == "BACKTEST":
                        lucro_total = dados.get('lucro_total', 0)
                        cor_total = self.colors['accent_green'] if lucro_total >= 0 else self.colors['accent_red']
                        self.info_labels['lucro_total'].configure(text=f"R$ {lucro_total:.2f}", text_color=cor_total)

                    # Agressão
                    usar_agressao = dados.get('usar_agressao', False)
                    self.lbl_agressao_status.configure(
                        text="ATIVADO" if usar_agressao else "DESATIVADO",
                        text_color=self.colors['accent_green'] if usar_agressao else self.colors['accent_red']
                    )

                    if usar_agressao:
                        self.info_labels['agressao_compra'].configure(text=f"{dados.get('agressao_compra', 0):.1f}%", text_color=self.colors['accent_cyan'])
                        self.info_labels['agressao_venda'].configure(text=f"{dados.get('agressao_venda', 0):.1f}%", text_color=self.colors['accent_cyan'])
                        self.info_labels['agressao_vol'].configure(text=f"{dados.get('agressao_vol', 0):.0f}", text_color=self.colors['accent_cyan'])
                        direcao = dados.get('agressao_direcao', 'NEUTRO')
                        cor_dir = self.colors['accent_green'] if direcao == "COMPRA" else self.colors['accent_red'] if direcao == "VENDA" else self.colors['text_muted']
                        self.info_labels['agressao_direcao'].configure(text=direcao, text_color=cor_dir)
                    else:
                        for k in ['agressao_compra', 'agressao_venda', 'agressao_vol']:
                            self.info_labels[k].configure(text="--", text_color=self.colors['text_muted'])
                        self.info_labels['agressao_direcao'].configure(text="Desativado", text_color=self.colors['text_muted'])

                    # Volume Profile
                    usar_vp = dados.get('usar_volume_profile', False)
                    self.lbl_vp_status.configure(
                        text="ATIVADO" if usar_vp else "DESATIVADO",
                        text_color=self.colors['accent_green'] if usar_vp else self.colors['accent_red']
                    )

                    if usar_vp:
                        self.info_labels['vp_poc'].configure(text=f"{dados.get('vp_poc', 0):.2f}", text_color=self.colors['accent_cyan'])
                        self.info_labels['vp_vah'].configure(text=f"{dados.get('vp_vah', 0):.2f}", text_color=self.colors['accent_cyan'])
                        self.info_labels['vp_val'].configure(text=f"{dados.get('vp_val', 0):.2f}", text_color=self.colors['accent_cyan'])
                        self.info_labels['vp_zona'].configure(text=dados.get('vp_zona', '--'), text_color=self.colors['accent_cyan'])
                    else:
                        for k in ['vp_poc', 'vp_vah', 'vp_val']:
                            self.info_labels[k].configure(text="--", text_color=self.colors['text_muted'])
                        self.info_labels['vp_zona'].configure(text="Desativado", text_color=self.colors['text_muted'])

                    # Sinal status
                    self.lbl_sinal_status.configure(text=dados.get('sinal_status', 'Aguardando...'))

                    # Sincroniza campos
                    foco = self.focus_get()
                    entry_widgets = [self.entries['lote'], self.entries['sl'], self.entries['tp'], self.entry_trailing]
                    if foco not in entry_widgets:
                        self.entries['lote'].delete(0, 'end')
                        self.entries['lote'].insert(0, str(dados.get('lote', 1.0)))
                        self.entries['sl'].delete(0, 'end')
                        self.entries['sl'].insert(0, str(int(dados.get('stoploss', 200))))
                        self.entries['tp'].delete(0, 'end')
                        self.entries['tp'].insert(0, str(int(dados.get('takeprofit', 350))))
                        self.entry_trailing.delete(0, 'end')
                        self.entry_trailing.insert(0, str(int(dados.get('trailing_pontos', 150))))

                        if not self.checkboxes_sincronizados:
                            self.trailing_var.set(dados.get('usar_trailing', True))
                            self.agressao_var.set(dados.get('usar_agressao', False))
                            self.volume_profile_var.set(dados.get('usar_volume_profile', False))
                            self.checkboxes_sincronizados = True

                    self.lbl_status_config.configure(text=f"Atualizado: {self.ultimo_timestamp}")
            else:
                # Não há arquivo de dados - EA nunca foi iniciado ou arquivo foi deletado
                self.conexao_ativa = False
                self.lbl_conexao.configure(text="DESCONECTADO", text_color=self.colors['accent_red'])
                self.status_indicator.configure(fg_color=self.colors['accent_red'])
                self.status_badge.configure(text="● DESCONECTADO EA", text_color=self.colors['accent_yellow'],
                                           fg_color=self.colors['bg_tertiary'])

        except Exception as e:
            print(f"Erro: {e}")

        self.after(250, self._atualizar_dados)

    def _enviar_comando(self, comando):
        """
        Envia comando para o EA via arquivo de texto.

        Formato do arquivo:
        - Linha 1: comando (ex: PAUSAR, FECHAR_TUDO, SALVAR_CONFIG:...)
        - Linha 2: timestamp (para o EA saber se é comando novo)

        O EA lê, processa e deleta o arquivo de comandos.
        """
        try:
            timestamp = datetime.now().strftime("%Y.%m.%d %H:%M:%S")
            with open(self.command_file, "w", encoding="utf-8") as f:
                f.write(f"{comando}\n{timestamp}")
            return True
        except Exception as e:
            messagebox.showerror("Erro", f"Erro ao enviar comando: {e}")
            return False

    def _pausar_retomar(self):
        self._enviar_comando("PAUSAR")

    def _fechar_tudo(self):
        if messagebox.askyesno("Confirmar", "Fechar todas as posições?"):
            self._enviar_comando("FECHAR_TUDO")

    def _parar_ea(self):
        """Para o EA no MetaTrader e fecha o painel."""
        if messagebox.askyesno("Parar EA", "Isso vai remover o EA do gráfico e fechar o painel.\n\nDeseja continuar?"):
            self._enviar_comando("PARAR_EA")
            self.after(500, self.destroy)  # Aguarda 500ms para o comando ser enviado

    def _salvar_config(self):
        """
        Envia configurações atuais para o EA.

        Formato: SALVAR_CONFIG:sl,tp,trailing_pts,usar_trailing,usar_agressao,usar_vp,lote
        Exemplo: SALVAR_CONFIG:200,350,150,1,0,0,1.0
        """
        try:
            lote = float(self.entries['lote'].get())
            sl = float(self.entries['sl'].get())
            tp = float(self.entries['tp'].get())
            trailing_pts = float(self.entry_trailing.get())
            usar_trailing = 1 if self.trailing_var.get() else 0
            usar_agressao = 1 if self.agressao_var.get() else 0
            usar_vp = 1 if self.volume_profile_var.get() else 0

            # Ordem: sl, tp, trailing_pts, usar_trailing, usar_agressao, usar_vp, lote
            if self._enviar_comando(f"SALVAR_CONFIG:{sl},{tp},{trailing_pts},{usar_trailing},{usar_agressao},{usar_vp},{lote}"):
                self.lbl_status_config.configure(text="✓ Configurações salvas!", text_color=self.colors['accent_green'])
                self.after(3000, lambda: self.lbl_status_config.configure(text_color=self.colors['text_muted']))
        except ValueError:
            messagebox.showerror("Erro", "Valores inválidos!")

    def _resetar_config(self):
        if messagebox.askyesno("Confirmar", "Resetar para valores originais?"):
            self._enviar_comando("RESETAR_CONFIG")
            # Força re-sincronização dos checkboxes e campos na próxima atualização
            self.checkboxes_sincronizados = False
            self.lbl_status_config.configure(text="↺ Resetado! Aguarde...", text_color=self.colors['accent_yellow'])
            self.after(2000, lambda: self.lbl_status_config.configure(text_color=self.colors['text_muted']))

    def _diagnostico(self):
        diag = ctk.CTkToplevel(self)
        diag.title("Diagnóstico")
        diag.geometry("500x400")
        diag.configure(fg_color=self.colors['bg_primary'])

        container = ctk.CTkFrame(diag, fg_color=self.colors['bg_secondary'], corner_radius=16)
        container.pack(fill="both", expand=True, padx=20, pady=20)

        ctk.CTkLabel(
            container,
            text="🔍 DIAGNÓSTICO RSI SNIPER",
            font=ctk.CTkFont(size=18, weight="bold"),
            text_color=self.colors['accent_cyan']
        ).pack(pady=20)

        info_frame = ctk.CTkFrame(container, fg_color="transparent")
        info_frame.pack(fill="x", padx=30, pady=10)

        status_cor = self.colors['accent_green'] if self.conexao_ativa else self.colors['accent_red']
        status_txt = "CONECTADO" if self.conexao_ativa else "DESCONECTADO"

        ctk.CTkLabel(info_frame, text=f"Status: {status_txt}", font=ctk.CTkFont(size=14, weight="bold"),
                    text_color=status_cor).pack(anchor="w", pady=5)
        ctk.CTkLabel(info_frame, text=f"Modo: {self.modo_atual}", font=ctk.CTkFont(size=12),
                    text_color=self.colors['text_secondary']).pack(anchor="w", pady=5)
        ctk.CTkLabel(info_frame, text=f"Arquivo: rsi_data_{self.modo_atual}.json", font=ctk.CTkFont(size=12),
                    text_color=self.colors['text_secondary']).pack(anchor="w", pady=5)
        ctk.CTkLabel(info_frame, text=f"Última atualização: {self.ultimo_timestamp or 'Aguardando...'}",
                    font=ctk.CTkFont(size=12), text_color=self.colors['text_secondary']).pack(anchor="w", pady=5)

    def _ajuda(self):
        ajuda = ctk.CTkToplevel(self)
        ajuda.title("Ajuda - RSI Sniper")
        ajuda.geometry("650x700")
        ajuda.configure(fg_color=self.colors['bg_primary'])

        # Container com scroll
        container = ctk.CTkScrollableFrame(
            ajuda,
            fg_color=self.colors['bg_secondary'],
            corner_radius=16
        )
        container.pack(fill="both", expand=True, padx=20, pady=20)

        # Título
        ctk.CTkLabel(
            container,
            text="❓ GUIA DE MÉTRICAS",
            font=ctk.CTkFont(size=20, weight="bold"),
            text_color=self.colors['accent_cyan']
        ).pack(pady=(10, 20))

        # Função auxiliar para criar seções
        def criar_secao(titulo, cor_titulo):
            frame = ctk.CTkFrame(container, fg_color=self.colors['bg_tertiary'], corner_radius=10)
            frame.pack(fill="x", pady=8, padx=10)
            ctk.CTkLabel(
                frame, text=titulo,
                font=ctk.CTkFont(size=14, weight="bold"),
                text_color=cor_titulo
            ).pack(anchor="w", padx=15, pady=(12, 5))
            return frame

        def criar_item(parent, termo, descricao):
            item_frame = ctk.CTkFrame(parent, fg_color="transparent")
            item_frame.pack(fill="x", padx=15, pady=3)
            ctk.CTkLabel(
                item_frame, text=f"• {termo}:",
                font=ctk.CTkFont(size=12, weight="bold"),
                text_color=self.colors['text_primary']
            ).pack(anchor="w")
            ctk.CTkLabel(
                item_frame, text=f"  {descricao}",
                font=ctk.CTkFont(size=11),
                text_color=self.colors['text_secondary'],
                wraplength=550
            ).pack(anchor="w", pady=(0, 5))

        # ═══ MONITOR ═══
        sec = criar_secao("📊 MONITOR", self.colors['accent_cyan'])
        criar_item(sec, "Status", "ATIVO = robô operando | PAUSADO = operações bloqueadas")
        criar_item(sec, "Ativo", "Símbolo do ativo sendo negociado (ex: WINM26, WDOJ26)")
        criar_item(sec, "Posições", "Quantidade de posições abertas no momento")
        criar_item(sec, "RSI", "Índice de Força Relativa (0-100). Abaixo de 30 = sobrevenda, Acima de 70 = sobrecompra")
        criar_item(sec, "Lucro do Dia", "Lucro/prejuízo realizado + flutuante do dia atual")
        criar_item(sec, "Saldo", "Saldo inicial + lucro realizado (sem lucro flutuante)")
        criar_item(sec, "Lucro Aberto", "Lucro/prejuízo das posições abertas (não realizado)")
        ctk.CTkFrame(sec, height=10, fg_color="transparent").pack()

        # ═══ AGRESSÃO ═══
        sec = criar_secao("⚡ AGRESSÃO (Fluxo de Ordens)", self.colors['accent_green'])
        criar_item(sec, "Compra %", "Percentual de ordens agressoras de compra no período")
        criar_item(sec, "Venda %", "Percentual de ordens agressoras de venda no período")
        criar_item(sec, "Volume", "Volume total de contratos no período analisado")
        criar_item(sec, "Direção", "COMPRA = fluxo comprador dominante | VENDA = fluxo vendedor | NEUTRO = equilibrado")
        criar_item(sec, "Filtro", "Quando ativado, só opera se a direção do fluxo confirmar o sinal do RSI")
        ctk.CTkFrame(sec, height=10, fg_color="transparent").pack()

        # ═══ VOLUME PROFILE ═══
        sec = criar_secao("📊 VOLUME PROFILE", self.colors['accent_purple'])
        criar_item(sec, "POC", "Point of Control - preço com maior volume negociado (região de equilíbrio)")
        criar_item(sec, "VAH", "Value Area High - limite superior da área de valor (70% do volume)")
        criar_item(sec, "VAL", "Value Area Low - limite inferior da área de valor (70% do volume)")
        criar_item(sec, "Zona", "ACIMA_POC = preço acima do POC | ABAIXO_POC = preço abaixo | NA_POC = no POC")
        criar_item(sec, "Filtro", "Quando ativado, usa a zona do VP como confirmação adicional para entradas")
        ctk.CTkFrame(sec, height=10, fg_color="transparent").pack()

        # ═══ CONFIGURAÇÕES ═══
        sec = criar_secao("⚙️ CONFIGURAÇÕES", self.colors['accent_blue'])
        criar_item(sec, "Lote", "Quantidade de contratos/lotes por operação")
        criar_item(sec, "Stop Loss", "Distância em pontos para o stop loss (proteção contra perdas)")
        criar_item(sec, "Take Profit", "Distância em pontos para o take profit (alvo de lucro)")
        criar_item(sec, "Trailing Stop", "Quando ativado, o stop se move a favor conforme o preço avança")
        criar_item(sec, "Trailing (pts)", "Distância em pontos para ativar/mover o trailing stop")
        ctk.CTkFrame(sec, height=10, fg_color="transparent").pack()

        # ═══ ESTRATÉGIA RSI ═══
        sec = criar_secao("📈 ESTRATÉGIA RSI SNIPER", self.colors['accent_yellow'])
        criar_item(sec, "Sinal de COMPRA", "RSI cruza acima do nível de sobrevenda (ex: 30 → 31)")
        criar_item(sec, "Sinal de VENDA", "RSI cruza abaixo do nível de sobrecompra (ex: 70 → 69)")
        criar_item(sec, "Confirmação", "Filtros de Agressão e Volume Profile refinam os sinais")
        ctk.CTkFrame(sec, height=10, fg_color="transparent").pack()

        # Botão fechar
        ctk.CTkButton(
            container,
            text="✓ ENTENDI",
            font=ctk.CTkFont(size=14, weight="bold"),
            fg_color=self.colors['accent_green'],
            hover_color="#00cc77",
            text_color="#000000",
            corner_radius=10,
            height=40,
            command=ajuda.destroy
        ).pack(pady=20)


if __name__ == "__main__":
    app = RSIPanelModern()
    app.mainloop()
