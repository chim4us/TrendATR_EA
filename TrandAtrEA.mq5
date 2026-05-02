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
input bool    UseLearningMemory           = true;
input int     SetupFailureLimit           = 3;      // failures within LearningLookbackDays block setup for week
input int     LearningLookbackDays        = 7;
input int     SymbolLossStreakLimit       = 5;
input bool    UseWeeklyRiskLimit          = true;
input double  MaxWeeklyLossPercent        = 4.0;
input double  MaxSymbolWeeklyLossPercent  = 1.0;    // poor weekly performance block per symbol

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
string TradeLearningFileName();
string EntrySnapshotFileName();
string DailyRiskFileName();
string WeeklyStartFileName();
string WeakLevelFileName();
void   EnsureCsvHeaders();
void   EnsureCsvHeader(const string fileName, const string headerLine, const string firstHeaderColumn, const int columnCount);
string SetupTypeName(const ENUM_ORDER_TYPE orderType);
string DirectionNameFromDealType(const long dealType);
string EntryReasonText(const ENUM_ORDER_TYPE orderType);
string SessionName(const datetime value);
string TimeframeName(const ENUM_TIMEFRAMES timeframe);
void   UpdateDailyRiskRecord();
void   UpdateWeeklyStartBalance();
double GetRecordedWeeklyStartBalance(const datetime weekStart);
double GetRealizedPnlForDay(const datetime dayStart, const string symbolFilter);
datetime GetWeekStart(const datetime value);
bool   IsWeeklyRiskLimitReached();
bool   IsSymbolWeeklyPerformancePoor(const string symbol);
bool   IsLearningBlocked(const string symbol, const ENUM_ORDER_TYPE orderType);
bool   HasSetupFailureBlock(const string symbol, const string setupType);
bool   HasSymbolLossStreak(const string symbol);
bool   IsWeakLevelBlocked(const string symbol, const ENUM_ORDER_TYPE orderType, const double level);
void   RecordWeakLevel(const string symbol, const ENUM_ORDER_TYPE orderType, const double level, const datetime when, const string reason);
void   RecordEntrySnapshot(const ulong positionId, const string symbol, const ENUM_ORDER_TYPE orderType, const double entryPrice, const double stopLoss, const double takeProfit, const double volume, const double entryATRPips, const double entrySpreadPoints, const datetime entryTime);
bool   GetEntrySnapshotInfo(const ulong positionId, string &reason, double &entryPrice, double &entrySl, double &entryTp, double &entryVolume, double &entryATRPips, double &entrySpreadPoints, string &entrySession, string &setupType);
void   RecordClosedTradeLearning(const ulong deal);
bool   GetEntryDealInfo(const ulong positionId, string &reason, double &entryPrice, double &entrySl, double &entryTp, double &entryVolume, double &entryATRPips, double &entrySpreadPoints, string &entrySession, string &setupType);
string DetermineFailureReason(const string symbol, const string direction, const double pnl, const double exitPrice, const double entrySl, const double entryTp);
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

   EnsureCsvHeaders();

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
   UpdateDailyRiskRecord();

   if(UseWeeklyRiskLimit && IsWeeklyRiskLimitReached())
   {
      if(DebugMode) Print("Weekly loss cap reached. New entries blocked.");
      return;
   }

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

   if(UseLearningMemory && IsLearningBlocked(symbol, orderType))
      return;

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
   double entrySpreadPoints = 0.0;
   double entryATRPips = 0.0;

   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point > 0.0)
      entrySpreadPoints = (t.ask - t.bid) / point;

   double atrAtEntry[1];
   if(CopyBuffer(ctx[idx].m15ATR, 0, 0, 1, atrAtEntry) >= 1)
      entryATRPips = atrAtEntry[0] / PipSize(symbol);

   if(!CalculateSLTP(idx, orderType, entryPrice, stopLoss, takeProfit))
   {
      if(DebugMode) Print("[", symbol, "] Failed to calculate SL/TP.");
      return;
   }

   double weakLevel = stopLoss;
   if(UseLearningMemory && IsWeakLevelBlocked(symbol, orderType, weakLevel))
   {
      if(DebugMode)
         Print("[", symbol, "] Learning memory blocked weak level near SL=", weakLevel);
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

   if(ok && UseLearningMemory)
   {
      ulong entryDeal = trade.ResultDeal();
      if(entryDeal > 0 && HistoryDealSelect(entryDeal))
      {
         ulong positionId = (ulong)HistoryDealGetInteger(entryDeal, DEAL_POSITION_ID);
         if(positionId > 0)
            RecordEntrySnapshot(positionId, symbol, orderType, entryPrice, stopLoss, takeProfit, volume,
                                entryATRPips, entrySpreadPoints, (datetime)HistoryDealGetInteger(entryDeal, DEAL_TIME));
      }
   }

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
//| Learning trade log filename                                      |
//+------------------------------------------------------------------+
string TradeLearningFileName()
{
   return RiskStateFilePrefix + "_trade_learning.csv";
}

//+------------------------------------------------------------------+
//| Entry condition snapshot filename                                |
//+------------------------------------------------------------------+
string EntrySnapshotFileName()
{
   return RiskStateFilePrefix + "_entry_snapshots.csv";
}

//+------------------------------------------------------------------+
//| Daily risk ledger filename                                       |
//+------------------------------------------------------------------+
string DailyRiskFileName()
{
   return RiskStateFilePrefix + "_daily_risk.csv";
}

//+------------------------------------------------------------------+
//| Weekly starting balance filename                                 |
//+------------------------------------------------------------------+
string WeeklyStartFileName()
{
   return RiskStateFilePrefix + "_weekly_start_balance.csv";
}

//+------------------------------------------------------------------+
//| Weak level memory filename                                       |
//+------------------------------------------------------------------+
string WeakLevelFileName()
{
   return RiskStateFilePrefix + "_weak_levels.csv";
}

//+------------------------------------------------------------------+
//| Ensure all EA CSV files have readable header rows                |
//+------------------------------------------------------------------+
void EnsureCsvHeaders()
{
   EnsureCsvHeader(DailyRiskFileName(), "Date,StartingBalance,RealizedPnL", "Date", 3);
   EnsureCsvHeader(WeeklyStartFileName(), "WeekStart,StartingBalance", "WeekStart", 2);
   EnsureCsvHeader(TradeLearningFileName(), "Date,Symbol,Direction,Entry,SL,TP,Lot,Timeframe,ATR_Pips,Spread_Points,Session,ReasonForEntry,Result,ProfitLoss,FailureReason", "Date", 15);
   EnsureCsvHeader(EntrySnapshotFileName(), "PositionID,Date,Symbol,Direction,Entry,SL,TP,Lot,Timeframe,ATR_Pips,Spread_Points,Session,ReasonForEntry", "PositionID", 13);
   EnsureCsvHeader(WeakLevelFileName(), "Date,Symbol,SetupType,Level,Reason", "Date", 5);
   EnsureCsvHeader(BasketLockFileName(), "BasketKey,LockTime,Reason", "BasketKey", 3);
   EnsureCsvHeader(LossCooldownFileName(), "Symbol,BasketKey,LossTime,ProfitLoss", "Symbol", 4);
}

//+------------------------------------------------------------------+
//| Add missing header while preserving existing CSV records         |
//+------------------------------------------------------------------+
void EnsureCsvHeader(const string fileName, const string headerLine, const string firstHeaderColumn, const int columnCount)
{
   if(columnCount <= 0)
      return;

   string rows[];
   int rowCount = 0;
   bool hasHeader = false;
   bool hasAnyRow = false;

   int readHandle = FileOpen(fileName, FILE_READ | FILE_CSV | FILE_ANSI, ',');
   if(readHandle != INVALID_HANDLE)
   {
      while(!FileIsEnding(readHandle))
      {
         string line = "";
         string firstField = "";

         for(int i = 0; i < columnCount; i++)
         {
            string field = FileReadString(readHandle);
            if(i == 0)
               firstField = field;
            if(i > 0)
               line += ",";
            line += field;
         }

         if(firstField == "")
            continue;

         if(!hasAnyRow)
         {
            hasAnyRow = true;
            if(firstField == firstHeaderColumn)
            {
               hasHeader = true;
               continue;
            }
         }

         ArrayResize(rows, rowCount + 1);
         rows[rowCount] = line;
         rowCount++;
      }

      FileClose(readHandle);
   }

   if(hasHeader)
      return;

   int writeHandle = FileOpen(fileName, FILE_WRITE | FILE_ANSI);
   if(writeHandle == INVALID_HANDLE)
   {
      if(DebugMode) Print("Failed to add CSV header for ", fileName, ". error=", GetLastError());
      return;
   }

   FileWriteString(writeHandle, headerLine + "\r\n");
   for(int i = 0; i < rowCount; i++)
      FileWriteString(writeHandle, rows[i] + "\r\n");

   FileClose(writeHandle);
}

//+------------------------------------------------------------------+
//| Setup type name                                                  |
//+------------------------------------------------------------------+
string SetupTypeName(const ENUM_ORDER_TYPE orderType)
{
   if(orderType == ORDER_TYPE_BUY)
      return "BUY_PULLBACK_SUPPORT";

   return "SELL_PULLBACK_RESISTANCE";
}

//+------------------------------------------------------------------+
//| Direction from closing deal type                                 |
//+------------------------------------------------------------------+
string DirectionNameFromDealType(const long dealType)
{
   return (dealType == DEAL_TYPE_SELL) ? "BUY" : "SELL";
}

//+------------------------------------------------------------------+
//| Human-readable entry reason                                      |
//+------------------------------------------------------------------+
string EntryReasonText(const ENUM_ORDER_TYPE orderType)
{
   if(orderType == ORDER_TYPE_BUY)
      return "H4 bullish trend + M15 pullback support bounce";

   return "H4 bearish trend + M15 pullback resistance rejection";
}

//+------------------------------------------------------------------+
//| Trading session name by server hour                              |
//+------------------------------------------------------------------+
string SessionName(const datetime value)
{
   MqlDateTime timeStruct;
   TimeToStruct(value, timeStruct);

   if(timeStruct.hour >= 0 && timeStruct.hour < 7)
      return "Asian";
   if(timeStruct.hour >= 7 && timeStruct.hour < 13)
      return "London";
   if(timeStruct.hour >= 13 && timeStruct.hour < 21)
      return "NewYork";

   return "LateNY";
}

//+------------------------------------------------------------------+
//| Timeframe name helper                                            |
//+------------------------------------------------------------------+
string TimeframeName(const ENUM_TIMEFRAMES timeframe)
{
   if(timeframe == PERIOD_M1)  return "M1";
   if(timeframe == PERIOD_M5)  return "M5";
   if(timeframe == PERIOD_M15) return "M15";
   if(timeframe == PERIOD_M30) return "M30";
   if(timeframe == PERIOD_H1)  return "H1";
   if(timeframe == PERIOD_H4)  return "H4";
   if(timeframe == PERIOD_D1)  return "D1";

   return IntegerToString((int)timeframe);
}

//+------------------------------------------------------------------+
//| Update daily balance and PnL ledger                              |
//+------------------------------------------------------------------+
void UpdateDailyRiskRecord()
{
   UpdateWeeklyStartBalance();

   string dates[];
   double balances[];
   double pnls[];
   int recordCount = 0;

   int readHandle = FileOpen(DailyRiskFileName(), FILE_READ | FILE_CSV | FILE_ANSI, ',');
   if(readHandle != INVALID_HANDLE)
   {
      while(!FileIsEnding(readHandle))
      {
         string savedDate = FileReadString(readHandle);
         string savedBalance = FileReadString(readHandle);
         string savedPnl = FileReadString(readHandle);

         if(savedDate == "" || savedDate == "Date")
            continue;

         ArrayResize(dates, recordCount + 1);
         ArrayResize(balances, recordCount + 1);
         ArrayResize(pnls, recordCount + 1);

         dates[recordCount] = savedDate;
         balances[recordCount] = StringToDouble(savedBalance);
         pnls[recordCount] = StringToDouble(savedPnl);
         recordCount++;
      }

      FileClose(readHandle);
   }

   datetime todayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE) + " 00:00");
   string today = TimeToString(todayStart, TIME_DATE);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double pnl = GetRealizedPnlForDay(todayStart, "");

   bool updated = false;
   for(int i = 0; i < recordCount; i++)
   {
      if(dates[i] == today)
      {
         if(balances[i] <= 0.0)
            balances[i] = balance;
         pnls[i] = pnl;
         updated = true;
         break;
      }
   }

   if(!updated)
   {
      ArrayResize(dates, recordCount + 1);
      ArrayResize(balances, recordCount + 1);
      ArrayResize(pnls, recordCount + 1);

      dates[recordCount] = today;
      balances[recordCount] = balance;
      pnls[recordCount] = pnl;
      recordCount++;
   }

   int writeHandle = FileOpen(DailyRiskFileName(), FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(writeHandle == INVALID_HANDLE)
   {
      if(DebugMode) Print("Failed to open daily risk file. error=", GetLastError());
      return;
   }

   FileWrite(writeHandle, "Date", "StartingBalance", "RealizedPnL");
   for(int i = 0; i < recordCount; i++)
      FileWrite(writeHandle, dates[i], DoubleToString(balances[i], 2), DoubleToString(pnls[i], 2));

   FileClose(writeHandle);
}

//+------------------------------------------------------------------+
//| Save weekly starting balance                                     |
//+------------------------------------------------------------------+
void UpdateWeeklyStartBalance()
{
   datetime weekStart = GetWeekStart(TimeCurrent());
   string weekStartText = TimeToString(weekStart, TIME_DATE);

   int readHandle = FileOpen(WeeklyStartFileName(), FILE_READ | FILE_CSV | FILE_ANSI, ',');
   if(readHandle != INVALID_HANDLE)
   {
      while(!FileIsEnding(readHandle))
      {
         string savedWeek = FileReadString(readHandle);
         string savedBalance = FileReadString(readHandle);

         if(savedWeek == "WeekStart")
            continue;

         if(savedWeek == weekStartText)
         {
            FileClose(readHandle);
            return;
         }
      }

      FileClose(readHandle);
   }

   int writeHandle = FileOpen(WeeklyStartFileName(), FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(writeHandle == INVALID_HANDLE)
   {
      if(DebugMode) Print("Failed to open weekly start balance file. error=", GetLastError());
      return;
   }

   if(FileSize(writeHandle) <= 0)
      FileWrite(writeHandle, "WeekStart", "StartingBalance");

   FileSeek(writeHandle, 0, SEEK_END);
   FileWrite(writeHandle, weekStartText, DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
   FileClose(writeHandle);
}

//+------------------------------------------------------------------+
//| Read weekly starting balance                                     |
//+------------------------------------------------------------------+
double GetRecordedWeeklyStartBalance(const datetime weekStart)
{
   string weekStartText = TimeToString(weekStart, TIME_DATE);
   int handle = FileOpen(WeeklyStartFileName(), FILE_READ | FILE_CSV | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
      return 0.0;

   double balance = 0.0;

   while(!FileIsEnding(handle))
   {
      string savedWeek = FileReadString(handle);
      string savedBalance = FileReadString(handle);

      if(savedWeek == "WeekStart")
         continue;

      if(savedWeek == weekStartText)
      {
         balance = StringToDouble(savedBalance);
         break;
      }
   }

   FileClose(handle);
   return balance;
}

//+------------------------------------------------------------------+
//| Realized PnL for one day, optionally one symbol                  |
//+------------------------------------------------------------------+
double GetRealizedPnlForDay(const datetime dayStart, const string symbolFilter)
{
   datetime dayEnd = dayStart + 86400;
   datetime now = TimeCurrent();
   if(dayEnd > now)
      dayEnd = now;

   if(!HistorySelect(dayStart, dayEnd))
      return 0.0;

   double pnl = 0.0;
   int deals = HistoryDealsTotal();

   for(int i = 0; i < deals; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0)
         continue;

      string symbol = HistoryDealGetString(deal, DEAL_SYMBOL);
      if(symbolFilter != "" && symbol != symbolFilter)
         continue;
      if(!IsTrackedSymbol(symbol))
         continue;
      if((ulong)HistoryDealGetInteger(deal, DEAL_MAGIC) != MagicNumber)
         continue;
      if(HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_OUT)
         continue;

      pnl += HistoryDealGetDouble(deal, DEAL_PROFIT)
           + HistoryDealGetDouble(deal, DEAL_SWAP)
           + HistoryDealGetDouble(deal, DEAL_COMMISSION);
   }

   return pnl;
}

//+------------------------------------------------------------------+
//| Monday 00:00 server-time week start                              |
//+------------------------------------------------------------------+
datetime GetWeekStart(const datetime value)
{
   MqlDateTime valueStruct;
   TimeToStruct(value, valueStruct);

   int daysFromMonday = valueStruct.day_of_week - 1;
   if(daysFromMonday < 0)
      daysFromMonday = 6;

   datetime dayStart = StringToTime(TimeToString(value, TIME_DATE) + " 00:00");
   return (dayStart - (daysFromMonday * 86400));
}

//+------------------------------------------------------------------+
//| Weekly account risk cap                                          |
//+------------------------------------------------------------------+
bool IsWeeklyRiskLimitReached()
{
   if(MaxWeeklyLossPercent <= 0.0)
      return false;

   int handle = FileOpen(DailyRiskFileName(), FILE_READ | FILE_CSV | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
      return false;

   datetime weekStart = GetWeekStart(TimeCurrent());
   double weekPnl = 0.0;
   double weekStartBalance = GetRecordedWeeklyStartBalance(weekStart);
   datetime earliestRecord = 0;

   while(!FileIsEnding(handle))
   {
      string savedDate = FileReadString(handle);
      string savedBalance = FileReadString(handle);
      string savedPnl = FileReadString(handle);

      if(savedDate == "" || savedDate == "Date")
         continue;

      datetime recordTime = StringToTime(savedDate + " 00:00");
      if(recordTime < weekStart)
         continue;

      double balance = StringToDouble(savedBalance);
      double pnl = StringToDouble(savedPnl);

      weekPnl += pnl;

      if(weekStartBalance <= 0.0 && (earliestRecord == 0 || recordTime < earliestRecord))
      {
         earliestRecord = recordTime;
         weekStartBalance = balance;
      }
   }

   FileClose(handle);

   if(weekStartBalance <= 0.0)
      weekStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   double maxLoss = weekStartBalance * (MaxWeeklyLossPercent / 100.0);
   return (weekPnl <= -maxLoss);
}

//+------------------------------------------------------------------+
//| Poor weekly performance by symbol                                |
//+------------------------------------------------------------------+
bool IsSymbolWeeklyPerformancePoor(const string symbol)
{
   if(MaxSymbolWeeklyLossPercent <= 0.0)
      return false;

   datetime weekStart = GetWeekStart(TimeCurrent());
   double pnl = 0.0;

   for(int d = 0; d < 7; d++)
   {
      datetime dayStart = weekStart + (d * 86400);
      if(dayStart > TimeCurrent())
         break;
      pnl += GetRealizedPnlForDay(dayStart, symbol);
   }

   double maxLoss = AccountInfoDouble(ACCOUNT_BALANCE) * (MaxSymbolWeeklyLossPercent / 100.0);
   return (pnl <= -maxLoss);
}

//+------------------------------------------------------------------+
//| Learning entry gate                                              |
//+------------------------------------------------------------------+
bool IsLearningBlocked(const string symbol, const ENUM_ORDER_TYPE orderType)
{
   string setupType = SetupTypeName(orderType);

   if(HasSetupFailureBlock(symbol, setupType))
   {
      if(DebugMode) Print("[", symbol, "] Learning blocked setup after repeated failures: ", setupType);
      return true;
   }

   if(HasSymbolLossStreak(symbol))
   {
      if(DebugMode) Print("[", symbol, "] Learning blocked symbol after loss streak.");
      return true;
   }

   if(IsSymbolWeeklyPerformancePoor(symbol))
   {
      if(DebugMode) Print("[", symbol, "] Learning blocked symbol after poor weekly performance.");
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Count setup failures in recent days, block for rest of week      |
//+------------------------------------------------------------------+
bool HasSetupFailureBlock(const string symbol, const string setupType)
{
   int handle = FileOpen(TradeLearningFileName(), FILE_READ | FILE_CSV | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
      return false;

   datetime now = TimeCurrent();
   datetime lookbackStart = now - (LearningLookbackDays * 86400);
   datetime weekStart = GetWeekStart(now);
   int failures = 0;

   while(!FileIsEnding(handle))
   {
      string dateText = FileReadString(handle);
      string savedSymbol = FileReadString(handle);
      string direction = FileReadString(handle);
      string entry = FileReadString(handle);
      string sl = FileReadString(handle);
      string tp = FileReadString(handle);
      string lot = FileReadString(handle);
      string timeframe = FileReadString(handle);
      string atr = FileReadString(handle);
      string spread = FileReadString(handle);
      string session = FileReadString(handle);
      string reason = FileReadString(handle);
      string result = FileReadString(handle);
      string pnl = FileReadString(handle);
      string failureReason = FileReadString(handle);

      if(dateText == "" || dateText == "Date")
         continue;

      datetime recordTime = StringToTime(dateText);
      if(savedSymbol == symbol && reason == setupType && result == "LOSS" && recordTime >= lookbackStart && recordTime >= weekStart)
         failures++;
   }

   FileClose(handle);
   return (failures >= SetupFailureLimit);
}

//+------------------------------------------------------------------+
//| Check last N trades for symbol all losses                        |
//+------------------------------------------------------------------+
bool HasSymbolLossStreak(const string symbol)
{
   if(SymbolLossStreakLimit <= 0)
      return false;

   int handle = FileOpen(TradeLearningFileName(), FILE_READ | FILE_CSV | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
      return false;

   string results[];
   int count = 0;
   datetime weekStart = GetWeekStart(TimeCurrent());

   while(!FileIsEnding(handle))
   {
      string dateText = FileReadString(handle);
      string savedSymbol = FileReadString(handle);
      string direction = FileReadString(handle);
      string entry = FileReadString(handle);
      string sl = FileReadString(handle);
      string tp = FileReadString(handle);
      string lot = FileReadString(handle);
      string timeframe = FileReadString(handle);
      string atr = FileReadString(handle);
      string spread = FileReadString(handle);
      string session = FileReadString(handle);
      string reason = FileReadString(handle);
      string result = FileReadString(handle);
      string pnl = FileReadString(handle);
      string failureReason = FileReadString(handle);

      if(dateText == "" || dateText == "Date")
         continue;

      if(savedSymbol != symbol)
         continue;

      datetime recordTime = StringToTime(dateText);
      if(recordTime < weekStart)
         continue;

      ArrayResize(results, count + 1);
      results[count] = result;
      count++;
   }

   FileClose(handle);

   if(count < SymbolLossStreakLimit)
      return false;

   for(int i = count - 1; i >= count - SymbolLossStreakLimit; i--)
      if(results[i] != "LOSS")
         return false;

   return true;
}

//+------------------------------------------------------------------+
//| Weak support/resistance memory check                             |
//+------------------------------------------------------------------+
bool IsWeakLevelBlocked(const string symbol, const ENUM_ORDER_TYPE orderType, const double level)
{
   int handle = FileOpen(WeakLevelFileName(), FILE_READ | FILE_CSV | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
      return false;

   string setupType = SetupTypeName(orderType);
   double tolerance = 10.0 * PipSize(symbol);
   datetime weekStart = GetWeekStart(TimeCurrent());
   bool blocked = false;

   while(!FileIsEnding(handle))
   {
      string savedDate = FileReadString(handle);
      string savedSymbol = FileReadString(handle);
      string savedSetup = FileReadString(handle);
      string savedLevel = FileReadString(handle);
      string savedReason = FileReadString(handle);

      if(savedDate == "" || savedDate == "Date")
         continue;

      datetime recordTime = StringToTime(savedDate);
      double weakLevel = StringToDouble(savedLevel);

      if(savedSymbol == symbol && savedSetup == setupType && recordTime >= weekStart && MathAbs(level - weakLevel) <= tolerance)
      {
         blocked = true;
         break;
      }
   }

   FileClose(handle);
   return blocked;
}

//+------------------------------------------------------------------+
//| Record weak support/resistance level                             |
//+------------------------------------------------------------------+
void RecordWeakLevel(const string symbol, const ENUM_ORDER_TYPE orderType, const double level, const datetime when, const string reason)
{
   if(level <= 0.0)
      return;

   int handle = FileOpen(WeakLevelFileName(), FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
   {
      if(DebugMode) Print("Failed to open weak level file. error=", GetLastError());
      return;
   }

   if(FileSize(handle) <= 0)
      FileWrite(handle, "Date", "Symbol", "SetupType", "Level", "Reason");

   FileSeek(handle, 0, SEEK_END);
   FileWrite(handle, TimeToString(when, TIME_DATE | TIME_MINUTES), symbol, SetupTypeName(orderType), DoubleToString(level, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)), reason);
   FileClose(handle);
}

//+------------------------------------------------------------------+
//| Save true entry conditions at order open                         |
//+------------------------------------------------------------------+
void RecordEntrySnapshot(const ulong positionId, const string symbol, const ENUM_ORDER_TYPE orderType, const double entryPrice,
                         const double stopLoss, const double takeProfit, const double volume, const double entryATRPips,
                         const double entrySpreadPoints, const datetime entryTime)
{
   if(positionId == 0)
      return;

   string savedReason = "";
   double savedEntry = 0.0;
   double savedSl = 0.0;
   double savedTp = 0.0;
   double savedVolume = 0.0;
   double savedAtr = 0.0;
   double savedSpread = 0.0;
   string savedSession = "";
   string savedSetup = "";
   if(GetEntrySnapshotInfo(positionId, savedReason, savedEntry, savedSl, savedTp, savedVolume, savedAtr, savedSpread, savedSession, savedSetup))
      return;

   int handle = FileOpen(EntrySnapshotFileName(), FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
   {
      if(DebugMode) Print("Failed to open entry snapshot file. error=", GetLastError());
      return;
   }

   if(FileSize(handle) <= 0)
   {
      FileWrite(handle, "PositionID", "Date", "Symbol", "Direction", "Entry", "SL", "TP", "Lot", "Timeframe",
                "ATR_Pips", "Spread_Points", "Session", "ReasonForEntry");
   }

   FileSeek(handle, 0, SEEK_END);
   FileWrite(handle,
             IntegerToString((long)positionId),
             TimeToString(entryTime, TIME_DATE | TIME_MINUTES),
             symbol,
             (orderType == ORDER_TYPE_BUY ? "BUY" : "SELL"),
             DoubleToString(entryPrice, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)),
             DoubleToString(stopLoss, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)),
             DoubleToString(takeProfit, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)),
             DoubleToString(volume, 2),
             TimeframeName(EntryTF),
             DoubleToString(entryATRPips, 1),
             DoubleToString(entrySpreadPoints, 1),
             SessionName(entryTime),
             SetupTypeName(orderType));

   FileClose(handle);
}

//+------------------------------------------------------------------+
//| Load true entry conditions saved at order open                   |
//+------------------------------------------------------------------+
bool GetEntrySnapshotInfo(const ulong positionId, string &reason, double &entryPrice, double &entrySl, double &entryTp,
                          double &entryVolume, double &entryATRPips, double &entrySpreadPoints, string &entrySession, string &setupType)
{
   if(positionId == 0)
      return false;

   int handle = FileOpen(EntrySnapshotFileName(), FILE_READ | FILE_CSV | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
      return false;

   bool found = false;
   string targetPositionId = IntegerToString((long)positionId);

   while(!FileIsEnding(handle))
   {
      string savedPositionId = FileReadString(handle);
      string savedDate = FileReadString(handle);
      string savedSymbol = FileReadString(handle);
      string savedDirection = FileReadString(handle);
      string savedEntry = FileReadString(handle);
      string savedSl = FileReadString(handle);
      string savedTp = FileReadString(handle);
      string savedLot = FileReadString(handle);
      string savedTimeframe = FileReadString(handle);
      string savedAtr = FileReadString(handle);
      string savedSpread = FileReadString(handle);
      string savedSession = FileReadString(handle);
      string savedReason = FileReadString(handle);

      if(savedPositionId == "" || savedPositionId == "PositionID")
         continue;

      if(savedPositionId != targetPositionId)
         continue;

      entryPrice = StringToDouble(savedEntry);
      entrySl = StringToDouble(savedSl);
      entryTp = StringToDouble(savedTp);
      entryVolume = StringToDouble(savedLot);
      entryATRPips = StringToDouble(savedAtr);
      entrySpreadPoints = StringToDouble(savedSpread);
      entrySession = savedSession;
      reason = savedReason;
      setupType = savedReason;
      found = true;
      break;
   }

   FileClose(handle);
   return found;
}

//+------------------------------------------------------------------+
//| Get original entry deal info for a position                      |
//+------------------------------------------------------------------+
bool GetEntryDealInfo(const ulong positionId, string &reason, double &entryPrice, double &entrySl, double &entryTp, double &entryVolume, double &entryATRPips, double &entrySpreadPoints, string &entrySession, string &setupType)
{
   if(GetEntrySnapshotInfo(positionId, reason, entryPrice, entrySl, entryTp, entryVolume, entryATRPips, entrySpreadPoints, entrySession, setupType))
      return true;

   datetime fromTime = TimeCurrent() - (90 * 86400);
   if(!HistorySelect(fromTime, TimeCurrent()))
      return false;

   int deals = HistoryDealsTotal();
   for(int i = 0; i < deals; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0)
         continue;
      if((ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID) != positionId)
         continue;
      if(HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_IN)
         continue;
      if((ulong)HistoryDealGetInteger(deal, DEAL_MAGIC) != MagicNumber)
         continue;

      string symbol = HistoryDealGetString(deal, DEAL_SYMBOL);
      long dealType = HistoryDealGetInteger(deal, DEAL_TYPE);
      ENUM_ORDER_TYPE orderType = (dealType == DEAL_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

      reason = SetupTypeName(orderType);
      setupType = reason;
      entryPrice = HistoryDealGetDouble(deal, DEAL_PRICE);
      entrySl = HistoryDealGetDouble(deal, DEAL_SL);
      entryTp = HistoryDealGetDouble(deal, DEAL_TP);
      entryVolume = HistoryDealGetDouble(deal, DEAL_VOLUME);
      entrySession = SessionName((datetime)HistoryDealGetInteger(deal, DEAL_TIME));

      int idx = FindContextIndex(symbol);
      double atrBuf[1];
      if(idx >= 0 && CopyBuffer(ctx[idx].m15ATR, 0, 1, 1, atrBuf) >= 1)
         entryATRPips = atrBuf[0] / PipSize(symbol);
      else
         entryATRPips = 0.0;

      MqlTick tick;
      if(SymbolInfoTick(symbol, tick))
      {
         double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
         if(point > 0.0)
            entrySpreadPoints = (tick.ask - tick.bid) / point;
      }

      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Failure reason classifier                                        |
//+------------------------------------------------------------------+
string DetermineFailureReason(const string symbol, const string direction, const double pnl, const double exitPrice, const double entrySl, const double entryTp)
{
   if(pnl >= 0.0)
      return "";

   double tolerance = 3.0 * PipSize(symbol);

   if(entrySl > 0.0 && MathAbs(exitPrice - entrySl) <= tolerance)
   {
      if(direction == "BUY")
         return "Price broke support / SL hit";

      return "Price broke resistance / SL hit";
   }

   if(entryTp > 0.0)
   {
      if(direction == "BUY" && exitPrice < entryTp)
         return "Reversal before target";
      if(direction == "SELL" && exitPrice > entryTp)
         return "Reversal before target";
   }

   return "Closed negative after setup failure";
}

//+------------------------------------------------------------------+
//| Save closed trade learning row                                   |
//+------------------------------------------------------------------+
void RecordClosedTradeLearning(const ulong deal)
{
   ulong positionId = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
   string symbol = HistoryDealGetString(deal, DEAL_SYMBOL);
   long dealType = HistoryDealGetInteger(deal, DEAL_TYPE);
   string direction = DirectionNameFromDealType(dealType);
   datetime closeTime = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
   double exitPrice = HistoryDealGetDouble(deal, DEAL_PRICE);
   double pnl = HistoryDealGetDouble(deal, DEAL_PROFIT)
              + HistoryDealGetDouble(deal, DEAL_SWAP)
              + HistoryDealGetDouble(deal, DEAL_COMMISSION);

   string reason = "";
   double entryPrice = 0.0;
   double entrySl = 0.0;
   double entryTp = 0.0;
   double entryVolume = HistoryDealGetDouble(deal, DEAL_VOLUME);
   double entryATRPips = 0.0;
   double entrySpreadPoints = 0.0;
   string entrySession = SessionName(closeTime);
   string setupType = "";

   GetEntryDealInfo(positionId, reason, entryPrice, entrySl, entryTp, entryVolume, entryATRPips, entrySpreadPoints, entrySession, setupType);

   if(reason == "")
      reason = (direction == "BUY") ? SetupTypeName(ORDER_TYPE_BUY) : SetupTypeName(ORDER_TYPE_SELL);

   string result = (pnl < 0.0) ? "LOSS" : "WIN";
   string failureReason = DetermineFailureReason(symbol, direction, pnl, exitPrice, entrySl, entryTp);

   int handle = FileOpen(TradeLearningFileName(), FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
   {
      if(DebugMode) Print("Failed to open trade learning file. error=", GetLastError());
      return;
   }

   if(FileSize(handle) <= 0)
   {
      FileWrite(handle, "Date", "Symbol", "Direction", "Entry", "SL", "TP", "Lot", "Timeframe",
                "ATR_Pips", "Spread_Points", "Session", "ReasonForEntry", "Result", "ProfitLoss", "FailureReason");
   }

   FileSeek(handle, 0, SEEK_END);
   FileWrite(handle,
             TimeToString(closeTime, TIME_DATE | TIME_MINUTES),
             symbol,
             direction,
             DoubleToString(entryPrice, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)),
             DoubleToString(entrySl, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)),
             DoubleToString(entryTp, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)),
             DoubleToString(entryVolume, 2),
             TimeframeName(EntryTF),
             DoubleToString(entryATRPips, 1),
             DoubleToString(entrySpreadPoints, 1),
             entrySession,
             reason,
             result,
             DoubleToString(pnl, 2),
             failureReason);

   FileClose(handle);
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

      if(savedBasket == "" || savedBasket == "BasketKey")
         continue;

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

   if(FileSize(handle) <= 0)
      FileWrite(handle, "BasketKey", "LockTime", "Reason");

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

      if(savedSymbol == "" || savedSymbol == "Symbol")
         continue;

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

   if(FileSize(handle) <= 0)
      FileWrite(handle, "Symbol", "BasketKey", "LossTime", "ProfitLoss");

   FileSeek(handle, 0, SEEK_END);
   FileWrite(handle, symbol, basketKey, TimeToString(lossTime, TIME_DATE | TIME_MINUTES), DoubleToString(pnl, 2));
   FileClose(handle);
}

//+------------------------------------------------------------------+
//| Trade transaction hook for loss cooldown recording               |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0)
      return;

   if(!HistoryDealSelect(trans.deal))
      return;

   string symbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
   if(!IsTrackedSymbol(symbol))
      return;

   if((ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != MagicNumber)
      return;

   long dealEntry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(dealEntry == DEAL_ENTRY_IN)
   {
      if(!UseLearningMemory)
         return;

      string entrySymbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
      int idx = FindContextIndex(entrySymbol);
      long entryDealType = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
      ENUM_ORDER_TYPE entryOrderType = (entryDealType == DEAL_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      double entrySpreadPoints = 0.0;
      double entryATRPips = 0.0;

      MqlTick entryTick;
      if(SymbolInfoTick(entrySymbol, entryTick))
      {
         double point = SymbolInfoDouble(entrySymbol, SYMBOL_POINT);
         if(point > 0.0)
            entrySpreadPoints = (entryTick.ask - entryTick.bid) / point;
      }

      if(idx >= 0)
      {
         double atrAtEntry[1];
         if(CopyBuffer(ctx[idx].m15ATR, 0, 0, 1, atrAtEntry) >= 1)
            entryATRPips = atrAtEntry[0] / PipSize(entrySymbol);
      }

      RecordEntrySnapshot((ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID),
                          entrySymbol,
                          entryOrderType,
                          HistoryDealGetDouble(trans.deal, DEAL_PRICE),
                          HistoryDealGetDouble(trans.deal, DEAL_SL),
                          HistoryDealGetDouble(trans.deal, DEAL_TP),
                          HistoryDealGetDouble(trans.deal, DEAL_VOLUME),
                          entryATRPips,
                          entrySpreadPoints,
                          (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME));
      return;
   }

   if(dealEntry != DEAL_ENTRY_OUT)
      return;

   if(UseLearningMemory)
      RecordClosedTradeLearning(trans.deal);

   double pnl = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
              + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
              + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);

   if(pnl >= 0.0)
      return;

   if(!UseLossCooldown && !UseLearningMemory)
      return;

   long dealType = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
   ENUM_ORDER_TYPE originalOrderType = (dealType == DEAL_TYPE_SELL) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   string basketKey = "";
   string quoteBasketKey = "";
   GetOrderBasketKeys(symbol, originalOrderType, basketKey, quoteBasketKey);
   datetime lossTime = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);

   if(UseLossCooldown)
   {
      RecordLossCooldown(symbol, basketKey, lossTime, pnl);
      if(quoteBasketKey != "")
         RecordLossCooldown(symbol, quoteBasketKey, lossTime, pnl);
   }

   if(UseLearningMemory)
   {
      ulong positionId = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
      string reason = "";
      double entryPrice = 0.0;
      double entrySl = 0.0;
      double entryTp = 0.0;
      double entryVolume = 0.0;
      double entryATRPips = 0.0;
      double entrySpreadPoints = 0.0;
      string entrySession = "";
      string setupType = "";
      if(GetEntryDealInfo(positionId, reason, entryPrice, entrySl, entryTp, entryVolume, entryATRPips, entrySpreadPoints, entrySession, setupType))
         RecordWeakLevel(symbol, originalOrderType, entrySl, lossTime, "loss_after_entry");
   }

   if(DebugMode)
      Print("[", symbol, "] Loss cooldown recorded for ", basketKey, " / ", quoteBasketKey, " pnl=", pnl);
}
//+------------------------------------------------------------------+
