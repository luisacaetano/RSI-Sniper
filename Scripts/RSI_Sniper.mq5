//+------------------------------------------------------------------+
//|                         RSI SNIPER                               |
//|                                                                  |
//| Robô de trading baseado em RSI com filtros opcionais:            |
//| - Agressão (fluxo de ordens): confirma sinais com pressão real   |
//| - Volume Profile (POC/VAH/VAL): identifica zonas de valor        |
//|                                                                  |
//| Funciona em modo LIVE e BACKTEST (Strategy Tester)               |
//| Exporta dados para painel Python externo (rsi_panel.py)          |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "1.00"

#include <Trade/Trade.mqh>
#include <MWM/RSIExport.mqh>

//+------------------------------------------------------------------+
//| ESTRUTURAS DE DADOS                                              |
//+------------------------------------------------------------------+

// Dados de Agressao (Fluxo de Ordens)
struct AgressaoData {
   bool     ok;
   int      nTicks;
   int      janelaSeg;
   double   volumeTotal;
   double   volumeCompra;
   double   volumeVenda;
   double   pctCompra;       // 0..1
   double   pctVenda;        // 0..1
   string   direcao;         // "COMPRA", "VENDA" ou "NEUTRO"
};

// Dados de Volume Profile
struct VolumeProfileData {
   bool     ok;
   double   poc;             // Point of Control
   double   pocVolume;
   double   vah;             // Value Area High
   double   val;             // Value Area Low
   double   precoAtual;
   string   zona;            // "ACIMA_POC", "ABAIXO_POC", "NO_POC"
};

//+------------------------------------------------------------------+
//| SISTEMA DE LOG PERSONALIZADO                                     |
//+------------------------------------------------------------------+

enum ENUM_LOG_LEVEL {
   LOG_NONE = 0,      // Sem logs
   LOG_ERROR = 1,     // Apenas erros críticos
   LOG_INFO = 2,      // Informações importantes (sinais, execuções)
   LOG_DEBUG = 3      // Detalhes técnicos completos
};

int log_file_handle = INVALID_HANDLE;

// Buffer circular de logs para o painel (últimas 50 mensagens)
string g_log_buffer[];
int g_log_count = 0;
int g_log_index = 0;  // Índice circular para inserção
int LOG_BUFFER_SIZE = 50;
bool g_log_buffer_initialized = false;

//+------------------------------------------------------------------+
//| Função de log personalizado - grava em arquivo separado          |
//+------------------------------------------------------------------+
void LogMsg(ENUM_LOG_LEVEL level, string message) {
   // Verifica se deve logar baseado no nível configurado
   if(level > LogDetalhado)
      return;

   // Nome do nível
   string level_str = "";
   switch(level) {
      case LOG_ERROR: level_str = "ERROR"; break;
      case LOG_INFO:  level_str = "INFO "; break;
      case LOG_DEBUG: level_str = "DEBUG"; break;
      default: return;
   }

   // Formato: [YYYY.MM.DD HH:MM:SS] [LEVEL] Mensagem
   datetime now = TimeLocal();
   string timestamp = TimeToString(now, TIME_DATE|TIME_SECONDS);
   string log_line = StringFormat("[%s] [%s] %s\n", timestamp, level_str, message);

   // Grava no arquivo (append mode para manter histórico)
   if(log_file_handle == INVALID_HANDLE) {
      string filename = StringFormat("RSI_Sniper_%s.log", _Symbol);
      // FILE_READ|FILE_WRITE permite append sem truncar
      log_file_handle = FileOpen(filename, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);
      if(log_file_handle == INVALID_HANDLE) {
         // Se não existe, cria novo
         log_file_handle = FileOpen(filename, FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);
      }
   }

   if(log_file_handle != INVALID_HANDLE) {
      FileSeek(log_file_handle, 0, SEEK_END);
      FileWriteString(log_file_handle, log_line);
      FileFlush(log_file_handle);
   }

   // Verifica se é linha de separação (não adiciona prefixo)
   bool is_separator = (StringFind(message, "----") == 0 || StringFind(message, "====") == 0);

   // Imprime no terminal com prefixo visual (exceto separadores)
   if(is_separator)
      Print(message);
   else if(level == LOG_ERROR)
      Print("[ERRO] ", message);
   else if(level == LOG_INFO)
      Print("[OK] ", message);
   else if(level == LOG_DEBUG)
      Print("[DBG] ", message);

   // Adiciona ao buffer circular para o painel (apenas INFO e ERROR)
   if(level <= LOG_INFO) {
      // Pré-aloca buffer na primeira vez (O(1) depois)
      if(!g_log_buffer_initialized) {
         ArrayResize(g_log_buffer, LOG_BUFFER_SIZE);
         for(int i = 0; i < LOG_BUFFER_SIZE; i++)
            g_log_buffer[i] = "";
         g_log_buffer_initialized = true;
      }

      // Adiciona prefixo e mensagem no índice atual (sem prefixo para separadores)
      string prefix = is_separator ? "" : ((level == LOG_ERROR) ? "[ERRO] " : "[OK] ");
      g_log_buffer[g_log_index] = prefix + message;

      // Avança índice circular
      g_log_index = (g_log_index + 1) % LOG_BUFFER_SIZE;
      if(g_log_count < LOG_BUFFER_SIZE)
         g_log_count++;
   }
}

//+------------------------------------------------------------------+
//| PARAMETROS DE ENTRADA                                            |
//+------------------------------------------------------------------+

input group "=== RSI ==="
input int RSI_Period = 14;
input ENUM_APPLIED_PRICE RSI_Price = PRICE_CLOSE;
input double RSI_Oversold = 40.0;    // 40 = Mais sinais de compra (oversold)
input double RSI_Overbought = 60.0;  // 60 = Mais sinais de venda (overbought)

input group "=== AGRESSAO (Fluxo de Ordens) ==="
input bool UsarAgressao = false;     // Inicia DESATIVADO para simplificar testes
input int Agressao_JanelaSeg = 1;              // Rodrigo recomenda 1 segundo
input double Agressao_VolumeMinimo = 500;      // Volume minimo significativo
input double Agressao_PctMinimo = 0.70;        // 70% para confirmar direcao

input group "=== VOLUME PROFILE ==="
input bool UsarVolumeProfile = false;  // Inicia DESATIVADO para simplificar testes
input int VP_Barras = 60;
input int VP_PassoTicks = 5;
input double VP_MargemPOC = 10;

input group "=== GERENCIAMENTO DE RISCO ==="
input double LotSize = 1.0;
input double TakeProfit_Points = 350;
input double StopLoss_Points = 200;
input bool UseTrailingStop = true;
input double TrailingStop_Points = 150;

input group "=== CONTROLE ==="
input int MaxPositions = 1;
input ulong MagicNumber = 123456;  // Numero magico para identificar ordens do EA
input ENUM_LOG_LEVEL LogDetalhado = LOG_INFO;  // Nivel de log: NONE, ERROR, INFO, DEBUG

input group "=== PAINEL EXTERNO ==="
input bool UsarPainelExterno = true;
input uint IntervaloExportacao_MS = 500;  // Throttle de exportacao (ms)

//+------------------------------------------------------------------+
//| VARIAVEIS GLOBAIS                                                |
//+------------------------------------------------------------------+

CTrade trade;
int rsi_handle;
double rsi_buffer[];
bool buy_signal_sent = false;
bool sell_signal_sent = false;
bool aguardando_entrada = false;  // Bloqueia novas entradas enquanto ordem está pendente
// Configuracoes do EA (usando struct do RSIExport)
SRSIConfig cfg;           // Configuracoes atuais (modificaveis pelo painel)
SRSIConfig cfg_original;  // Configuracoes originais (para resetar)

double lucro_dia = 0.0;
double lucro_realizado = 0.0;  // Lucro de trades fechados (do dia)
double lucro_total_backtest = 0.0;  // Lucro total acumulado (todo o backtest)
double saldo_inicial = 0.0;    // Saldo no início do backtest

CRSIExport* exportador = NULL;
uint ultima_exportacao = 0;  // GetTickCount() retorna uint, não datetime
uint ultima_atualizacao_lucro = 0;  // Throttle para AtualizarLucroDia

double vol_min, vol_max, vol_step;

AgressaoData g_agressao;
VolumeProfileData g_volumeProfile;
datetime g_lastCalcSec = 0;

//+------------------------------------------------------------------+
//| Converte volume do tick para double                              |
//+------------------------------------------------------------------+
double TickVolumeToDouble(const MqlTick &t) {
   double vr = (double)t.volume_real;
   if(vr > 0.0) return vr;
   return (double)t.volume;
}

//+------------------------------------------------------------------+
//| Calcula agressao (fluxo de ordens) na janela de tempo            |
//+------------------------------------------------------------------+
AgressaoData CalcularAgressao() {
   AgressaoData a;
   a.ok = false;
   a.nTicks = 0;
   a.janelaSeg = Agressao_JanelaSeg;
   a.volumeTotal = 0.0;
   a.volumeCompra = 0.0;
   a.volumeVenda = 0.0;
   a.pctCompra = 0.0;
   a.pctVenda = 0.0;
   a.direcao = "NEUTRO";

   datetime t2 = TimeTradeServer();
   datetime t1 = t2 - (datetime)Agressao_JanelaSeg;
   if(t1 <= 0) t1 = t2 - 1;

   MqlTick ticks[];
   int copied = CopyTicksRange(_Symbol, ticks, COPY_TICKS_TRADE,
                               (ulong)t1 * 1000, (ulong)t2 * 1000);
   if(copied <= 0)
      return a;

   double buyVol = 0.0;
   double sellVol = 0.0;
   double total = 0.0;

   for(int i = 0; i < copied; i++) {
      double v = TickVolumeToDouble(ticks[i]);
      if(v <= 0.0) continue;

      total += v;

      bool isBuy = ((ticks[i].flags & TICK_FLAG_BUY) != 0);
      bool isSell = ((ticks[i].flags & TICK_FLAG_SELL) != 0);

      if(isBuy && !isSell) {
         buyVol += v;
      }
      else if(isSell && !isBuy) {
         sellVol += v;
      }
      else {
         // Fallback: compara LAST com BID/ASK
         double last = ticks[i].last;
         double bid = ticks[i].bid;
         double ask = ticks[i].ask;

         if(ask > 0 && last >= (ask - _Point * 0.5))
            buyVol += v;
         else if(bid > 0 && last <= (bid + _Point * 0.5))
            sellVol += v;
      }
   }

   if(total <= 0.0)
      return a;

   a.ok = true;
   a.nTicks = copied;
   a.volumeTotal = total;
   a.volumeCompra = buyVol;
   a.volumeVenda = sellVol;
   a.pctCompra = buyVol / total;
   a.pctVenda = sellVol / total;

   if(a.pctCompra >= Agressao_PctMinimo && a.volumeTotal >= Agressao_VolumeMinimo)
      a.direcao = "COMPRA";
   else if(a.pctVenda >= Agressao_PctMinimo && a.volumeTotal >= Agressao_VolumeMinimo)
      a.direcao = "VENDA";
   else
      a.direcao = "NEUTRO";

   return a;
}

//+------------------------------------------------------------------+
//| Funcoes auxiliares do Volume Profile                             |
//+------------------------------------------------------------------+
double PriceStep() {
   return _Point * (double)MathMax(1, VP_PassoTicks);
}

long PriceToIndex(double price, double step) {
   return (long)MathRound(price / step);
}

double IndexToPrice(long idx, double step) {
   return (double)idx * step;
}

//+------------------------------------------------------------------+
//| Calcula Volume Profile (POC, VAH, VAL) - OTIMIZADO O(n)          |
//+------------------------------------------------------------------+
VolumeProfileData CalcularVolumeProfile() {
   VolumeProfileData vp;
   vp.ok = false;
   vp.poc = 0.0;
   vp.pocVolume = 0.0;
   vp.vah = 0.0;
   vp.val = 0.0;
   vp.precoAtual = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   vp.zona = "INDEFINIDO";

   MqlRates rates[];
   int cnt = CopyRates(_Symbol, PERIOD_M1, 0, VP_Barras, rates);
   if(cnt <= 0)
      return vp;

   ArraySetAsSeries(rates, false);

   double step = PriceStep();

   // Primeiro passo: encontrar range global de preços
   double globalLow = rates[0].low;
   double globalHigh = rates[0].high;
   for(int i = 1; i < cnt; i++) {
      if(rates[i].low < globalLow) globalLow = rates[i].low;
      if(rates[i].high > globalHigh) globalHigh = rates[i].high;
   }

   long idxMin = PriceToIndex(globalLow, step);
   long idxMax = PriceToIndex(globalHigh, step);
   int niveis = (int)(idxMax - idxMin + 1);

   if(niveis <= 0 || niveis > 10000)  // Limite de segurança
      return vp;

   // Aloca array de volumes com indexação direta (O(1) acesso)
   double volumes[];
   ArrayResize(volumes, niveis);
   ArrayInitialize(volumes, 0.0);

   // Segundo passo: acumular volumes (O(n) total)
   for(int i = 0; i < cnt; i++) {
      long i_lo = PriceToIndex(rates[i].low, step) - idxMin;
      long i_hi = PriceToIndex(rates[i].high, step) - idxMin;
      if(i_hi < i_lo) { long t = i_hi; i_hi = i_lo; i_lo = t; }

      int slots = (int)(i_hi - i_lo + 1);
      if(slots <= 0) slots = 1;
      double vshare = (double)rates[i].tick_volume / (double)slots;

      for(long k = i_lo; k <= i_hi && k < niveis; k++) {
         volumes[(int)k] += vshare;
      }
   }

   // Terceiro passo: encontrar POC e calcular total
   int pocIdx = 0;
   double maxVol = 0.0;
   double totalVol = 0.0;
   for(int i = 0; i < niveis; i++) {
      totalVol += volumes[i];
      if(volumes[i] > maxVol) {
         maxVol = volumes[i];
         pocIdx = i;
      }
   }

   if(totalVol <= 0)
      return vp;

   vp.ok = true;
   vp.poc = IndexToPrice(idxMin + pocIdx, step);
   vp.pocVolume = maxVol;

   // Value Area (70% do volume) - usando indexação direta
   double targetVol = totalVol * 0.70;
   double coveredVol = maxVol;

   int valIdx = pocIdx;
   int vahIdx = pocIdx;

   while(coveredVol < targetVol) {
      double volBelow = (valIdx > 0) ? volumes[valIdx - 1] : 0;
      double volAbove = (vahIdx < niveis - 1) ? volumes[vahIdx + 1] : 0;

      if(volBelow <= 0 && volAbove <= 0) break;

      if(volBelow >= volAbove && volBelow > 0) {
         valIdx--;
         coveredVol += volBelow;
      } else if(volAbove > 0) {
         vahIdx++;
         coveredVol += volAbove;
      } else break;
   }

   vp.val = IndexToPrice(idxMin + valIdx, step);
   vp.vah = IndexToPrice(idxMin + vahIdx, step);

   double margem = VP_MargemPOC * _Point;
   if(vp.precoAtual >= vp.poc - margem && vp.precoAtual <= vp.poc + margem)
      vp.zona = "NO_POC";
   else if(vp.precoAtual > vp.poc)
      vp.zona = "ACIMA_POC";
   else
      vp.zona = "ABAIXO_POC";

   return vp;
}

//+------------------------------------------------------------------+
//| Ajusta SL/TP para respeitar STOPS_LEVEL do simbolo               |
//+------------------------------------------------------------------+
void AjustarStops(double preco_entrada, double &sl, double &tp, bool is_buy) {
   long stops_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   long spread_points = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   double spread = (double)spread_points * point;
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   // Margem de seguranca adicional (em pontos)
   long margem_seguranca = 15;

   // Calcula distancia minima respeitando SYMBOL_TRADE_STOPS_LEVEL
   long dist_minima_pontos = stops_level + margem_seguranca;

   // Se stops_level for 0, usa margem maior para seguranca
   if(stops_level == 0)
      dist_minima_pontos = margem_seguranca + 10;

   // Calcula distancia em preco
   double dist_minima = dist_minima_pontos * point;

   // Garante que seja pelo menos 3x o spread
   double spread_minimo = spread * 3;
   if(dist_minima < spread_minimo)
      dist_minima = spread_minimo;

   if(LogDetalhado >= LOG_DEBUG) {
      Print("  [DEBUG] Ajuste de Stops:");
      Print("    SYMBOL_TRADE_STOPS_LEVEL: ", stops_level, " pontos");
      Print("    Margem de seguranca: ", margem_seguranca, " pontos");
      Print("    Distancia minima total: ", dist_minima_pontos, " pontos");
      Print("    Spread: ", spread_points, " pontos");
   }

   // Armazena valores originais para comparacao
   double sl_original = sl;
   double tp_original = tp;

   if(is_buy) {
      // COMPRA: SL abaixo do preco, TP acima
      double dist_sl_atual = preco_entrada - sl;
      double dist_tp_atual = tp - preco_entrada;

      if(dist_sl_atual < dist_minima)
         sl = preco_entrada - dist_minima;
      if(dist_tp_atual < dist_minima)
         tp = preco_entrada + dist_minima;
   } else {
      // VENDA: SL acima do preco, TP abaixo
      double dist_sl_atual = sl - preco_entrada;
      double dist_tp_atual = preco_entrada - tp;

      if(dist_sl_atual < dist_minima)
         sl = preco_entrada + dist_minima;
      if(dist_tp_atual < dist_minima)
         tp = preco_entrada - dist_minima;
   }

   // CRÍTICO: Normaliza para tick size ANTES da validação final
   if(tick_size > 0) {
      sl = MathRound(sl / tick_size) * tick_size;
      tp = MathRound(tp / tick_size) * tick_size;
   }

   // VALIDAÇÃO FINAL: Após o arredondamento, garante que a distância ainda é válida
   double dist_sl_apos_arred = is_buy ? (preco_entrada - sl) : (sl - preco_entrada);
   double dist_tp_apos_arred = is_buy ? (tp - preco_entrada) : (preco_entrada - tp);

   // Se o arredondamento reduziu abaixo do mínimo, adiciona mais um tick
   if(dist_sl_apos_arred < dist_minima) {
      if(is_buy)
         sl -= tick_size;
      else
         sl += tick_size;
   }

   if(dist_tp_apos_arred < dist_minima) {
      if(is_buy)
         tp += tick_size;
      else
         tp -= tick_size;
   }

   // Recalcula distancias finais
   double dist_sl_final = is_buy ? (preco_entrada - sl) : (sl - preco_entrada);
   double dist_tp_final = is_buy ? (tp - preco_entrada) : (preco_entrada - tp);

   if(LogDetalhado >= LOG_DEBUG) {
      Print("    SL original: ", DoubleToString(sl_original, _Digits),
            " -> Final: ", DoubleToString(sl, _Digits),
            " (distancia: ", (int)(dist_sl_final / point), " pts)");
      Print("    TP original: ", DoubleToString(tp_original, _Digits),
            " -> Final: ", DoubleToString(tp, _Digits),
            " (distancia: ", (int)(dist_tp_final / point), " pts)");

      if(sl != sl_original || tp != tp_original) {
         Print("    >>> STOPS AJUSTADOS PARA RESPEITAR DISTANCIA MINIMA");
      }
   }
}

//+------------------------------------------------------------------+
//| Normaliza volume de acordo com regras do simbolo                 |
//+------------------------------------------------------------------+
double NormalizarVolume(double volume) {
   // vol_min, vol_max, vol_step já são globais inicializadas no OnInit()
   double minimo_efetivo = vol_min;
   if(vol_step > vol_min && vol_step > 0)
      minimo_efetivo = vol_step;

   if(volume < minimo_efetivo)
      volume = minimo_efetivo;

   if(vol_step > 0) {
      volume = MathRound(volume / vol_step) * vol_step;
      if(volume <= 0)
         volume = minimo_efetivo;
   }

   if(volume > vol_max)
      volume = vol_max;

   return NormalizeDouble(volume, 2);
}

//+------------------------------------------------------------------+
//| Verifica confirmacao para COMPRA                                 |
//+------------------------------------------------------------------+
bool ConfirmacaoCompra() {
   bool confirmado = true;

   if(cfg.usar_agressao) {
      if(g_agressao.ok) {
         if(g_agressao.direcao == "COMPRA") {
            if(LogDetalhado >= LOG_DEBUG)
               Print("    Agressao: COMPRADORES dominando (",
                     DoubleToString(g_agressao.pctCompra * 100, 1), "%)");
         } else {
            if(LogDetalhado >= LOG_DEBUG)
               Print("    Agressao: ", g_agressao.direcao,
                     " (Compra: ", DoubleToString(g_agressao.pctCompra * 100, 1), "%)");
            confirmado = false;
         }
      }
   }

   if(cfg.usar_volume_profile && confirmado) {
      if(g_volumeProfile.ok) {
         if(LogDetalhado >= LOG_DEBUG)
            Print("    Volume Profile: Preco ", g_volumeProfile.zona,
                  " | POC: ", DoubleToString(g_volumeProfile.poc, _Digits));
      }
   }

   return confirmado;
}

//+------------------------------------------------------------------+
//| Verifica confirmacao para VENDA                                  |
//+------------------------------------------------------------------+
bool ConfirmacaoVenda() {
   bool confirmado = true;

   if(cfg.usar_agressao) {
      if(g_agressao.ok) {
         if(g_agressao.direcao == "VENDA") {
            if(LogDetalhado >= LOG_DEBUG)
               Print("    Agressao: VENDEDORES dominando (",
                     DoubleToString(g_agressao.pctVenda * 100, 1), "%)");
         } else {
            if(LogDetalhado >= LOG_DEBUG)
               Print("    Agressao: ", g_agressao.direcao,
                     " (Venda: ", DoubleToString(g_agressao.pctVenda * 100, 1), "%)");
            confirmado = false;
         }
      }
   }

   if(cfg.usar_volume_profile && confirmado) {
      if(g_volumeProfile.ok) {
         if(LogDetalhado >= LOG_DEBUG)
            Print("    Volume Profile: Preco ", g_volumeProfile.zona,
                  " | POC: ", DoubleToString(g_volumeProfile.poc, _Digits));
      }
   }

   return confirmado;
}

//+------------------------------------------------------------------+
//| Inicializacao                                                    |
//+------------------------------------------------------------------+
int OnInit() {
   LogMsg(LOG_INFO, "============================================================");
   LogMsg(LOG_INFO, "RSI SNIPER - Inicializando");
   LogMsg(LOG_INFO, "============================================================");

   vol_min = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   vol_max = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   vol_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   LogMsg(LOG_INFO, StringFormat("Ativo: %s | Timeframe: %s", _Symbol, EnumToString(_Period)));

   // Inicializa struct de configuracoes
   cfg.pausado = false;
   cfg.lote = NormalizarVolume(LotSize);
   if(cfg.lote != LotSize)
      LogMsg(LOG_INFO, StringFormat("Lote ajustado: %.2f -> %.2f", LotSize, cfg.lote));

   cfg.sl = StopLoss_Points;
   cfg.tp = TakeProfit_Points;
   cfg.trailing = UseTrailingStop;
   cfg.trailing_pts = TrailingStop_Points;
   cfg.usar_agressao = UsarAgressao;
   cfg.usar_volume_profile = UsarVolumeProfile;

   // Guarda valores originais para reset
   cfg_original = cfg;

   // Guarda saldo inicial para calcular lucro realizado no backtest
   // (ACCOUNT_BALANCE não atualiza em tempo real no Strategy Tester)
   saldo_inicial = AccountInfoDouble(ACCOUNT_BALANCE);
   lucro_realizado = 0.0;

   rsi_handle = iRSI(_Symbol, _Period, RSI_Period, RSI_Price);
   if(rsi_handle == INVALID_HANDLE) {
      LogMsg(LOG_ERROR, "Falha ao criar indicador RSI");
      return(INIT_FAILED);
   }
   ArraySetAsSeries(rsi_buffer, true);

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(10);

   // Verifica modo de preenchimento suportado pelo simbolo
   long filling_mode = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling_mode & SYMBOL_FILLING_FOK) != 0)
      trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((filling_mode & SYMBOL_FILLING_IOC) != 0)
      trade.SetTypeFilling(ORDER_FILLING_IOC);
   else
      trade.SetTypeFilling(ORDER_FILLING_RETURN);

   trade.SetAsyncMode(false);
   trade.LogLevel(LOG_LEVEL_NO);  // Desabilita logs automaticos do CTrade

   LogMsg(LOG_DEBUG, "------------------------------------------------------------");
   LogMsg(LOG_DEBUG, "CONFIGURACOES");
   LogMsg(LOG_DEBUG, StringFormat("RSI Periodo: %d | Sobrevenda: %.1f | Sobrecompra: %.1f", RSI_Period, RSI_Oversold, RSI_Overbought));
   LogMsg(LOG_DEBUG, StringFormat("Lote: %.2f | SL: %.0f pts | TP: %.0f pts", cfg.lote, cfg.sl, cfg.tp));
   LogMsg(LOG_DEBUG, StringFormat("Trailing Stop: %s", cfg.trailing ? "Ativo" : "Desativado"));
   LogMsg(LOG_DEBUG, "------------------------------------------------------------");
   LogMsg(LOG_DEBUG, StringFormat("Agressao (Fluxo): %s", cfg.usar_agressao ? "Ativo" : "Desativado"));
   LogMsg(LOG_DEBUG, StringFormat("Volume Profile: %s", cfg.usar_volume_profile ? "Ativo" : "Desativado"));
   LogMsg(LOG_DEBUG, "------------------------------------------------------------");

   if(UsarPainelExterno) {
      exportador = new CRSIExport();
      ExportarDadosPainelExterno();

      // Timer só funciona em modo live, não em backtest
      bool is_tester = MQLInfoInteger(MQL_TESTER);
      if(!is_tester)
         EventSetTimer(1);

      LogMsg(LOG_INFO, StringFormat("Painel Externo: ATIVO | Modo: %s", is_tester ? "BACKTEST" : "LIVE"));
      if(is_tester) {
         LogMsg(LOG_INFO, "BACKTEST: Exportacao via OnTick() (sem timer)");
         LogMsg(LOG_INFO, "BACKTEST: Arquivo = rsi_data_BACKTEST.json");
      }
      LogMsg(LOG_DEBUG, "[macOS] cd \"$HOME/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5/Include/MWM\" && python3 rsi_panel.py");
   }

   LogMsg(LOG_INFO, "============================================================");
   LogMsg(LOG_INFO, "RSI SNIPER inicializado com sucesso!");
   LogMsg(LOG_INFO, "============================================================");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Timer                                                            |
//+------------------------------------------------------------------+
void OnTimer() {
   if(UsarPainelExterno && exportador != NULL) {
      AtualizarLucroDia();        // Atualiza lucro do dia (1x por segundo)
      ExportarDadosPainelExterno(); // Exporta dados para o painel (1x por segundo)
      // ProcessarComandosPainelExterno() removido - já processa no OnTick() com frequência suficiente
   }
}

//+------------------------------------------------------------------+
//| Finalizacao                                                      |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   EventKillTimer();

   // Log ANTES de fechar o arquivo
   LogMsg(LOG_INFO, "============================================================");
   LogMsg(LOG_INFO, "RSI SNIPER finalizado");
   LogMsg(LOG_INFO, "============================================================");

   if(rsi_handle != INVALID_HANDLE)
      IndicatorRelease(rsi_handle);

   if(exportador != NULL)
      delete exportador;

   // Fecha arquivo de log POR ÚLTIMO
   if(log_file_handle != INVALID_HANDLE) {
      FileClose(log_file_handle);
      log_file_handle = INVALID_HANDLE;
   }
}

//+------------------------------------------------------------------+
//| OnTrade - Chamado quando posicoes/ordens mudam                   |
//+------------------------------------------------------------------+
void OnTrade() {
   // BACKTEST: Exporta imediatamente quando posição abre/fecha
   if(UsarPainelExterno && exportador != NULL) {
      AtualizarLucroDia(true);  // Força atualização imediata
      ultima_exportacao = 0;    // Força exportação
      ExportarDadosPainelExterno();
   }
}

//+------------------------------------------------------------------+
//| OnTradeTransaction - Loga quando trade fecha (não soma, apenas log)
//| O cálculo do lucro é feito em CalcularLucroRealizadoHistorico()  |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result) {
   // Captura apenas deals (transações de fechamento)
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD) {
      // Verifica se é do nosso símbolo
      if(trans.symbol != _Symbol)
         return;

      // Busca informações do deal
      ulong deal_ticket = trans.deal;
      if(HistoryDealSelect(deal_ticket)) {
         // Verifica se é saída (fechamento de posição)
         ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT) {
            double lucro_deal = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
            double comissao = HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);
            double swap = HistoryDealGetDouble(deal_ticket, DEAL_SWAP);
            double lucro_liquido = lucro_deal + comissao + swap;

            // Recalcula o acumulado do histórico (fonte única de verdade)
            AtualizarLucroDia(true);

            if(LogDetalhado >= LOG_INFO && lucro_deal != 0) {
               LogMsg(LOG_INFO, StringFormat("TRADE FECHADO | Lucro: %.2f | Comissao: %.2f | Total: %.2f | Acumulado: %.2f",
                      lucro_liquido, comissao, lucro_liquido, lucro_realizado));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| OnTick - Logica principal                                        |
//+------------------------------------------------------------------+
void OnTick() {
   // ✅ BACKTEST: Atualiza e exporta a cada tick (OnTimer não funciona no backtest)
   AtualizarLucroDia();

   // ✅ COMMENT: Exibe dados em tempo real no gráfico (funciona no Strategy Tester Visual)
   int posicoes = 0;
   double lucro_posicoes = 0;
   for(int i = 0; i < PositionsTotal(); i++) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetString(POSITION_SYMBOL) == _Symbol) {
         posicoes++;
         lucro_posicoes += PositionGetDouble(POSITION_PROFIT);
      }
   }
   double rsi_comment = 0;
   if(CopyBuffer(rsi_handle, 0, 0, 1, rsi_buffer) > 0)
      rsi_comment = rsi_buffer[0];

   // Calcula saldo real = inicial + lucro (total em backtest, diário em live)
   double lucro_para_saldo = MQLInfoInteger(MQL_TESTER) ? lucro_total_backtest : lucro_realizado;
   double saldo_calculado = saldo_inicial + lucro_para_saldo;

   // Mostra LIVE ou BACKTEST no título do painel
   string modo_texto = MQLInfoInteger(MQL_TESTER) ? "BACKTEST" : "LIVE";

   // Em BACKTEST, mostra lucro total acumulado; em LIVE, mostra lucro do dia
   double lucro_exibir = MQLInfoInteger(MQL_TESTER) ? lucro_total_backtest : lucro_dia;
   string label_lucro = MQLInfoInteger(MQL_TESTER) ? "LUCRO TOTAL:  " : "LUCRO DO DIA: ";

   Comment(
      "═══════════════════════════════════════\n",
      "       RSI SNIPER - ", modo_texto, "\n",
      "═══════════════════════════════════════\n",
      "Saldo Inicial:   ", DoubleToString(saldo_inicial, 2), "\n",
      "Saldo Calculado: ", DoubleToString(saldo_calculado, 2), "\n",
      "───────────────────────────────────────\n",
      "Lucro Realizado: ", DoubleToString(lucro_realizado, 2), "\n",
      "Lucro Aberto:    ", DoubleToString(lucro_posicoes, 2), "\n",
      label_lucro, DoubleToString(lucro_exibir, 2), "\n",
      "───────────────────────────────────────\n",
      "Posicoes:  ", posicoes, "\n",
      "RSI:       ", DoubleToString(rsi_comment, 2), "\n",
      "═══════════════════════════════════════"
   );

   if(UsarPainelExterno && exportador != NULL)
      ExportarDadosPainelExterno();

   // Processa comandos do painel (PAUSAR, FECHAR_TUDO, SALVAR_CONFIG, etc)
   if(UsarPainelExterno && exportador != NULL)
      ProcessarComandosPainelExterno();

   if(cfg.pausado)
      return;

   int total_positions = PositionsTotal();

   if(cfg.trailing && total_positions > 0)
      ApplyTrailingStop();

   // ✅ Calcula RSI ANTES de verificar MaxPositions (permite reset de flags)
   if(CopyBuffer(rsi_handle, 0, 0, 3, rsi_buffer) <= 0)
      return;

   double rsi_current = rsi_buffer[0];
   double rsi_previous = rsi_buffer[1];

   // Atualiza Agressao e Volume Profile (1x por segundo) - ANTES das verificações de return
   datetime nowSec = TimeTradeServer();
   if(nowSec != g_lastCalcSec) {
      g_lastCalcSec = nowSec;

      if(cfg.usar_agressao)
         g_agressao = CalcularAgressao();

      if(cfg.usar_volume_profile)
         g_volumeProfile = CalcularVolumeProfile();
   }

   // ✅ Reset de flags - permite novo sinal quando RSI voltar à zona neutra
   // buy_signal_sent reseta quando RSI SOBE de volta (acima de oversold + margem)
   if(buy_signal_sent && rsi_current > RSI_Oversold + 5)
      buy_signal_sent = false;

   // sell_signal_sent reseta quando RSI CAI bem abaixo de overbought (zona neutra)
   if(sell_signal_sent && rsi_current < RSI_Overbought - 5)
      sell_signal_sent = false;

   // Bloqueia novas entradas se já atingiu MaxPositions (mas flags já foram resetadas)
   if(total_positions >= MaxPositions) {
      aguardando_entrada = false;  // Reset flag pois posição já existe
      return;
   }

   // Bloqueia novas entradas enquanto aguarda ordem ser processada
   if(aguardando_entrada)
      return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // SINAL DE COMPRA
   if(rsi_previous <= RSI_Oversold && rsi_current > RSI_Oversold) {
      if(!buy_signal_sent) {
         LogMsg(LOG_INFO, "------------------------------------------------------------");
         LogMsg(LOG_INFO, StringFormat("[SINAL] COMPRA DETECTADA | RSI: %.2f (cruzou acima de %.1f)", rsi_current, RSI_Oversold));
         LogMsg(LOG_INFO, "------------------------------------------------------------");

         if(ConfirmacaoCompra()) {
            double sl = ask - (cfg.sl * point);
            double tp = ask + (cfg.tp * point);
            AjustarStops(ask, sl, tp, true);
            double lote = NormalizarVolume(cfg.lote);

            aguardando_entrada = true;  // Bloqueia novas entradas
            if(trade.Buy(lote, _Symbol, ask, sl, tp, "RSI Compra")) {
               // Calcula distâncias reais (após ajuste)
               double sl_pts = (ask - sl) / point;
               double tp_pts = (tp - ask) / point;
               LogMsg(LOG_INFO, StringFormat("COMPRA EXECUTADA | Preco: %s | Lote: %.2f | SL: %s (-%.0f pts) | TP: %s (+%.0f pts)",
                                            DoubleToString(ask, _Digits),
                                            lote,
                                            DoubleToString(sl, _Digits), sl_pts,
                                            DoubleToString(tp, _Digits), tp_pts));
               buy_signal_sent = true;
               sell_signal_sent = false;
               // OnTrade() será chamado automaticamente e fará a exportação
            } else {
               aguardando_entrada = false;  // Reset flag em caso de falha
               LogMsg(LOG_ERROR, StringFormat("Falha ao executar COMPRA: %s", trade.ResultRetcodeDescription()));
            }
         } else {
            LogMsg(LOG_INFO, StringFormat("[BLOQUEADO] COMPRA BLOQUEADA | Filtro de Agressao: %s (%.1f%% compra) | Necessario: >= %.0f%% e volume >= %.0f",
                                         g_agressao.direcao,
                                         g_agressao.pctCompra * 100,
                                         Agressao_PctMinimo * 100,
                                         Agressao_VolumeMinimo));
         }
      }
   }

   // SINAL DE VENDA
   else if(rsi_previous >= RSI_Overbought && rsi_current < RSI_Overbought) {
      if(!sell_signal_sent) {
         LogMsg(LOG_INFO, "------------------------------------------------------------");
         LogMsg(LOG_INFO, StringFormat("[SINAL] VENDA DETECTADA | RSI: %.2f (cruzou abaixo de %.1f)", rsi_current, RSI_Overbought));
         LogMsg(LOG_INFO, "------------------------------------------------------------");

         if(ConfirmacaoVenda()) {
            double sl = bid + (cfg.sl * point);
            double tp = bid - (cfg.tp * point);
            AjustarStops(bid, sl, tp, false);
            double lote = NormalizarVolume(cfg.lote);

            aguardando_entrada = true;  // Bloqueia novas entradas
            if(trade.Sell(lote, _Symbol, bid, sl, tp, "RSI Venda")) {
               // Calcula distâncias reais (após ajuste)
               double sl_pts = (sl - bid) / point;
               double tp_pts = (bid - tp) / point;
               LogMsg(LOG_INFO, StringFormat("VENDA EXECUTADA | Preco: %s | Lote: %.2f | SL: %s (+%.0f pts) | TP: %s (-%.0f pts)",
                                            DoubleToString(bid, _Digits),
                                            lote,
                                            DoubleToString(sl, _Digits), sl_pts,
                                            DoubleToString(tp, _Digits), tp_pts));
               sell_signal_sent = true;
               buy_signal_sent = false;
               // OnTrade() será chamado automaticamente e fará a exportação
            } else {
               aguardando_entrada = false;  // Reset flag em caso de falha
               LogMsg(LOG_ERROR, StringFormat("Falha ao executar VENDA: %s", trade.ResultRetcodeDescription()));
            }
         } else {
            LogMsg(LOG_INFO, StringFormat("[BLOQUEADO] VENDA BLOQUEADA | Filtro de Agressao: %s (%.1f%% venda) | Necessario: >= %.0f%% e volume >= %.0f",
                                         g_agressao.direcao,
                                         g_agressao.pctVenda * 100,
                                         Agressao_PctMinimo * 100,
                                         Agressao_VolumeMinimo));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Exporta dados para o painel externo                              |
//+------------------------------------------------------------------+
void ExportarDadosPainelExterno() {
   // BACKTEST: Exporta a cada N barras para evitar throttle baseado em tempo real
   // GetTickCount() retorna tempo REAL do sistema, não tempo simulado no backtest
   // Isso causava bloqueio de quase todas as exportações durante backtest rápido

   static int ticks_desde_export = 0;
   bool is_tester = MQLInfoInteger(MQL_TESTER);

   if(is_tester) {
      // No backtest: exporta a cada 5 ticks para capturar posições rápidas
      ticks_desde_export++;
      if(ticks_desde_export < 5 && ultima_exportacao != 0)
         return;
      ticks_desde_export = 0;
   } else {
      // LIVE: Throttle baseado em tempo real (funciona corretamente)
      uint agora = GetTickCount();
      uint diff = agora - ultima_exportacao;
      if(diff < IntervaloExportacao_MS && diff < 60000)
         return;
   }

   ultima_exportacao = GetTickCount();

   string status = cfg.pausado ? "PAUSADO" : "ATIVO";
   int posicoes = 0;
   double lucro_aberto = 0.0;

   // Conta posicoes do simbolo atual e lucro aberto
   for(int i = 0; i < PositionsTotal(); i++) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket)) {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol) {
            posicoes++;
            lucro_aberto += PositionGetDouble(POSITION_PROFIT);
         }
      }
   }

   double rsi_atual = 0.0;
   if(CopyBuffer(rsi_handle, 0, 0, 1, rsi_buffer) > 0)
      rsi_atual = rsi_buffer[0];

   // Obter saldo da conta (calculado, pois ACCOUNT_BALANCE não atualiza no Tester)
   // Em BACKTEST usa lucro total acumulado; em LIVE usa lucro do dia
   double lucro_para_saldo = MQLInfoInteger(MQL_TESTER) ? CalcularLucroTotalHistorico() : lucro_realizado;
   double saldo = saldo_inicial + lucro_para_saldo;

   // Determinar status do sinal
   string sinal_status = "Aguardando sinal...";
   if(rsi_atual <= RSI_Oversold)
      sinal_status = "RSI em SOBREVENDA (" + DoubleToString(rsi_atual, 1) + ")";
   else if(rsi_atual >= RSI_Overbought)
      sinal_status = "RSI em SOBRECOMPRA (" + DoubleToString(rsi_atual, 1) + ")";
   else if(rsi_atual > RSI_Oversold && rsi_atual < 45)
      sinal_status = "RSI subindo (" + DoubleToString(rsi_atual, 1) + ")";
   else if(rsi_atual < RSI_Overbought && rsi_atual > 55)
      sinal_status = "RSI caindo (" + DoubleToString(rsi_atual, 1) + ")";
   else
      sinal_status = "RSI neutro (" + DoubleToString(rsi_atual, 1) + ")";

   if(posicoes > 0)
      sinal_status = "Em operacao: " + IntegerToString(posicoes) + " pos";

   // Prepara logs na ordem correta (mais novo primeiro) para o buffer circular
   string logs_ordenados[];
   ArrayResize(logs_ordenados, g_log_count);
   for(int i = 0; i < g_log_count; i++) {
      // Lê do mais recente para o mais antigo
      int idx = (g_log_index - 1 - i + LOG_BUFFER_SIZE) % LOG_BUFFER_SIZE;
      logs_ordenados[i] = g_log_buffer[idx];
   }

   exportador.ExportarDados(
      status, _Symbol, posicoes, lucro_dia, rsi_atual,
      cfg.lote, cfg.sl, cfg.tp,
      cfg.trailing, cfg.trailing_pts,
      // Buffer de logs ordenado (mais novo primeiro)
      logs_ordenados, g_log_count,
      // Novos dados de monitoramento (opcionais)
      saldo, lucro_aberto,
      g_agressao.pctCompra, g_agressao.pctVenda,
      g_agressao.volumeTotal, g_agressao.direcao,
      g_volumeProfile.poc, g_volumeProfile.vah, g_volumeProfile.val,
      g_volumeProfile.zona, sinal_status,
      cfg.usar_agressao, cfg.usar_volume_profile,
      lucro_total_backtest  // Lucro total (apenas backtest)
   );
}

//+------------------------------------------------------------------+
//| Processa comandos do painel externo                              |
//+------------------------------------------------------------------+
void ProcessarComandosPainelExterno() {
   string comando = exportador.LerComando();

   if(comando == "")
      return;

   exportador.ProcessarComando(comando, cfg, cfg_original);
}

//+------------------------------------------------------------------+
//| Atualiza lucro do dia (com throttle adaptativo)                  |
//+------------------------------------------------------------------+
void AtualizarLucroDia(bool forcar = false) {
   static int ticks_desde_atualizacao = 0;
   bool is_tester = MQLInfoInteger(MQL_TESTER);

   if(!forcar) {
      if(is_tester) {
         // BACKTEST: Atualiza a cada 5 ticks para capturar mudanças rápidas
         ticks_desde_atualizacao++;
         if(ticks_desde_atualizacao < 5)
            return;
         ticks_desde_atualizacao = 0;
      } else {
         // LIVE: Throttle baseado em tempo real
         uint agora = GetTickCount();
         if((agora - ultima_atualizacao_lucro < 500) && agora > ultima_atualizacao_lucro)
            return;
         ultima_atualizacao_lucro = agora;
      }
   }

   // ⚠️ IMPORTANTE: AccountInfoDouble(ACCOUNT_BALANCE) NÃO atualiza em tempo real no Strategy Tester!
   // Solução: Calcular lucro manualmente usando HistoryDealGetDouble
   // Fonte: https://www.mql5.com/en/forum/234668

   // Calcula lucro realizado a partir do histórico de deals (funciona no Strategy Tester)
   lucro_realizado = CalcularLucroRealizadoHistorico();

   // Calcula lucro flutuante das posições abertas
   double lucro_flutuante = 0.0;
   for(int i = 0; i < PositionsTotal(); i++) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket)) {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol) {
            lucro_flutuante += PositionGetDouble(POSITION_PROFIT);
         }
      }
   }

   // Lucro do dia = realizado (trades fechados do dia) + flutuante (posições abertas)
   lucro_dia = lucro_realizado + lucro_flutuante;

   // Em BACKTEST, calcula também o lucro total acumulado (todo o histórico)
   if(MQLInfoInteger(MQL_TESTER)) {
      lucro_total_backtest = CalcularLucroTotalHistorico() + lucro_flutuante;
   }
}

//+------------------------------------------------------------------+
//| Calcula lucro realizado do histórico de deals (apenas do dia)    |
//| Usa DEAL_PROFIT diretamente - funciona em LIVE e BACKTEST        |
//+------------------------------------------------------------------+
double CalcularLucroRealizadoHistorico() {
   double lucro_total = 0.0;

   // Calcula início do dia atual (00:00:00)
   datetime agora = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(agora, dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   datetime inicio_do_dia = StructToTime(dt);

   // Seleciona histórico apenas do dia atual
   if(!HistorySelect(inicio_do_dia, agora)) {
      return 0.0;
   }

   int total_deals = HistoryDealsTotal();

   for(int i = 0; i < total_deals; i++) {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;

      ENUM_DEAL_TYPE dtype = (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);
      ENUM_DEAL_ENTRY dentry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
      string dsymbol = HistoryDealGetString(ticket, DEAL_SYMBOL);

      // Ignora balance e deals de outros símbolos
      if(dtype == DEAL_TYPE_BALANCE) continue;
      if(dsymbol != _Symbol) continue;

      // Apenas deals de saída (fechamento) tem lucro
      if(dentry == DEAL_ENTRY_OUT || dentry == DEAL_ENTRY_INOUT) {
         double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
         double commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
         double swap = HistoryDealGetDouble(ticket, DEAL_SWAP);

         lucro_total += profit + commission + swap;
      }
   }

   return lucro_total;
}

//+------------------------------------------------------------------+
//| Calcula lucro TOTAL do histórico (todo o backtest, sem filtro)   |
//| Usado apenas em BACKTEST para mostrar lucro acumulado total      |
//+------------------------------------------------------------------+
double CalcularLucroTotalHistorico() {
   double lucro = 0.0;

   // Seleciona TODO o histórico (desde o início)
   if(!HistorySelect(0, TimeCurrent())) {
      return 0.0;
   }

   int total_deals = HistoryDealsTotal();

   for(int i = 0; i < total_deals; i++) {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;

      ENUM_DEAL_TYPE dtype = (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);
      ENUM_DEAL_ENTRY dentry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
      string dsymbol = HistoryDealGetString(ticket, DEAL_SYMBOL);

      // Ignora balance e deals de outros símbolos
      if(dtype == DEAL_TYPE_BALANCE) continue;
      if(dsymbol != _Symbol) continue;

      // Apenas deals de saída (fechamento) tem lucro
      if(dentry == DEAL_ENTRY_OUT || dentry == DEAL_ENTRY_INOUT) {
         double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
         double commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
         double swap = HistoryDealGetDouble(ticket, DEAL_SWAP);

         lucro += profit + commission + swap;
      }
   }

   return lucro;
}

//+------------------------------------------------------------------+
//| Trailing Stop                                                    |
//+------------------------------------------------------------------+
void ApplyTrailingStop() {
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);

      if(PositionSelectByTicket(ticket)) {
         if(PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;

         double position_sl = PositionGetDouble(POSITION_SL);
         double position_tp = PositionGetDouble(POSITION_TP);
         ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

         if(type == POSITION_TYPE_BUY) {
            double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            double new_sl = bid - (cfg.trailing_pts * point);

            if((position_sl == 0 || new_sl > position_sl) && new_sl < bid) {
               if(!trade.PositionModify(ticket, new_sl, position_tp)) {
                  if(LogDetalhado >= LOG_DEBUG)
                     Print("[Trailing] Falha ao modificar BUY #", ticket, ": ", trade.ResultRetcodeDescription());
               }
            }
         }
         else if(type == POSITION_TYPE_SELL) {
            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double new_sl = ask + (cfg.trailing_pts * point);

            if((position_sl == 0 || new_sl < position_sl) && new_sl > ask) {
               if(!trade.PositionModify(ticket, new_sl, position_tp)) {
                  if(LogDetalhado >= LOG_DEBUG)
                     Print("[Trailing] Falha ao modificar SELL #", ticket, ": ", trade.ResultRetcodeDescription());
               }
            }
         }
      }
   }
}
//+------------------------------------------------------------------+
