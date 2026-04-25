//+------------------------------------------------------------------+
//|                                       TrendFollower_H4_M15.mq5   |
//|     Multi-symbol: H4 bias + M15 entry + ATR SL + R management    |
//+------------------------------------------------------------------+
#property strict
#property version   "1.22"

#include <Trade/Trade.mqh>
CTrade trade;

//============================
// Inputs
//============================
input ulong   MagicNumber                 = 260311;
input double  RiskPercent                 = 0.50;   // Risk per trade in %
input int     MaxTradesPerDay             = 4;
input int     MaxOpenTrades               = 4;
input bool    OnePositionAtATime          = true;

input string  SymbolsToTrade              = "AUDNZD,GBPUSD,NZDUSD,EURUSD,AUDCHF"; // comma-separated
input bool    IncludeChartSymbol          = true;
input int     ScanTimerSeconds            = 2;

input ENUM_TIMEFRAMES TrendTF             = PERIOD_H4;
input ENUM_TIMEFRAMES EntryTF             = PERIOD_M15;

input int     EntryFastMAPeriod           = 20;     // M15 EMA20
input int     EntryMidMAPeriod            = 50;     // M15 EMA50
input int     TrendMAPeriod50             = 50;     // H4 EMA50
input int     TrendMAPeriod200            = 200;    // H4 EMA200
input ENUM_MA_METHOD MAMethod             = MODE_EMA;

input int     ATRPeriod                   = 14;
input double  ATRStopMultiplierH4         = 1.5;    // SL = swing +/- (H4 ATR * multiplier)

input int     SwingLookbackBars           = 6;      // M15 swing for SL
input int     H4StructureLookbackBars     = 12;     // H4 swing-break structure check
input int     PullbackLookbackBars        = 8;
input double  MinPullbackATRMultiplier    = 0.5;    // min pullback depth = ATR(M15) * this
input double  MaxPullbackH4ATRMultiplier  = 1.5;    // max pullback depth = ATR(H4) * this

input bool    UsePartialTP                = true;
input double  TP1_RR                      = 1.0;
input double  TP2_RR                      = 2.0;
input double  TP3_RR                      = 3.0;
input double  TP1_ClosePercent            = 30.0;
input double  TP2_ClosePercent            = 50.0;
input bool    MoveToBEAt2R                = true;
input double  BreakEvenLockPips           = 0.0;
input bool    UseATRTrailingAfterTP3      = true;
input double  ATRTrailMultiplier          = 1.0;

input bool    UseDailySafety              = true;
input double  MaxDailyLossPercent         = 2.0;
input int     MaxConsecutiveLossesPerDay  = 3;

input bool    UseCorrelationFilter        = true;
input int     MaxCurrencyExposure         = 2;      // max same-direction exposure per currency
input bool    UseOpenRiskAdjustedBalance  = true;   // size new trade from balance minus open SL risk
input bool    UseBasketRiskLimit          = true;
input double  MaxBasketFloatingLossPercent = 2.0;   // correlated basket floating loss cap in %
input bool    UseLossCooldown             = true;
input int     LossCooldownHours           = 12;
input string  RiskStateFilePrefix         = "TrandAtrEA";

input double  MaxSpreadPoints             = 40;
input bool    DebugMode                   = true;

//============================
// Symbol contexts
//============================
#define MAX_SYMBOLS 32

struct SymbolContext
{
   string   symbol;
   int      h4MA50;
   int      h4MA200;
   int      h4ATR;
   int      m15MA20;
   int      m15MA50;
   int      m15ATR;
   datetime lastEntryBarTime;
   bool     initialized;
};

SymbolContext ctx[MAX_SYMBOLS];
int ctxCount = 0;

// Position management memory (per ticket)
ulong  managedTickets[512];
double initialEntryByTicket[512];
double initialRiskByTicket[512];
double initialVolumeByTicket[512];
bool   tp1DoneByTicket[512];
bool   tp2DoneByTicket[512];
int    managedCount = 0;
datetime lastFridayCloseActionWAT = 0;

//============================
// Prototypes
//============================
void   ProcessAllSymbols();
void   ProcessSymbol(const int idx);
int    BuildSymbolList();
bool   InitSymbolContext(const int idx, const string symbol);
void   ReleaseSymbolContext(const int idx);
int    FindContextIndex(const string symbol);
string Trim(const string s);
bool   IsTrackedSymbol(const string symbol);
bool   IsSymbolExplicitlyAllowed(const string symbol);

bool   TradingAllowedForSymbol(const string symbol);
bool   IsNewBar(SymbolContext &c, ENUM_TIMEFRAMES tf);
int    GetH4TrendDirection(const int idx);
bool   BuySignalM15(const int idx);
bool   SellSignalM15(const int idx);

void   OpenTrade(const int idx, ENUM_ORDER_TYPE orderType);
bool   CalculateSLTP(const int idx, ENUM_ORDER_TYPE orderType, const double entryPrice, double &stopLoss, double &takeProfit);
double CalculatePositionSize(const string symbol, const double slDistancePrice);
double CalculateOpenRiskMoney();
double CalculatePositionRiskMoney(const string symbol, const long posType, const double entryPrice, const double stopLoss, const double volume);
double MoneyAtRiskPerLot(const string symbol, const double slDistancePrice);

double NormalizePrice(const string symbol, const double price);
double PipSize(const string symbol);
double NormalizeVolume(const string symbol, const double rawVolume);
double TruncateToTwoDecimals(const double value);

void   ManageOpenPositions();
int    FindManagedIndex(const ulong ticket);
void   EnsureTicketRegistered(const ulong ticket, const double entryPrice, const double slPrice);
bool   ClosePartialByTicket(const ulong ticket, const long posType, const double closeVolume);

bool   IsDailyLossLimitReached(const string symbol);
int    GetTodayConsecutiveLosses(const string symbol);
int    GetTodayTradeCount(const string symbol);
bool   HasOpenPositionForSymbol(const string symbol);
bool   IsPositionAtBreakevenOrBetter(const long posType, const double entryPrice, const double stopLoss, const double point);
int    CountOpenTradesExcludingBreakeven();
bool   IsFridayCloseWindowWAT();
void   CloseFridayPositions();
bool   GetSymbolCurrencies(const string symbol, string &baseCurrency, string &quoteCurrency);
string CurrencyExposureKey(const string currency, const int direction);
string PrimaryBasketKey(const string symbol, const ENUM_ORDER_TYPE orderType);
bool   GetOrderBasketKeys(const string symbol, const ENUM_ORDER_TYPE orderType, string &baseBasketKey, string &quoteBasketKey);
int    PositionCurrencyDirection(const string symbol, const long posType, const string currency);
bool   CorrelationExposureAllows(const string symbol, const ENUM_ORDER_TYPE orderType);
int    CountCurrencyExposure(const string currency, const int direction);
bool   BasketAllowsFreshEntry(const string symbol, const ENUM_ORDER_TYPE orderType);
bool   BasketKeyAllowsFreshEntry(const string symbol, const string basketKey);
double BasketFloatingPnl(const string basketKey);
bool   PositionBelongsToBasket(const string symbol, const long posType, const string basketKey);
bool   IsBasketLocked(const string basketKey);
void   RecordBasketLock(const string basketKey, const datetime lockTime, const string reason);
bool   IsLossCooldownActive(const string symbol, const string basketKey);
void   RecordLossCooldown(const string symbol, const string basketKey, const datetime lossTime, const double pnl);
string BasketLockFileName();
string LossCooldownFileName();
void   OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result);

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber((int)MagicNumber);

   ArrayInitialize(managedTickets, 0);
   ArrayInitialize(initialEntryByTicket, 0.0);
   ArrayInitialize(initialRiskByTicket, 0.0);
   ArrayInitialize(initialVolumeByTicket, 0.0);
   ArrayInitialize(tp1DoneByTicket, false);
   ArrayInitialize(tp2DoneByTicket, false);

   int built = BuildSymbolList();
   if(built <= 0)
   {
      Print("No valid symbols configured in SymbolsToTrade.");
      return(INIT_FAILED);
   }

   for(int i = 0; i < ctxCount; i++)
   {
      if(!InitSymbolContext(i, ctx[i].symbol))
      {
         Print("Failed to initialize symbol context for ", ctx[i].symbol);
         return(INIT_FAILED);
      }
   }

   if(ScanTimerSeconds > 0)
      EventSetTimer(ScanTimerSeconds);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   for(int i = 0; i < ctxCount; i++)
      ReleaseSymbolContext(i);
}

//+------------------------------------------------------------------+
//| Expert tick                                                      |
//+------------------------------------------------------------------+
void OnTick()
{
   CloseFridayPositions();
   ManageOpenPositions();
   ProcessAllSymbols();
}

//+------------------------------------------------------------------+
//| Timer                                                            |
//+------------------------------------------------------------------+
void OnTimer()
{
   CloseFridayPositions();
   ManageOpenPositions();
   ProcessAllSymbols();
}

//+------------------------------------------------------------------+
//| Build symbol list from input                                     |
//+------------------------------------------------------------------+
int BuildSymbolList()
{
   ctxCount = 0;

   // Only process the chart symbol when it is explicitly listed.
   if(IncludeChartSymbol && IsSymbolExplicitlyAllowed(_Symbol))
   {
      ctx[ctxCount].symbol = _Symbol;
      ctx[ctxCount].initialized = false;
      ctxCount++;
   }

   string list = SymbolsToTrade;
   string parts[];
   int n = StringSplit(list, ',', parts);

   for(int i = 0; i < n && ctxCount < MAX_SYMBOLS; i++)
   {
      string s = Trim(parts[i]);
      if(s == "")
         continue;

      if(FindContextIndex(s) >= 0)
         continue;

      ctx[ctxCount].symbol = s;
      ctx[ctxCount].initialized = false;
      ctxCount++;
   }

   return ctxCount;
}

//+------------------------------------------------------------------+
//| Init one symbol context                                          |
//+------------------------------------------------------------------+
bool InitSymbolContext(const int idx, const string symbol)
{
   if(idx < 0 || idx >= MAX_SYMBOLS)
      return false;

   if(!SymbolSelect(symbol, true))
   {
      Print("SymbolSelect failed for ", symbol);
      return false;
   }

   ctx[idx].h4MA50  = iMA(symbol, TrendTF, TrendMAPeriod50,  0, MAMethod, PRICE_CLOSE);
   ctx[idx].h4MA200 = iMA(symbol, TrendTF, TrendMAPeriod200, 0, MAMethod, PRICE_CLOSE);
   ctx[idx].h4ATR   = iATR(symbol, TrendTF, ATRPeriod);

   ctx[idx].m15MA20 = iMA(symbol, EntryTF, EntryFastMAPeriod, 0, MAMethod, PRICE_CLOSE);
   ctx[idx].m15MA50 = iMA(symbol, EntryTF, EntryMidMAPeriod,  0, MAMethod, PRICE_CLOSE);
   ctx[idx].m15ATR  = iATR(symbol, EntryTF, ATRPeriod);

   ctx[idx].lastEntryBarTime = 0;

   if(ctx[idx].h4MA50 == INVALID_HANDLE || ctx[idx].h4MA200 == INVALID_HANDLE || ctx[idx].h4ATR == INVALID_HANDLE ||
      ctx[idx].m15MA20 == INVALID_HANDLE || ctx[idx].m15MA50 == INVALID_HANDLE || ctx[idx].m15ATR == INVALID_HANDLE)
   {
      Print("Failed to create indicator handles for ", symbol);
      return false;
   }

   ctx[idx].initialized = true;
   return true;
}

//+------------------------------------------------------------------+
//| Release one symbol context                                       |
//+------------------------------------------------------------------+
void ReleaseSymbolContext(const int idx)
{
   if(idx < 0 || idx >= ctxCount)
      return;

   if(ctx[idx].h4MA50  != INVALID_HANDLE) IndicatorRelease(ctx[idx].h4MA50);
   if(ctx[idx].h4MA200 != INVALID_HANDLE) IndicatorRelease(ctx[idx].h4MA200);
   if(ctx[idx].h4ATR   != INVALID_HANDLE) IndicatorRelease(ctx[idx].h4ATR);
   if(ctx[idx].m15MA20 != INVALID_HANDLE) IndicatorRelease(ctx[idx].m15MA20);
   if(ctx[idx].m15MA50 != INVALID_HANDLE) IndicatorRelease(ctx[idx].m15MA50);
   if(ctx[idx].m15ATR  != INVALID_HANDLE) IndicatorRelease(ctx[idx].m15ATR);

   ctx[idx].h4MA50 = ctx[idx].h4MA200 = ctx[idx].h4ATR = INVALID_HANDLE;
   ctx[idx].m15MA20 = ctx[idx].m15MA50 = ctx[idx].m15ATR = INVALID_HANDLE;
   ctx[idx].initialized = false;
}

//+------------------------------------------------------------------+
//| Process all symbols                                              |
//+------------------------------------------------------------------+
void ProcessAllSymbols()
{
   if(IsFridayCloseWindowWAT())
      return;

   for(int i = 0; i < ctxCount; i++)
      ProcessSymbol(i);
}

//+------------------------------------------------------------------+
//| Friday 9 PM WAT close window                                     |
//+------------------------------------------------------------------+
bool IsFridayCloseWindowWAT()
{
   datetime watNow = TimeGMT() + 3600; // WAT = UTC+1 all year
   MqlDateTime watStruct;
   TimeToStruct(watNow, watStruct);

   if(watStruct.day_of_week != 5)
      return false;

   return (watStruct.hour >= 21);
}

//+------------------------------------------------------------------+
//| Close all EA positions every Friday from 9 PM WAT                |
//+------------------------------------------------------------------+
void CloseFridayPositions()
{
   if(!IsFridayCloseWindowWAT())
      return;

   datetime watNow = TimeGMT() + 3600;
   datetime currentMinuteWAT = watNow - (watNow % 60);
   if(lastFridayCloseActionWAT == currentMinuteWAT)
      return;

   lastFridayCloseActionWAT = currentMinuteWAT;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      long magic = PositionGetInteger(POSITION_MAGIC);

      if((ulong)magic != MagicNumber)
         continue;
      if(!IsTrackedSymbol(symbol))
         continue;

      if(!trade.PositionClose(ticket))
      {
         Print("[", symbol, "] Friday close failed ticket=", ticket,
               " retcode=", trade.ResultRetcode(), " | ", trade.ResultRetcodeDescription());
      }
      else if(DebugMode)
      {
         Print("[", symbol, "] Closed for Friday 9PM WAT. ticket=", ticket);
      }
   }
}

//+------------------------------------------------------------------+
//| Process one symbol                                               |
//+------------------------------------------------------------------+
void ProcessSymbol(const int idx)
{
   if(idx < 0 || idx >= ctxCount || !ctx[idx].initialized)
      return;

   string symbol = ctx[idx].symbol;

   if(!IsSymbolExplicitlyAllowed(symbol))
   {
      if(DebugMode) Print("[", symbol, "] Skipped because it is not in SymbolsToTrade.");
      return;
   }

   if(!IsNewBar(ctx[idx], EntryTF))
      return;

   if(!TradingAllowedForSymbol(symbol))
      return;

   if(UseDailySafety && IsDailyLossLimitReached(symbol))
   {
      if(DebugMode) Print("[", symbol, "] Daily loss cap reached.");
      return;
   }

   if(UseDailySafety && GetTodayConsecutiveLosses(symbol) >= MaxConsecutiveLossesPerDay)
   {
      if(DebugMode) Print("[", symbol, "] Consecutive loss cap reached.");
      return;
   }

   if(GetTodayTradeCount(symbol) >= MaxTradesPerDay)
   {
      if(DebugMode) Print("[", symbol, "] Max trades reached for today.");
      return;
   }

   int activeTrades = CountOpenTradesExcludingBreakeven();
   if(activeTrades >= MaxOpenTrades)
   {
      if(DebugMode) Print("[", symbol, "] Max open trades reached: ", activeTrades, "/", MaxOpenTrades);
      return;
   }

   if(OnePositionAtATime && HasOpenPositionForSymbol(symbol))
   {
      if(DebugMode) Print("[", symbol, "] Position already open.");
      return;
   }

   MqlTick t;
   if(!SymbolInfoTick(symbol, t))
      return;

   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      return;

   double spreadPoints = (t.ask - t.bid) / point;
   if(spreadPoints > MaxSpreadPoints)
   {
      if(DebugMode) Print("[", symbol, "] Spread too high: ", spreadPoints);
      return;
   }

   int trend = GetH4TrendDirection(idx);

   if(trend == 1 && BuySignalM15(idx))
      OpenTrade(idx, ORDER_TYPE_BUY);
   else if(trend == -1 && SellSignalM15(idx))
      OpenTrade(idx, ORDER_TYPE_SELL);
   else if(DebugMode)
      Print("[", symbol, "] No valid entry. Bias=", trend);
}

//+------------------------------------------------------------------+
//| Find context index by symbol                                     |
//+------------------------------------------------------------------+
int FindContextIndex(const string symbol)
{
   for(int i = 0; i < ctxCount; i++)
      if(ctx[i].symbol == symbol)
         return i;
   return -1;
}

//+------------------------------------------------------------------+
//| Is tracked symbol                                                |
//+------------------------------------------------------------------+
bool IsTrackedSymbol(const string symbol)
{
   return (FindContextIndex(symbol) >= 0);
}

//+------------------------------------------------------------------+
//| Is symbol explicitly listed in SymbolsToTrade                    |
//+------------------------------------------------------------------+
bool IsSymbolExplicitlyAllowed(const string symbol)
{
   string target = Trim(symbol);
   if(target == "")
      return false;

   string parts[];
   int count = StringSplit(SymbolsToTrade, ',', parts);

   for(int i = 0; i < count; i++)
   {
      if(Trim(parts[i]) == target)
         return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Trim spaces                                                      |
//+------------------------------------------------------------------+
string Trim(const string s)
{
   string out = s;
   StringTrimLeft(out);
   StringTrimRight(out);
   return out;
}

//+------------------------------------------------------------------+
//| Check trading allowed                                            |
//+------------------------------------------------------------------+
bool TradingAllowedForSymbol(const string symbol)
{
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return false;
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      return false;

   long trade_mode = SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
   if(trade_mode != SYMBOL_TRADE_MODE_FULL)
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| Detect new bar on timeframe                                      |
//+------------------------------------------------------------------+
bool IsNewBar(SymbolContext &c, ENUM_TIMEFRAMES tf)
{
   datetime times[];
   if(CopyTime(c.symbol, tf, 0, 2, times) < 2)
      return false;

   ArraySetAsSeries(times, true);

   if(times[0] != c.lastEntryBarTime)
   {
      c.lastEntryBarTime = times[0];
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Get H4 trend direction                                           |
//+------------------------------------------------------------------+
int GetH4TrendDirection(const int idx)
{
   string symbol = ctx[idx].symbol;
   int needBars = MathMax(H4StructureLookbackBars + 6, 20);

   MqlRates rates[];
   double ma50[];
   double ma200[];

   if(CopyRates(symbol, TrendTF, 1, needBars, rates) < needBars)
      return 0;
   if(CopyBuffer(ctx[idx].h4MA50,  0, 1, needBars, ma50) < needBars)
      return 0;
   if(CopyBuffer(ctx[idx].h4MA200, 0, 1, needBars, ma200) < needBars)
      return 0;

   ArraySetAsSeries(rates, true);
   ArraySetAsSeries(ma50, true);
   ArraySetAsSeries(ma200, true);

   double close1 = rates[0].close;
   double high1  = rates[0].high;
   double low1   = rates[0].low;
   double high2  = rates[1].high;
   double low2   = rates[1].low;

   double recentSwingHigh = rates[1].high;
   double recentSwingLow  = rates[1].low;

   for(int i = 1; i <= H4StructureLookbackBars && i < needBars; i++)
   {
      if(rates[i].high > recentSwingHigh)
         recentSwingHigh = rates[i].high;
      if(rates[i].low < recentSwingLow)
         recentSwingLow = rates[i].low;
   }

   bool maBull = (ma50[0] > ma200[0]) && (close1 > ma50[0]);
   bool maBear = (ma50[0] < ma200[0]) && (close1 < ma50[0]);

   bool structureBull = (low1 > low2) || (close1 > recentSwingHigh);
   bool structureBear = (high1 < high2) || (close1 < recentSwingLow);

   if(maBull && structureBull)
      return 1;
   if(maBear && structureBear)
      return -1;

   return 0;
}

//+------------------------------------------------------------------+
//| Buy signal on M15                                                |
//+------------------------------------------------------------------+
bool BuySignalM15(const int idx)
{
   string symbol = ctx[idx].symbol;
   int needBars = MathMax(PullbackLookbackBars + 4, 15);

   MqlRates rates[];
   double ma20[];
   double ma50[];
   double atrM15[];
   double atrH4[];

   if(CopyRates(symbol, EntryTF, 1, needBars, rates) < needBars) return false;
   if(CopyBuffer(ctx[idx].m15MA20, 0, 1, needBars, ma20) < needBars) return false;
   if(CopyBuffer(ctx[idx].m15MA50, 0, 1, needBars, ma50) < needBars) return false;
   if(CopyBuffer(ctx[idx].m15ATR,  0, 1, 3, atrM15) < 3) return false;
   if(CopyBuffer(ctx[idx].h4ATR,   0, 1, 3, atrH4) < 3) return false;

   ArraySetAsSeries(rates, true);
   ArraySetAsSeries(ma20, true);
   ArraySetAsSeries(ma50, true);
   ArraySetAsSeries(atrM15, true);
   ArraySetAsSeries(atrH4, true);

   double close1 = rates[0].close;
   double open1  = rates[0].open;
   double low1   = rates[0].low;

   double prevHigh = rates[1].high;

   bool pullbackTouch = (low1 <= ma20[0]) || (low1 <= ma50[0]);
   bool candleBullish = (close1 > open1);
   bool breakoutConf  = (close1 > prevHigh);
   bool aboveMA50     = (close1 > ma50[0]);

   double recentHigh = rates[1].high;
   for(int i = 1; i <= PullbackLookbackBars && i < needBars; i++)
      if(rates[i].high > recentHigh)
         recentHigh = rates[i].high;

   double pullbackDepth = recentHigh - low1;
   double minDepth = atrM15[0] * MinPullbackATRMultiplier;
   double maxDepth = atrH4[0]  * MaxPullbackH4ATRMultiplier;
   bool depthOk = (pullbackDepth >= minDepth && pullbackDepth <= maxDepth);

   if(DebugMode)
   {
      Print("[", symbol, "] BUY CHECK | touch=", pullbackTouch,
            " bullish=", candleBullish,
            " break=", breakoutConf,
            " aboveMA50=", aboveMA50,
            " depthOk=", depthOk,
            " depth=", pullbackDepth);
   }

   return (pullbackTouch && candleBullish && breakoutConf && aboveMA50 && depthOk);
}

//+------------------------------------------------------------------+
//| Sell signal on M15                                               |
//+------------------------------------------------------------------+
bool SellSignalM15(const int idx)
{
   string symbol = ctx[idx].symbol;
   int needBars = MathMax(PullbackLookbackBars + 4, 15);

   MqlRates rates[];
   double ma20[];
   double ma50[];
   double atrM15[];
   double atrH4[];

   if(CopyRates(symbol, EntryTF, 1, needBars, rates) < needBars) return false;
   if(CopyBuffer(ctx[idx].m15MA20, 0, 1, needBars, ma20) < needBars) return false;
   if(CopyBuffer(ctx[idx].m15MA50, 0, 1, needBars, ma50) < needBars) return false;
   if(CopyBuffer(ctx[idx].m15ATR,  0, 1, 3, atrM15) < 3) return false;
   if(CopyBuffer(ctx[idx].h4ATR,   0, 1, 3, atrH4) < 3) return false;

   ArraySetAsSeries(rates, true);
   ArraySetAsSeries(ma20, true);
   ArraySetAsSeries(ma50, true);
   ArraySetAsSeries(atrM15, true);
   ArraySetAsSeries(atrH4, true);

   double close1 = rates[0].close;
   double open1  = rates[0].open;
   double high1  = rates[0].high;

   double prevLow = rates[1].low;

   bool pullbackTouch = (high1 >= ma20[0]) || (high1 >= ma50[0]);
   bool candleBearish = (close1 < open1);
   bool breakoutConf  = (close1 < prevLow);
   bool belowMA50     = (close1 < ma50[0]);

   double recentLow = rates[1].low;
   for(int i = 1; i <= PullbackLookbackBars && i < needBars; i++)
      if(rates[i].low < recentLow)
         recentLow = rates[i].low;

   double pullbackDepth = high1 - recentLow;
   double minDepth = atrM15[0] * MinPullbackATRMultiplier;
   double maxDepth = atrH4[0]  * MaxPullbackH4ATRMultiplier;
   bool depthOk = (pullbackDepth >= minDepth && pullbackDepth <= maxDepth);

   if(DebugMode)
   {
      Print("[", symbol, "] SELL CHECK | touch=", pullbackTouch,
            " bearish=", candleBearish,
            " break=", breakoutConf,
            " belowMA50=", belowMA50,
            " depthOk=", depthOk,
            " depth=", pullbackDepth);
   }

   return (pullbackTouch && candleBearish && breakoutConf && belowMA50 && depthOk);
}

//+------------------------------------------------------------------+
//| Open trade                                                       |
//+------------------------------------------------------------------+
void OpenTrade(const int idx, ENUM_ORDER_TYPE orderType)
{
   string symbol = ctx[idx].symbol;

   string basketKey = PrimaryBasketKey(symbol, orderType);
   string quoteBasketKey = "";
   GetOrderBasketKeys(symbol, orderType, basketKey, quoteBasketKey);

   if(UseLossCooldown && (IsLossCooldownActive(symbol, basketKey) || IsLossCooldownActive(symbol, quoteBasketKey)))
   {
      if(DebugMode) Print("[", symbol, "] Loss cooldown active for basket ", basketKey, " / ", quoteBasketKey, ".");
      return;
   }

   if(UseCorrelationFilter && !CorrelationExposureAllows(symbol, orderType))
      return;

   if(UseBasketRiskLimit && !BasketAllowsFreshEntry(symbol, orderType))
      return;

   MqlTick t;
   if(!SymbolInfoTick(symbol, t))
      return;

   double entryPrice = (orderType == ORDER_TYPE_BUY) ? t.ask : t.bid;
   double stopLoss   = 0.0;
   double takeProfit = 0.0;

   if(!CalculateSLTP(idx, orderType, entryPrice, stopLoss, takeProfit))
   {
      if(DebugMode) Print("[", symbol, "] Failed to calculate SL/TP.");
      return;
   }

   double slDistance = MathAbs(entryPrice - stopLoss);
   if(slDistance <= 0.0)
      return;

   double volume = CalculatePositionSize(symbol, slDistance);
   if(volume <= 0.0)
      return;

   bool ok = false;

   if(orderType == ORDER_TYPE_BUY)
      ok = trade.Buy(volume, symbol, t.ask, stopLoss, takeProfit, "TrendATR BUY");
   else
      ok = trade.Sell(volume, symbol, t.bid, stopLoss, takeProfit, "TrendATR SELL");

   if(DebugMode)
   {
      if(ok)
         Print("[", symbol, "] Trade opened ", (orderType == ORDER_TYPE_BUY ? "BUY" : "SELL"), " vol=", volume, " SL=", stopLoss);
      else
         Print("[", symbol, "] Order failed retcode=", trade.ResultRetcode(), " | ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Calculate SL and TP                                              |
//+------------------------------------------------------------------+
bool CalculateSLTP(const int idx, ENUM_ORDER_TYPE orderType, const double entryPrice, double &stopLoss, double &takeProfit)
{
   string symbol = ctx[idx].symbol;

   MqlRates rates[];
   double atrH4Val[];

   int needBars = MathMax(SwingLookbackBars + 2, 10);

   if(CopyRates(symbol, EntryTF, 1, needBars, rates) < needBars)
      return false;
   if(CopyBuffer(ctx[idx].h4ATR, 0, 1, 2, atrH4Val) < 2)
      return false;

   ArraySetAsSeries(rates, true);
   ArraySetAsSeries(atrH4Val, true);

   double swingLow = rates[0].low;
   double swingHigh = rates[0].high;

   for(int i = 0; i < SwingLookbackBars && i < needBars; i++)
   {
      if(rates[i].low < swingLow)   swingLow = rates[i].low;
      if(rates[i].high > swingHigh) swingHigh = rates[i].high;
   }

   double atrPad = atrH4Val[0] * ATRStopMultiplierH4;

   if(orderType == ORDER_TYPE_BUY)
   {
      stopLoss = swingLow - atrPad;
      if(entryPrice <= stopLoss)
         return false;
   }
   else
   {
      stopLoss = swingHigh + atrPad;
      if(entryPrice >= stopLoss)
         return false;
   }

   // remainder managed by R-based partial + trailing
   takeProfit = 0.0;

   stopLoss = NormalizePrice(symbol, stopLoss);
   takeProfit = NormalizePrice(symbol, takeProfit);

   return true;
}

//+------------------------------------------------------------------+
//| Position size calculation                                        |
//+------------------------------------------------------------------+
double CalculatePositionSize(const string symbol, const double slDistancePrice)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(UseOpenRiskAdjustedBalance)
   {
      double openRisk = CalculateOpenRiskMoney();
      balance -= openRisk;

      if(DebugMode && openRisk > 0.0)
         Print("[", symbol, "] Position sizing balance adjusted by open SL risk: risk=", openRisk, " effectiveBalance=", balance);
   }

   if(balance <= 0.0)
      return 0.0;

   double riskMoney = balance * (RiskPercent / 100.0);

   double volMin    = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double volMax    = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double volStep   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   if(slDistancePrice <= 0.0 || volStep <= 0.0)
      return 0.0;

   double moneyPerLot = MoneyAtRiskPerLot(symbol, slDistancePrice);
   if(moneyPerLot <= 0.0)
      return 0.0;

   double volume = riskMoney / moneyPerLot;

   volume = MathFloor(volume / volStep) * volStep;
   volume = MathMax(volume, volMin);
   volume = MathMin(volume, volMax);

   int stepDigits = 0;
   double tmpStep = volStep;
   while(tmpStep < 1.0 && stepDigits < 8)
   {
      tmpStep *= 10.0;
      stepDigits++;
   }

   return NormalizeDouble(volume, stepDigits);
}

//+------------------------------------------------------------------+
//| Money at risk for 1.00 lot over a price distance                 |
//+------------------------------------------------------------------+
double MoneyAtRiskPerLot(const string symbol, const double slDistancePrice)
{
   double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);

   if(tickSize <= 0.0 || tickValue <= 0.0 || slDistancePrice <= 0.0)
      return 0.0;

   return (slDistancePrice / tickSize) * tickValue;
}

//+------------------------------------------------------------------+
//| Sum remaining SL risk across this EA's open tracked positions    |
//+------------------------------------------------------------------+
double CalculateOpenRiskMoney()
{
   double totalRisk = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      long magic = PositionGetInteger(POSITION_MAGIC);

      if((ulong)magic != MagicNumber)
         continue;
      if(!IsTrackedSymbol(symbol))
         continue;

      long posType = PositionGetInteger(POSITION_TYPE);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double volume = PositionGetDouble(POSITION_VOLUME);

      totalRisk += CalculatePositionRiskMoney(symbol, posType, entry, sl, volume);
   }

   return totalRisk;
}

//+------------------------------------------------------------------+
//| Remaining money risk for one position if SL is hit               |
//+------------------------------------------------------------------+
double CalculatePositionRiskMoney(const string symbol, const long posType, const double entryPrice, const double stopLoss, const double volume)
{
   if(entryPrice <= 0.0 || stopLoss <= 0.0 || volume <= 0.0)
      return 0.0;

   double slDistance = 0.0;

   if(posType == POSITION_TYPE_BUY && stopLoss < entryPrice)
      slDistance = entryPrice - stopLoss;
   else if(posType == POSITION_TYPE_SELL && stopLoss > entryPrice)
      slDistance = stopLoss - entryPrice;

   if(slDistance <= 0.0)
      return 0.0;

   return MoneyAtRiskPerLot(symbol, slDistance) * volume;
}

//+------------------------------------------------------------------+
//| Normalize price                                                  |
//+------------------------------------------------------------------+
double NormalizePrice(const string symbol, const double price)
{
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   return NormalizeDouble(price, digits);
}

//+------------------------------------------------------------------+
//| Pip size helper                                                  |
//+------------------------------------------------------------------+
double PipSize(const string symbol)
{
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(digits == 3 || digits == 5)
      return (point * 10.0);
   return point;
}

//+------------------------------------------------------------------+
//| Normalize volume                                                 |
//+------------------------------------------------------------------+
double NormalizeVolume(const string symbol, const double rawVolume)
{
   double volMin  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double volMax  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double volStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   if(volStep <= 0.0)
      return 0.0;

   double stepped = MathFloor(rawVolume / volStep) * volStep;
   double clamped = MathMax(volMin, MathMin(volMax, stepped));

   int digits = 0;
   double step = volStep;
   while(step < 1.0 && digits < 8)
   {
      step *= 10.0;
      digits++;
   }

   return NormalizeDouble(clamped, digits);
}

//+------------------------------------------------------------------+
//| Truncate volume to 2 decimal places                              |
//+------------------------------------------------------------------+
double TruncateToTwoDecimals(const double value)
{
   if(value <= 0.0)
      return 0.0;

   return NormalizeDouble(MathFloor(value * 100.0) / 100.0, 2);
}

//+------------------------------------------------------------------+
//| Per-ticket management index                                      |
//+------------------------------------------------------------------+
int FindManagedIndex(const ulong ticket)
{
   for(int i = 0; i < managedCount; i++)
      if(managedTickets[i] == ticket)
         return i;
   return -1;
}

//+------------------------------------------------------------------+
//| Register ticket for R-based management                           |
//+------------------------------------------------------------------+
void EnsureTicketRegistered(const ulong ticket, const double entryPrice, const double slPrice)
{
   if(FindManagedIndex(ticket) >= 0)
      return;

   if(managedCount >= ArraySize(managedTickets))
      return;

   double risk = MathAbs(entryPrice - slPrice);
   if(risk <= 0.0)
      return;

   double initialVolume = 0.0;
   if(PositionSelectByTicket(ticket))
      initialVolume = PositionGetDouble(POSITION_VOLUME);
   if(initialVolume <= 0.0)
      return;

   managedTickets[managedCount] = ticket;
   initialEntryByTicket[managedCount] = entryPrice;
   initialRiskByTicket[managedCount] = risk;
   initialVolumeByTicket[managedCount] = initialVolume;
   tp1DoneByTicket[managedCount] = false;
   tp2DoneByTicket[managedCount] = false;
   managedCount++;
}

//+------------------------------------------------------------------+
//| Partial close by ticket                                          |
//+------------------------------------------------------------------+
bool ClosePartialByTicket(const ulong ticket, const long posType, const double closeVolume)
{
   if(closeVolume <= 0.0)
      return false;

   if(!PositionSelectByTicket(ticket))
      return false;

   string symbol = PositionGetString(POSITION_SYMBOL);
   double volume = PositionGetDouble(POSITION_VOLUME);
   double volMin = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double volStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   if(volStep <= 0.0)
      volStep = volMin;

   double normalizedCloseVolume = NormalizeVolume(symbol, closeVolume);
   if(normalizedCloseVolume <= 0.0 || normalizedCloseVolume < volMin)
      return false;

   if(normalizedCloseVolume > volume)
      normalizedCloseVolume = NormalizeVolume(symbol, volume);

   if(normalizedCloseVolume <= 0.0 || normalizedCloseVolume < volMin)
      return false;

   if((volume - normalizedCloseVolume) < (volMin - (volStep * 0.5)))
      return false;

   MqlTick t;
   if(!SymbolInfoTick(symbol, t))
      return false;

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};

   req.action   = TRADE_ACTION_DEAL;
   req.position = ticket;
   req.symbol   = symbol;
   req.volume   = normalizedCloseVolume;
   req.magic    = (long)MagicNumber;
   req.deviation = 20;
   req.type_filling = ORDER_FILLING_FOK;

   if(posType == POSITION_TYPE_BUY)
   {
      req.type  = ORDER_TYPE_SELL;
      req.price = NormalizePrice(symbol, t.bid);
   }
   else
   {
      req.type  = ORDER_TYPE_BUY;
      req.price = NormalizePrice(symbol, t.ask);
   }

   bool ok = OrderSend(req, res);
   if(!ok || (res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_PLACED))
   {
      if(DebugMode)
         Print("[", symbol, "] Partial close failed ticket=", ticket, " retcode=", res.retcode);
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Manage open positions                                            |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      long magic = PositionGetInteger(POSITION_MAGIC);

      if((ulong)magic != MagicNumber)
         continue;
      if(!IsTrackedSymbol(symbol))
         continue;

      int idx = FindContextIndex(symbol);
      if(idx < 0)
         continue;

      long posType = PositionGetInteger(POSITION_TYPE);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl    = PositionGetDouble(POSITION_SL);
      double tp    = PositionGetDouble(POSITION_TP);

      EnsureTicketRegistered(ticket, entry, sl);
      int m = FindManagedIndex(ticket);
      if(m < 0)
         continue;

      double initialEntry  = initialEntryByTicket[m];
      double initialRisk   = initialRiskByTicket[m];
      double initialVolume = initialVolumeByTicket[m];
      if(initialRisk <= 0.0 || initialEntry <= 0.0 || initialVolume <= 0.0)
         continue;

      MqlTick t;
      if(!SymbolInfoTick(symbol, t))
         continue;

      double currentPrice = (posType == POSITION_TYPE_BUY) ? t.bid : t.ask;
      double profitMove   = (posType == POSITION_TYPE_BUY) ? (currentPrice - initialEntry) : (initialEntry - currentPrice);
      double tp1Price     = (posType == POSITION_TYPE_BUY) ? (initialEntry + (initialRisk * TP1_RR)) : (initialEntry - (initialRisk * TP1_RR));
      double tp2Price     = (posType == POSITION_TYPE_BUY) ? (initialEntry + (initialRisk * TP2_RR)) : (initialEntry - (initialRisk * TP2_RR));
      double tp3Price     = (posType == POSITION_TYPE_BUY) ? (initialEntry + (initialRisk * TP3_RR)) : (initialEntry - (initialRisk * TP3_RR));

      double rNow = profitMove / initialRisk;

      bool tp1Hit = (posType == POSITION_TYPE_BUY) ? (currentPrice >= tp1Price) : (currentPrice <= tp1Price);
      bool tp2Hit = (posType == POSITION_TYPE_BUY) ? (currentPrice >= tp2Price) : (currentPrice <= tp2Price);
      bool tp3Hit = (posType == POSITION_TYPE_BUY) ? (currentPrice >= tp3Price) : (currentPrice <= tp3Price);

      if(UsePartialTP && !tp1DoneByTicket[m] && tp1Hit)
      {
         // Close one-third of the original lot at 1R so sizes like 0.12 split to 0.04.
         double tp1CloseVolume = TruncateToTwoDecimals(initialVolume / 3.0);
         if(ClosePartialByTicket(ticket, posType, tp1CloseVolume))
            tp1DoneByTicket[m] = true;
      }

      if(UsePartialTP && !tp2DoneByTicket[m] && tp2Hit)
      {
         // Close half of the remaining lot at 2R.
         double currentVolume = PositionGetDouble(POSITION_VOLUME);
         double tp2CloseVolume = TruncateToTwoDecimals(currentVolume / 2.0);
         if(ClosePartialByTicket(ticket, posType, tp2CloseVolume))
            tp2DoneByTicket[m] = true;
      }

      double atrH4Buf[1];
      if(CopyBuffer(ctx[idx].h4ATR, 0, 0, 1, atrH4Buf) < 1)
         continue;
      ArraySetAsSeries(atrH4Buf, true);
      double atrH4Now = atrH4Buf[0];
      if(atrH4Now <= 0.0)
         continue;

      double beLock = BreakEvenLockPips * PipSize(symbol);
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      double minStopDistance = (double)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;

      double newSL = sl;
      bool shouldModify = false;

      if(MoveToBEAt2R && tp2Hit)
      {
         if(posType == POSITION_TYPE_BUY)
         {
            double beSL = NormalizePrice(symbol, initialEntry + beLock);
            double maxAllowed = NormalizePrice(symbol, t.bid - minStopDistance);
            if(beSL > maxAllowed) beSL = maxAllowed;

            if(beSL > 0.0 && (newSL == 0.0 || beSL > newSL))
            {
               newSL = beSL;
               shouldModify = true;
            }
         }
         else
         {
            double beSL = NormalizePrice(symbol, initialEntry - beLock);
            double minAllowed = NormalizePrice(symbol, t.ask + minStopDistance);
            if(beSL < minAllowed) beSL = minAllowed;

            if(beSL > 0.0 && (newSL == 0.0 || beSL < newSL))
            {
               newSL = beSL;
               shouldModify = true;
            }
         }
      }

      if(UseATRTrailingAfterTP3 && tp3Hit)
      {
         if(posType == POSITION_TYPE_BUY)
         {
            double trailSL = NormalizePrice(symbol, t.bid - (atrH4Now * ATRTrailMultiplier));
            double maxAllowed = NormalizePrice(symbol, t.bid - minStopDistance);
            if(trailSL > maxAllowed) trailSL = maxAllowed;

            if(trailSL > 0.0 && (newSL == 0.0 || trailSL > newSL))
            {
               newSL = trailSL;
               shouldModify = true;
            }
         }
         else
         {
            double trailSL = NormalizePrice(symbol, t.ask + (atrH4Now * ATRTrailMultiplier));
            double minAllowed = NormalizePrice(symbol, t.ask + minStopDistance);
            if(trailSL < minAllowed) trailSL = minAllowed;

            if(trailSL > 0.0 && (newSL == 0.0 || trailSL < newSL))
            {
               newSL = trailSL;
               shouldModify = true;
            }
         }
      }

      if(!shouldModify)
         continue;

      if(sl != 0.0 && MathAbs(newSL - sl) < (point * 0.5))
         continue;

      MqlTradeRequest req = {};
      MqlTradeResult  res = {};
      req.action   = TRADE_ACTION_SLTP;
      req.position = ticket;
      req.symbol   = symbol;
      req.magic    = (long)MagicNumber;
      req.sl       = NormalizePrice(symbol, newSL);
      req.tp       = tp;

      if(!OrderSend(req, res) || (res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_PLACED))
      {
         if(DebugMode)
            Print("[", symbol, "] SL modify failed ticket=", ticket, " retcode=", res.retcode);
      }
      else if(DebugMode)
      {
         Print("[", symbol, "] SL updated ticket=", ticket, " oldSL=", sl, " newSL=", req.sl, " R=", rNow);
      }
   }
}

//+------------------------------------------------------------------+
//| Daily loss cap                                                   |
//+------------------------------------------------------------------+
bool IsDailyLossLimitReached(const string symbol)
{
   datetime dayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE) + " 00:00");
   datetime now      = TimeCurrent();

   if(!HistorySelect(dayStart, now))
      return false;

   double dayPnl = 0.0;
   int deals = HistoryDealsTotal();

   for(int i = 0; i < deals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;

      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != symbol)
         continue;
      if((ulong)HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber)
         continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT)
         continue;

      double pnl = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                 + HistoryDealGetDouble(ticket, DEAL_SWAP)
                 + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      dayPnl += pnl;
   }

   double maxLoss = AccountInfoDouble(ACCOUNT_BALANCE) * (MaxDailyLossPercent / 100.0);
   return (dayPnl <= -maxLoss);
}

//+------------------------------------------------------------------+
//| Today's consecutive losses                                       |
//+------------------------------------------------------------------+
int GetTodayConsecutiveLosses(const string symbol)
{
   datetime dayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE) + " 00:00");
   datetime now      = TimeCurrent();

   if(!HistorySelect(dayStart, now))
      return 0;

   int losses = 0;
   int deals = HistoryDealsTotal();

   for(int i = deals - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;

      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != symbol)
         continue;
      if((ulong)HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber)
         continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT)
         continue;

      double pnl = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                 + HistoryDealGetDouble(ticket, DEAL_SWAP)
                 + HistoryDealGetDouble(ticket, DEAL_COMMISSION);

      if(pnl < 0.0)
         losses++;
      else
         break;
   }

   return losses;
}

//+------------------------------------------------------------------+
//| Count today's trades for this EA+symbol                          |
//+------------------------------------------------------------------+
int GetTodayTradeCount(const string symbol)
{
   datetime dayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE) + " 00:00");
   datetime now      = TimeCurrent();

   if(!HistorySelect(dayStart, now))
      return 0;

   int count = 0;
   int deals = HistoryDealsTotal();

   for(int i = 0; i < deals; i++)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0)
         continue;

      if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != symbol)
         continue;
      if((ulong)HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != MagicNumber)
         continue;
      if(HistoryDealGetInteger(dealTicket, DEAL_ENTRY) != DEAL_ENTRY_IN)
         continue;

      count++;
   }

   return count;
}

//+------------------------------------------------------------------+
//| Check if symbol position already exists for this EA              |
//+------------------------------------------------------------------+
bool HasOpenPositionForSymbol(const string symbol)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      string s = PositionGetString(POSITION_SYMBOL);
      long magic = PositionGetInteger(POSITION_MAGIC);

      if(s == symbol && (ulong)magic == MagicNumber)
         return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Check if SL is at breakeven or better                            |
//+------------------------------------------------------------------+
bool IsPositionAtBreakevenOrBetter(const long posType, const double entryPrice, const double stopLoss, const double point)
{
   if(stopLoss <= 0.0 || point <= 0.0)
      return false;

   double tolerance = point * 0.5;

   if(posType == POSITION_TYPE_BUY)
      return (stopLoss >= (entryPrice - tolerance));

   if(posType == POSITION_TYPE_SELL)
      return (stopLoss <= (entryPrice + tolerance));

   return false;
}

//+------------------------------------------------------------------+
//| Count EA open trades excluding breakeven-protected positions     |
//+------------------------------------------------------------------+
int CountOpenTradesExcludingBreakeven()
{
   int count = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      long magic    = PositionGetInteger(POSITION_MAGIC);

      if((ulong)magic != MagicNumber)
         continue;
      if(!IsTrackedSymbol(symbol))
         continue;

      long posType      = PositionGetInteger(POSITION_TYPE);
      double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double stopLoss   = PositionGetDouble(POSITION_SL);
      double point      = SymbolInfoDouble(symbol, SYMBOL_POINT);

      if(IsPositionAtBreakevenOrBetter(posType, entryPrice, stopLoss, point))
         continue;

      count++;
   }

   return count;
}

//+------------------------------------------------------------------+
//| Extract base/quote currencies from a forex symbol                |
//+------------------------------------------------------------------+
bool GetSymbolCurrencies(const string symbol, string &baseCurrency, string &quoteCurrency)
{
   if(StringLen(symbol) < 6)
      return false;

   baseCurrency = StringSubstr(symbol, 0, 3);
   quoteCurrency = StringSubstr(symbol, 3, 3);

   return (StringLen(baseCurrency) == 3 && StringLen(quoteCurrency) == 3);
}

//+------------------------------------------------------------------+
//| Build signed currency exposure key                               |
//+------------------------------------------------------------------+
string CurrencyExposureKey(const string currency, const int direction)
{
   return currency + (direction >= 0 ? "_LONG" : "_SHORT");
}

//+------------------------------------------------------------------+
//| Primary trade theme basket                                       |
//+------------------------------------------------------------------+
string PrimaryBasketKey(const string symbol, const ENUM_ORDER_TYPE orderType)
{
   string baseBasketKey = "";
   string quoteBasketKey = "";
   if(!GetOrderBasketKeys(symbol, orderType, baseBasketKey, quoteBasketKey))
      return symbol + "_BASKET";

   return baseBasketKey;
}

//+------------------------------------------------------------------+
//| Basket keys created by a proposed order                          |
//+------------------------------------------------------------------+
bool GetOrderBasketKeys(const string symbol, const ENUM_ORDER_TYPE orderType, string &baseBasketKey, string &quoteBasketKey)
{
   string baseCurrency = "";
   string quoteCurrency = "";
   if(!GetSymbolCurrencies(symbol, baseCurrency, quoteCurrency))
      return false;

   int baseDirection = (orderType == ORDER_TYPE_BUY) ? 1 : -1;
   int quoteDirection = -baseDirection;

   baseBasketKey = CurrencyExposureKey(baseCurrency, baseDirection);
   quoteBasketKey = CurrencyExposureKey(quoteCurrency, quoteDirection);

   return true;
}

//+------------------------------------------------------------------+
//| Position exposure direction for a currency                       |
//+------------------------------------------------------------------+
int PositionCurrencyDirection(const string symbol, const long posType, const string currency)
{
   string baseCurrency = "";
   string quoteCurrency = "";
   if(!GetSymbolCurrencies(symbol, baseCurrency, quoteCurrency))
      return 0;

   if(currency == baseCurrency)
      return (posType == POSITION_TYPE_BUY) ? 1 : -1;

   if(currency == quoteCurrency)
      return (posType == POSITION_TYPE_BUY) ? -1 : 1;

   return 0;
}

//+------------------------------------------------------------------+
//| Count same-direction open exposure for a currency                |
//+------------------------------------------------------------------+
int CountCurrencyExposure(const string currency, const int direction)
{
   int count = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      long magic = PositionGetInteger(POSITION_MAGIC);

      if((ulong)magic != MagicNumber)
         continue;
      if(!IsTrackedSymbol(symbol))
         continue;

      long posType = PositionGetInteger(POSITION_TYPE);
      int posDirection = PositionCurrencyDirection(symbol, posType, currency);

      if(posDirection == direction)
         count++;
   }

   return count;
}

//+------------------------------------------------------------------+
//| Correlation exposure filter                                      |
//+------------------------------------------------------------------+
bool CorrelationExposureAllows(const string symbol, const ENUM_ORDER_TYPE orderType)
{
   if(MaxCurrencyExposure <= 0)
      return true;

   string baseCurrency = "";
   string quoteCurrency = "";
   if(!GetSymbolCurrencies(symbol, baseCurrency, quoteCurrency))
      return true;

   int baseDirection = (orderType == ORDER_TYPE_BUY) ? 1 : -1;
   int quoteDirection = -baseDirection;

   int baseExposure = CountCurrencyExposure(baseCurrency, baseDirection);
   if(baseExposure >= MaxCurrencyExposure)
   {
      if(DebugMode)
         Print("[", symbol, "] Correlation filter blocked: ", CurrencyExposureKey(baseCurrency, baseDirection),
               " exposure=", baseExposure, " limit=", MaxCurrencyExposure);
      return false;
   }

   int quoteExposure = CountCurrencyExposure(quoteCurrency, quoteDirection);
   if(quoteExposure >= MaxCurrencyExposure)
   {
      if(DebugMode)
         Print("[", symbol, "] Correlation filter blocked: ", CurrencyExposureKey(quoteCurrency, quoteDirection),
               " exposure=", quoteExposure, " limit=", MaxCurrencyExposure);
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Basket risk entry gate                                           |
//+------------------------------------------------------------------+
bool BasketAllowsFreshEntry(const string symbol, const ENUM_ORDER_TYPE orderType)
{
   string baseBasketKey = "";
   string quoteBasketKey = "";
   if(!GetOrderBasketKeys(symbol, orderType, baseBasketKey, quoteBasketKey))
      return true;

   if(!BasketKeyAllowsFreshEntry(symbol, baseBasketKey))
      return false;

   if(!BasketKeyAllowsFreshEntry(symbol, quoteBasketKey))
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| Basket risk entry gate for one basket key                        |
//+------------------------------------------------------------------+
bool BasketKeyAllowsFreshEntry(const string symbol, const string basketKey)
{
   if(IsBasketLocked(basketKey))
   {
      if(DebugMode) Print("[", symbol, "] Basket locked: ", basketKey);
      return false;
   }

   double basketPnl = BasketFloatingPnl(basketKey);
   double maxLoss = AccountInfoDouble(ACCOUNT_BALANCE) * (MaxBasketFloatingLossPercent / 100.0);

   if(maxLoss > 0.0 && basketPnl <= -maxLoss)
   {
      RecordBasketLock(basketKey, TimeCurrent(), "floating_loss_limit");
      if(DebugMode)
         Print("[", symbol, "] Basket floating loss limit reached: ", basketKey,
               " pnl=", basketPnl, " maxLoss=", maxLoss);
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Floating PnL for positions in a basket                           |
//+------------------------------------------------------------------+
double BasketFloatingPnl(const string basketKey)
{
   double total = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      long magic = PositionGetInteger(POSITION_MAGIC);

      if((ulong)magic != MagicNumber)
         continue;
      if(!IsTrackedSymbol(symbol))
         continue;

      long posType = PositionGetInteger(POSITION_TYPE);
      if(!PositionBelongsToBasket(symbol, posType, basketKey))
         continue;

      total += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }

   return total;
}

//+------------------------------------------------------------------+
//| Check whether a position belongs to a directional currency basket |
//+------------------------------------------------------------------+
bool PositionBelongsToBasket(const string symbol, const long posType, const string basketKey)
{
   string baseCurrency = "";
   string quoteCurrency = "";
   if(!GetSymbolCurrencies(symbol, baseCurrency, quoteCurrency))
      return false;

   string baseKey = CurrencyExposureKey(baseCurrency, (posType == POSITION_TYPE_BUY) ? 1 : -1);
   string quoteKey = CurrencyExposureKey(quoteCurrency, (posType == POSITION_TYPE_BUY) ? -1 : 1);

   return (basketKey == baseKey || basketKey == quoteKey);
}

//+------------------------------------------------------------------+
//| Basket lock filename                                             |
//+------------------------------------------------------------------+
string BasketLockFileName()
{
   return RiskStateFilePrefix + "_basket_locks.csv";
}

//+------------------------------------------------------------------+
//| Cooldown filename                                                |
//+------------------------------------------------------------------+
string LossCooldownFileName()
{
   return RiskStateFilePrefix + "_loss_cooldowns.csv";
}

//+------------------------------------------------------------------+
//| Check saved basket lock                                          |
//+------------------------------------------------------------------+
bool IsBasketLocked(const string basketKey)
{
   int handle = FileOpen(BasketLockFileName(), FILE_READ | FILE_CSV | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
      return false;

   string today = TimeToString(TimeCurrent(), TIME_DATE);
   bool locked = false;

   while(!FileIsEnding(handle))
   {
      string savedBasket = FileReadString(handle);
      string savedTimeText = FileReadString(handle);
      string reason = FileReadString(handle);

      if(savedBasket == basketKey)
      {
         datetime savedTime = StringToTime(savedTimeText);
         if(savedTime > 0 && TimeToString(savedTime, TIME_DATE) == today)
         {
            locked = true;
            break;
         }
      }
   }

   FileClose(handle);
   return locked;
}

//+------------------------------------------------------------------+
//| Record basket lock                                               |
//+------------------------------------------------------------------+
void RecordBasketLock(const string basketKey, const datetime lockTime, const string reason)
{
   int handle = FileOpen(BasketLockFileName(), FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
   {
      if(DebugMode) Print("Failed to open basket lock file. error=", GetLastError());
      return;
   }

   FileSeek(handle, 0, SEEK_END);
   FileWrite(handle, basketKey, TimeToString(lockTime, TIME_DATE | TIME_MINUTES), reason);
   FileClose(handle);
}

//+------------------------------------------------------------------+
//| Check cooldown file before a new entry                           |
//+------------------------------------------------------------------+
bool IsLossCooldownActive(const string symbol, const string basketKey)
{
   if(LossCooldownHours <= 0)
      return false;

   int handle = FileOpen(LossCooldownFileName(), FILE_READ | FILE_CSV | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
      return false;

   datetime now = TimeCurrent();
   bool active = false;

   while(!FileIsEnding(handle))
   {
      string savedSymbol = FileReadString(handle);
      string savedBasket = FileReadString(handle);
      string savedTimeText = FileReadString(handle);
      string savedPnl = FileReadString(handle);

      if(savedSymbol == symbol || savedBasket == basketKey)
      {
         datetime savedTime = StringToTime(savedTimeText);
         if(savedTime > 0 && (now - savedTime) < (LossCooldownHours * 3600))
         {
            active = true;
            break;
         }
      }
   }

   FileClose(handle);
   return active;
}

//+------------------------------------------------------------------+
//| Save losing trade cooldown                                       |
//+------------------------------------------------------------------+
void RecordLossCooldown(const string symbol, const string basketKey, const datetime lossTime, const double pnl)
{
   int handle = FileOpen(LossCooldownFileName(), FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
   {
      if(DebugMode) Print("Failed to open loss cooldown file. error=", GetLastError());
      return;
   }

   FileSeek(handle, 0, SEEK_END);
   FileWrite(handle, symbol, basketKey, TimeToString(lossTime, TIME_DATE | TIME_MINUTES), DoubleToString(pnl, 2));
   FileClose(handle);
}

//+------------------------------------------------------------------+
//| Trade transaction hook for loss cooldown recording               |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(!UseLossCooldown)
      return;

   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0)
      return;

   if(!HistoryDealSelect(trans.deal))
      return;

   string symbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
   if(!IsTrackedSymbol(symbol))
      return;

   if((ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != MagicNumber)
      return;

   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT)
      return;

   double pnl = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
              + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
              + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);

   if(pnl >= 0.0)
      return;

   long dealType = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
   ENUM_ORDER_TYPE originalOrderType = (dealType == DEAL_TYPE_SELL) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   string basketKey = "";
   string quoteBasketKey = "";
   GetOrderBasketKeys(symbol, originalOrderType, basketKey, quoteBasketKey);
   datetime lossTime = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);

   RecordLossCooldown(symbol, basketKey, lossTime, pnl);
   if(quoteBasketKey != "")
      RecordLossCooldown(symbol, quoteBasketKey, lossTime, pnl);

   if(DebugMode)
      Print("[", symbol, "] Loss cooldown recorded for ", basketKey, " / ", quoteBasketKey, " pnl=", pnl);
}
//+------------------------------------------------------------------+
