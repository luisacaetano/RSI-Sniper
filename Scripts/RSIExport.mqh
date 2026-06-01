//+------------------------------------------------------------------+
//|                      RSIExport.mqh                               |
//|                                                                  |
//| Biblioteca de comunicação entre o EA e o painel Python           |
//| - Exporta dados em JSON para Common/Files                        |
//| - Lê comandos do painel (PAUSAR, FECHAR_TUDO, etc)               |
//| - Usa arquivos separados para BACKTEST e LIVE (evita conflito)   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025"
#property version   "1.00"

#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Configurações do EA em struct para facilitar passagem de dados   |
//| O painel pode modificar esses valores em tempo real              |
//+------------------------------------------------------------------+
struct SRSIConfig {
   bool   pausado;              // true = operações bloqueadas
   double lote;                 // tamanho da posição
   double sl;                   // stop loss em pontos
   double tp;                   // take profit em pontos
   bool   trailing;             // usar trailing stop?
   double trailing_pts;         // distância do trailing em pontos
   bool   usar_agressao;        // filtro de fluxo de ordens
   bool   usar_volume_profile;  // filtro de volume profile
};

class CRSIExport {
private:
   string arquivo_dados;
   string arquivo_comandos;
   datetime ultimo_comando_lido;
   string ultimo_comando_processado;
   int contador_export;
   int contador_erros;
   CTrade trade_fechar;  // Reutilizado para fechar posicoes

public:
   CRSIExport() {
      // Usa arquivos diferentes para BACKTEST vs LIVE (evita conflito)
      string sufixo = MQLInfoInteger(MQL_TESTER) ? "_BACKTEST" : "_LIVE";
      arquivo_dados = "rsi_data" + sufixo + ".json";
      arquivo_comandos = "rsi_commands" + sufixo + ".txt";

      ultimo_comando_lido = 0;
      ultimo_comando_processado = "";
      contador_export = 0;
      contador_erros = 0;
      trade_fechar.LogLevel(LOG_LEVEL_NO);  // Desabilita logs automaticos

      string caminho = TerminalInfoString(TERMINAL_COMMONDATA_PATH) + "\\Files\\";
      bool is_tester = MQLInfoInteger(MQL_TESTER);

      Print("========================================");
      Print("  RSI EXPORT - Configuracao de Arquivos");
      Print("========================================");
      Print("  Modo: ", is_tester ? "BACKTEST" : "LIVE");
      Print("  Pasta de dados: ", caminho);
      Print("  Arquivo de dados: ", arquivo_dados);
      Print("  Arquivo de comandos: ", arquivo_comandos);
      Print("========================================");

      // Remove arquivo antigo se existir
      if(FileIsExist(arquivo_dados, FILE_COMMON)) {
         if(!FileDelete(arquivo_dados, FILE_COMMON))
            Print("[AVISO] Nao foi possivel remover arquivo antigo: ", GetLastError());
      }

      // Cria arquivo inicial imediatamente para o painel detectar
      CriarArquivoInicial();
   }

   //+------------------------------------------------------------------+
   //| Cria arquivo inicial para o painel detectar                      |
   //+------------------------------------------------------------------+
   void CriarArquivoInicial() {
      int handle = FileOpen(arquivo_dados, FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ);

      if(handle == INVALID_HANDLE) {
         Print("[ERRO] Nao foi possivel criar arquivo de dados: ", GetLastError());
         return;
      }

      // Usa hora do servidor no backtest (acompanha tempo simulado)
      datetime agora = MQLInfoInteger(MQL_TESTER) ? TimeTradeServer() : TimeLocal();
      string timestamp_atual = TimeToString(agora, TIME_DATE|TIME_SECONDS);

      string json = "{\n";
      json += "  \"status\": \"INICIANDO\",\n";
      json += "  \"ativo\": \"" + _Symbol + "\",\n";
      json += "  \"posicoes\": 0,\n";
      json += "  \"lucro_dia\": 0.00,\n";
      json += "  \"rsi\": 0.00,\n";
      json += "  \"lote\": 1.00,\n";
      json += "  \"stoploss\": 200,\n";
      json += "  \"takeprofit\": 350,\n";
      json += "  \"usar_trailing\": true,\n";
      json += "  \"trailing_pontos\": 150,\n";
      json += "  \"ultimo_comando\": \"\",\n";
      json += "  \"saldo\": 0.00,\n";
      json += "  \"lucro_aberto\": 0.00,\n";
      json += "  \"agressao_compra\": 0.0,\n";
      json += "  \"agressao_venda\": 0.0,\n";
      json += "  \"agressao_vol\": 0,\n";
      json += "  \"agressao_direcao\": \"\",\n";
      json += "  \"vp_poc\": 0.00,\n";
      json += "  \"vp_vah\": 0.00,\n";
      json += "  \"vp_val\": 0.00,\n";
      json += "  \"vp_zona\": \"\",\n";
      json += "  \"sinal_status\": \"Inicializando...\",\n";
      json += "  \"usar_agressao\": false,\n";
      json += "  \"usar_volume_profile\": false,\n";
      json += "  \"logs\": [],\n";
      json += "  \"timestamp\": \"" + timestamp_atual + "\"\n";
      json += "}";

      FileWriteString(handle, json);
      FileFlush(handle);
      FileClose(handle);
   }

   //+------------------------------------------------------------------+
   //| Exporta dados para o painel Python                               |
   //+------------------------------------------------------------------+
   void ExportarDados(string status, string ativo, int posicoes,
                     double lucro_dia_valor, double rsi_atual,
                     double lote, double sl, double tp,
                     bool usar_trailing, double trailing_pts,
                     string &log_buffer[], int log_count,
                     // Novos parametros de monitoramento
                     double saldo = 0, double lucro_aberto = 0,
                     double agressao_compra = 0, double agressao_venda = 0,
                     double agressao_vol = 0, string agressao_direcao = "NEUTRO",
                     double vp_poc = 0, double vp_vah = 0, double vp_val = 0,
                     string vp_zona = "INDEFINIDO", string sinal_status = "Aguardando...",
                     bool usar_agressao = true, bool usar_volume_profile = true,
                     double lucro_total = 0) {  // Lucro total (apenas backtest)

      // Usa hora do servidor no backtest (acompanha tempo simulado)
      datetime agora = MQLInfoInteger(MQL_TESTER) ? TimeTradeServer() : TimeLocal();
      string timestamp_atual = TimeToString(agora, TIME_DATE|TIME_SECONDS);

      int handle = FileOpen(arquivo_dados, FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ);

      if(handle == INVALID_HANDLE) {
         if(contador_erros % 100 == 0)
            Print("[ERRO] Falha ao abrir arquivo de dados: ", GetLastError());
         contador_erros++;
         return;
      }

      string json = "{\n";
      json += "  \"status\": \"" + status + "\",\n";
      json += "  \"ativo\": \"" + ativo + "\",\n";
      json += "  \"posicoes\": " + IntegerToString(posicoes) + ",\n";
      json += "  \"lucro_dia\": " + DoubleToString(lucro_dia_valor, 2) + ",\n";
      json += "  \"rsi\": " + DoubleToString(rsi_atual, 2) + ",\n";
      json += "  \"lote\": " + DoubleToString(lote, 2) + ",\n";
      json += "  \"stoploss\": " + DoubleToString(sl, 0) + ",\n";
      json += "  \"takeprofit\": " + DoubleToString(tp, 0) + ",\n";
      json += "  \"usar_trailing\": " + (usar_trailing ? "true" : "false") + ",\n";
      json += "  \"trailing_pontos\": " + DoubleToString(trailing_pts, 0) + ",\n";
      json += "  \"ultimo_comando\": \"" + ultimo_comando_processado + "\",\n";
      // Novos campos de monitoramento
      json += "  \"saldo\": " + DoubleToString(saldo, 2) + ",\n";
      json += "  \"lucro_aberto\": " + DoubleToString(lucro_aberto, 2) + ",\n";
      json += "  \"agressao_compra\": " + DoubleToString(agressao_compra * 100, 1) + ",\n";
      json += "  \"agressao_venda\": " + DoubleToString(agressao_venda * 100, 1) + ",\n";
      json += "  \"agressao_vol\": " + DoubleToString(agressao_vol, 0) + ",\n";
      json += "  \"agressao_direcao\": \"" + agressao_direcao + "\",\n";
      json += "  \"vp_poc\": " + DoubleToString(vp_poc, 2) + ",\n";
      json += "  \"vp_vah\": " + DoubleToString(vp_vah, 2) + ",\n";
      json += "  \"vp_val\": " + DoubleToString(vp_val, 2) + ",\n";
      json += "  \"vp_zona\": \"" + vp_zona + "\",\n";
      json += "  \"sinal_status\": \"" + sinal_status + "\",\n";
      json += "  \"usar_agressao\": " + (usar_agressao ? "true" : "false") + ",\n";
      json += "  \"usar_volume_profile\": " + (usar_volume_profile ? "true" : "false") + ",\n";

      // Lucro total (apenas em backtest)
      if(MQLInfoInteger(MQL_TESTER)) {
         json += "  \"lucro_total\": " + DoubleToString(lucro_total, 2) + ",\n";
      }

      // Array de logs (últimas N mensagens)
      json += "  \"logs\": [\n";
      for(int i = 0; i < log_count; i++) {
         string virgula = (i < log_count - 1) ? "," : "";
         // Escapa caracteres especiais para JSON valido
         string linha = log_buffer[i];
         StringReplace(linha, "\\", "\\\\");  // Escapa barras primeiro
         StringReplace(linha, "\"", "\\\"");  // Escapa aspas corretamente
         StringReplace(linha, "\n", "\\n");   // Escapa quebras de linha
         StringReplace(linha, "\r", "\\r");   // Escapa retorno de carro
         StringReplace(linha, "\t", "\\t");   // Escapa tabs
         json += "    \"" + linha + "\"" + virgula + "\n";
      }
      json += "  ],\n";

      json += "  \"timestamp\": \"" + timestamp_atual + "\"\n";
      json += "}";

      FileWriteString(handle, json);
      FileFlush(handle);
      FileClose(handle);

      contador_export++;
   }

   //+------------------------------------------------------------------+
   //| Le comando do painel Python                                      |
   //+------------------------------------------------------------------+
   string LerComando() {
      if(!FileIsExist(arquivo_comandos, FILE_COMMON))
         return "";

      int handle = FileOpen(arquivo_comandos, FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_WRITE|FILE_SHARE_READ);

      if(handle == INVALID_HANDLE)
         return "";

      string conteudo = "";
      while(!FileIsEnding(handle)) {
         conteudo += FileReadString(handle) + "\n";
      }
      FileClose(handle);

      string linhas[];
      int num_linhas = StringSplit(conteudo, '\n', linhas);

      if(num_linhas < 2) {
         FileDelete(arquivo_comandos, FILE_COMMON);
         return "";
      }

      string comando = linhas[0];
      string timestamp_str = linhas[1];

      StringTrimLeft(comando);
      StringTrimRight(comando);
      StringTrimLeft(timestamp_str);
      StringTrimRight(timestamp_str);

      if(comando == "" || timestamp_str == "") {
         FileDelete(arquivo_comandos, FILE_COMMON);
         return "";
      }

      datetime timestamp_comando = StringToTime(timestamp_str);

      if(timestamp_comando <= ultimo_comando_lido)
         return "";

      ultimo_comando_lido = timestamp_comando;

      FileDelete(arquivo_comandos, FILE_COMMON);

      return comando;
   }

   //+------------------------------------------------------------------+
   //| Processa comando recebido (versao com struct)                    |
   //+------------------------------------------------------------------+
   bool ProcessarComando(string comando, SRSIConfig &config, const SRSIConfig &config_orig) {

      if(comando == "")
         return false;

      bool sucesso = false;

      if(comando == "PAUSAR") {
         config.pausado = !config.pausado;
         if(config.pausado) {
            Print("[PAUSADO] ROBO PAUSADO | Operacoes bloqueadas");
         } else {
            Print("[ATIVO] ROBO RETOMADO | Operacoes ativas");
         }
         ultimo_comando_processado = config.pausado ? "PAUSADO" : "RETOMADO";
         sucesso = true;
      }

      else if(comando == "FECHAR_TUDO") {
         Print("[ALERTA] FECHANDO TODAS AS POSICOES...");
         FecharTodasPosicoes();
         Print("[OK] Todas as posicoes foram fechadas");
         ultimo_comando_processado = "POSICOES FECHADAS";
         sucesso = true;
      }

      else if(StringFind(comando, "SALVAR_CONFIG:") == 0) {
         string parametros = StringSubstr(comando, 14);
         string valores[];
         int total = StringSplit(parametros, ',', valores);

         if(total >= 4) {
            config.sl = StringToDouble(valores[0]);
            config.tp = StringToDouble(valores[1]);
            config.trailing_pts = StringToDouble(valores[2]);
            config.trailing = (valores[3] == "1");

            // Filtros de confirmação (parâmetros 5 e 6)
            if(total >= 6) {
               config.usar_agressao = (valores[4] == "1");
               config.usar_volume_profile = (valores[5] == "1");
            }

            // Lote incluído no comando (7º parâmetro)
            if(total >= 7) {
               config.lote = StringToDouble(valores[6]);
            }

            Print("[CONFIG] CONFIGURACOES SALVAS:");
            Print("    Lote: ", DoubleToString(config.lote, 2), " | SL: ", config.sl, " pts | TP: ", config.tp, " pts");
            Print("    Trailing: ", config.trailing ? "ON (" + DoubleToString(config.trailing_pts, 0) + " pts)" : "OFF");
            Print("    Agressao: ", config.usar_agressao ? "ON" : "OFF", " | Volume Profile: ", config.usar_volume_profile ? "ON" : "OFF");
            ultimo_comando_processado = "CONFIG SALVA";
            sucesso = true;
         }
      }

      else if(comando == "RESETAR_CONFIG") {
         config.lote = config_orig.lote;
         config.sl = config_orig.sl;
         config.tp = config_orig.tp;
         config.trailing = config_orig.trailing;
         config.trailing_pts = config_orig.trailing_pts;
         config.usar_agressao = config_orig.usar_agressao;
         config.usar_volume_profile = config_orig.usar_volume_profile;

         Print("[RESET] CONFIGURACOES RESETADAS para valores originais");
         ultimo_comando_processado = "RESETADO";
         sucesso = true;
      }

      else if(comando == "PARAR_EA") {
         Print("════════════════════════════════════════");
         Print("  EA REMOVIDO PELO PAINEL");
         Print("════════════════════════════════════════");
         ultimo_comando_processado = "EA PARADO";
         sucesso = true;
         // Remove o EA do gráfico
         ExpertRemove();
      }

      return sucesso;
   }

   //+------------------------------------------------------------------+
   //| Fecha todas as posicoes do simbolo atual                         |
   //+------------------------------------------------------------------+
   void FecharTodasPosicoes() {
      int fechadas = 0;

      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         ulong ticket = PositionGetTicket(i);
         if(PositionSelectByTicket(ticket)) {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol) {
               if(trade_fechar.PositionClose(ticket)) {
                  fechadas++;
                  Print("   Posicao #", ticket, " fechada");
               }
            }
         }
      }

      if(fechadas > 0)
         Print("  Total de posicoes fechadas: ", fechadas);
      else
         Print("  Nenhuma posicao encontrada para fechar");
   }
};
