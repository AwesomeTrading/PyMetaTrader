//+------------------------------------------------------------------+
//|                                                      ProjectName |
//|                                      Copyright 2018, CompanyName |
//|                                       http://www.companyname.net |
//+------------------------------------------------------------------+

#include "Helper.mqh"
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class Instrument {
 protected:
  string             symbol;
  ENUM_TIMEFRAMES    timeframe;

 public:
  string             getSymbol() {
    return symbol;
  }
  ENUM_TIMEFRAMES    getTimeframe() {
    return timeframe;
  }

  void               Instrument() {
    symbol = "";
    timeframe = PERIOD_CURRENT;
  }

  void               setup(string arg_symbol, ENUM_TIMEFRAMES arg_timeframe) {
    symbol = arg_symbol;
    timeframe = arg_timeframe;
  }

  bool               equal(string arg_symbol, ENUM_TIMEFRAMES arg_timeframe) {
    return this.symbol == arg_symbol && this.timeframe == arg_timeframe;
  }

  int                GetRates(MqlRates &rates[], int count) {
    if (StringLen(symbol) == 0)
      return 0;

    return CopyRates(symbol, timeframe, 0, count, rates);
  }
};

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class MTMarkets {
 private:
  string             symbols[];
  Instrument         instruments[];

  void               parseRate(string &result, MqlRates &rate, bool prefix);
  void               parseMarket(string &result, string symbol, bool prefix);
  void               parseQuote(string &result, string symbol, bool prefix);
  string             getMarketSessions(string symbol);
  void               barBuilding(string &result, string symbol, ENUM_TIMEFRAMES period, MqlRates &rate, bool prefix);

 public:
  void               MTMarkets();
  bool               getMarkets(string &result);

  bool               getBars(string &result, string symbol, ENUM_TIMEFRAMES period, datetime startTime, datetime endTime);
  bool               subscribeBar(string symbol, ENUM_TIMEFRAMES period);
  bool               unsubscribeBar(string symbol, ENUM_TIMEFRAMES period);
  bool               hasBarSubscribers(void);
  void               clearBarSubscribers(void);
  bool               getLastBars(string &result);

  bool               getQuotes(string &result);
  bool               subscribeQuote(string symbol);
  bool               unsubscribeQuote(string symbol);
  bool               hasQuoteSubscribers(void);
  void               clearQuoteSubscribers(void);
  bool               getLastQuotes(string &result);
};

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTMarkets::MTMarkets() {
}

//+------------------------------------------------------------------+
//| MARKETS                                                          |
//+------------------------------------------------------------------+
bool MTMarkets::getMarkets(string &result) {
#ifdef __MQL4__
  RefreshRates();
#endif

  int total = SymbolsTotal(false);
  if (total == 0)
    return true;

  for (int i = 0; i < total; i++) {
    string symbol = SymbolName(i, false);
    this.parseMarket(result, symbol, i > 0);
  }
  return true;
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTMarkets::parseMarket(string &result, string symbol, bool prefix = false) {
#ifdef __MQL4__
  string desc = SymbolInfoString(symbol, SYMBOL_DESCRIPTION);
  string currencyBase = SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE);
  string currencyProfit = SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT);
  string currencyMargin = SymbolInfoString(symbol, SYMBOL_CURRENCY_MARGIN);
  double point = MarketInfo(symbol, MODE_POINT);
  double digits = MarketInfo(symbol, MODE_DIGITS);
  double minlot = MarketInfo(symbol, MODE_MINLOT);
  double lotstep = MarketInfo(symbol, MODE_LOTSTEP);
  double maxlot = MarketInfo(symbol, MODE_MAXLOT);
  double lotsize = MarketInfo(symbol, MODE_LOTSIZE);
  double ticksize = MarketInfo(symbol, MODE_TICKSIZE);
  double tickvalue = MarketInfo(symbol, MODE_TICKVALUE);

// bypass: error when get MarketInfo with symbol not in MarketWatch
  GetLastError();
#endif
#ifdef __MQL5__
  string desc = SymbolInfoString(symbol, SYMBOL_DESCRIPTION);
  string exchange = SymbolInfoString(symbol, SYMBOL_EXCHANGE);
  string category = SymbolInfoString(symbol, SYMBOL_CATEGORY);
  string country = SymbolInfoString(symbol, SYMBOL_COUNTRY);
  string path = SymbolInfoString(symbol, SYMBOL_PATH);
  string isin = SymbolInfoString(symbol, SYMBOL_ISIN);
  string currencyBase = SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE);
  string currencyProfit = SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT);
  string currencyMargin = SymbolInfoString(symbol, SYMBOL_CURRENCY_MARGIN);
  double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
  long digits = SymbolInfoInteger(symbol, SYMBOL_DIGITS);
  double minlot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
  double lotstep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
  double maxlot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
  double lotsize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
  double ticksize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
  double tickvalue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
  double swapLong = SymbolInfoDouble(symbol, SYMBOL_SWAP_LONG);
  double swapShort = SymbolInfoDouble(symbol, SYMBOL_SWAP_SHORT);
  long swapRollover = SymbolInfoInteger(symbol, SYMBOL_SWAP_ROLLOVER3DAYS);
#endif

  if (prefix)
    StringAdd(result, ";");

  StringAdd(result, StringFormat("symbol=%s", symbol));
  StringAdd(result, StringFormat("|description=%s", desc));
  StringAdd(result, StringFormat("|exchange=%s", exchange));
  StringAdd(result, StringFormat("|category=%s", category));
  StringAdd(result, StringFormat("|country=%s", country));
  StringAdd(result, StringFormat("|path=%s", path));
  StringAdd(result, StringFormat("|isin=%s", isin));
  StringAdd(result, StringFormat("|currencybase=%s", currencyBase));
  StringAdd(result, StringFormat("|currencyprofit=%s", currencyProfit));
  StringAdd(result, StringFormat("|currencymargin=%s", currencyMargin));
  StringAdd(result, StringFormat("|point=%g", point));
  StringAdd(result, StringFormat("|digits=%g", digits));
  StringAdd(result, StringFormat("|minlot=%g", minlot));
  StringAdd(result, StringFormat("|lotstep=%g", lotstep));
  StringAdd(result, StringFormat("|maxlot=%g", maxlot));
  StringAdd(result, StringFormat("|lotsize=%g", lotsize));
  StringAdd(result, StringFormat("|ticksize=%g", ticksize));
  StringAdd(result, StringFormat("|tickvalue=%g", tickvalue));
  StringAdd(result, StringFormat("|swaplong=%g", swapLong));
  StringAdd(result, StringFormat("|swapshort=%g", swapShort));
  StringAdd(result, StringFormat("|swaprollover=%g", swapRollover));
  StringAdd(result, StringFormat("|session=%s", this.getMarketSessions(symbol)));
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string MTMarkets::getMarketSessions(string symbol) {
  string result = "";
  int errorCode = GetLastError();
  if (errorCode != 0)
    PrintFormat("[ERROR] %s %d %s", symbol, errorCode, GetErrorDescription(errorCode));

  datetime openSession, closeSession;
  uint session;
  for (ENUM_DAY_OF_WEEK day = SUNDAY; day <= SATURDAY; day++) {
    session = 0;
    while (SymbolInfoSessionTrade(symbol, day, session, openSession, closeSession)) {
      if (result != "")
        StringAdd(result, "!");

      StringAdd(result, StringFormat("%g~%d-%d",
                                     day,
                                     openSession,
                                     closeSession));
      session++;
    }
  }
  ResetLastError();
  return result;
}

//+------------------------------------------------------------------+
//| QUOTES                                                           |
//+------------------------------------------------------------------+
bool MTMarkets::getQuotes(string &result) {
#ifdef __MQL4__
  RefreshRates();
#endif

  int total = SymbolsTotal(true);
  if (total == 0)
    return true;

  for (int i = 0; i < total; i++) {
    string symbol = SymbolName(i, true);
    this.parseQuote(result, symbol, i > 0);
  }
  return true;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTMarkets::subscribeQuote(string symbol) {
  if (!MarketIsOpen(symbol))
    return false;

  int size = ArraySize(this.symbols);
  for (int i = 0; i < size; i++) {
    if (this.symbols[i] == symbol)
      return true;
  }

  ArrayResize(this.symbols, size + 1);
  this.symbols[size] = symbol;
  return true;
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTMarkets::unsubscribeQuote(string symbol) {
  ArrayRemove(this.symbols, symbol);
  return true;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTMarkets::hasQuoteSubscribers(void) {
  return ArraySize(this.symbols) > 0;
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTMarkets::clearQuoteSubscribers(void) {
  ArrayResize(this.symbols, 0);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTMarkets::getLastQuotes(string &result) {
#ifdef __MQL4__
  RefreshRates();
#endif

  int total = ArraySize(this.symbols);
  for (int i = 0; i < total; i++) {
    string symbol = this.symbols[i];
    this.parseQuote(result, symbol, i > 0);
  }
  return true;
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTMarkets::parseQuote(string &result, string symbol, bool prefix = false) {
#ifdef __MQL4__
  double bid = MarketInfo(symbol, MODE_BID);
  double ask = MarketInfo(symbol, MODE_ASK);
  double spread = MarketInfo(symbol, MODE_SPREAD);
  double digits = MarketInfo(symbol, MODE_DIGITS);
#endif
#ifdef __MQL5__
  MqlTick lastTick;
  SymbolInfoTick(symbol, lastTick);

  double bid = lastTick.bid;
  double ask = lastTick.ask;
  double spread = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
  int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
#endif

  double last = NormalizeDouble((bid + ask) / 2, digits);
  double open = iOpen(symbol, PERIOD_D1, 0);
  double high = iHigh(symbol, PERIOD_D1, 0);
  double low = iLow(symbol, PERIOD_D1, 0);
  double close = iClose(symbol, PERIOD_D1, 0);
  long volume = iVolume(symbol, PERIOD_D1, 0);

// bypass: skip download bar data if missing data
  ResetLastError();

  double prevClose = iClose(symbol, PERIOD_D1, 1);
  double change = close - prevClose;
  double changePercent = 0;
  if (prevClose > 0)
    changePercent = (close - prevClose) / prevClose * 100;

  if (prefix)
    StringAdd(result, ";");

  StringAdd(result, StringFormat("symbol=%s", symbol));
  StringAdd(result, StringFormat("|open=%g", open));
  StringAdd(result, StringFormat("|high=%g", high));
  StringAdd(result, StringFormat("|low=%g", low));
  StringAdd(result, StringFormat("|close=%g", close));
  StringAdd(result, StringFormat("|volume=%g", volume));
  StringAdd(result, StringFormat("|bid=%g", bid));
  StringAdd(result, StringFormat("|ask=%g", ask));
  StringAdd(result, StringFormat("|last=%g", last));
  StringAdd(result, StringFormat("|spread=%g", spread));
  StringAdd(result, StringFormat("|prev_close=%g", prevClose));
  StringAdd(result, StringFormat("|change=%g", change));
  StringAdd(result, StringFormat("|change_percent=%g", changePercent));
}

//+------------------------------------------------------------------+
//| BARS                                                             |
//+------------------------------------------------------------------+
bool MTMarkets::getBars(string &result, string symbol, ENUM_TIMEFRAMES period, datetime startTime, datetime endTime) {
  MqlRates rates[];
  int total = 0;
  if (endTime > TimeTradeServer())
    endTime = TimeTradeServer();

// Handling ERR_HISTORY_WILL_UPDATED (4066) and ERR_NO_HISTORY_DATA (4073) errors.
// For non-chart symbols and time frames MT4 often needs a few requests until the data is available.
// But even after 10 requests it can happen that it is not available. So it is best to have the charts open.
  for (int i = 0; i < 5; i++) {
    total = CopyRates(symbol, period, startTime, endTime, rates);
    int errorCode = GetLastError();
    if (errorCode != 0)
      PrintFormat("[ERROR] getBars: %d %s", errorCode, GetErrorDescription(errorCode));

    if (total > 0 || (errorCode != 4066 && errorCode != 4073))
      break;

    Sleep(200);
  }

// cannot load history data
  if (total <= 0)
    return false;

// add history to response string
  for (int i = 0; i < total; i++) {
    this.parseRate(result, rates[i], i > 0);
  }

// add bar building status
  this.barBuilding(result, symbol, period, rates[total - 1], true);

  return true;
}
//
bool MTMarkets::subscribeBar(string symbol, ENUM_TIMEFRAMES period) {
  if (!MarketIsOpen(symbol))
    return false;

  int size = ArraySize(this.instruments);
  for (int i = 0; i < size; i++) {
    if (this.instruments[i].equal(symbol, period))
      return true;
  }

  ArrayResize(this.instruments, size + 1);
  this.instruments[size].setup(symbol, period);
  return true;
}
//
bool MTMarkets::unsubscribeBar(string symbol, ENUM_TIMEFRAMES period) {
  int size = ArraySize(this.instruments);
  bool shift = false;
  for (int i = 0; i < size; i++) {
    Instrument instrument = this.instruments[i];

    // replace instrument
    if (shift) {
      this.instruments[i - 1] = instrument;
      continue;
    }

    // find instrument
    if (instrument.equal(symbol, period)) {
      shift = true;
      continue;
    }
  }

  if (shift) {
    ArrayResize(this.instruments, size - 1);
  }
  return true;
}
//
bool MTMarkets::hasBarSubscribers(void) {
  return ArraySize(this.instruments) > 0;
}
//
void MTMarkets::clearBarSubscribers(void) {
  ArrayResize(this.instruments, 0);
}
//
bool MTMarkets::getLastBars(string &result) {
  MqlRates rates[1];
  int total = ArraySize(this.instruments);

  Instrument instrument;
  for (int i = 0; i < total; i++) {
    instrument = this.instruments[i];
    instrument.GetRates(rates, 1);
    if (i > 0)
      StringAdd(result, ";");

    StringAdd(result, StringFormat("%s|%s|",
                                   instrument.getSymbol(),
                                   GetTimeframeText(instrument.getTimeframe())));
    this.parseRate(result, rates[0], false);
  }
  return true;
}
//
void MTMarkets::parseRate(string &result, MqlRates &rate, bool prefix = true) {
  if (prefix)
    StringAdd(result, ";");
  StringAdd(result, StringFormat("%f|%g|%g|%g|%g|%g|%g|%g",
                                 rate.time,
                                 rate.open,
                                 rate.high,
                                 rate.low,
                                 rate.close,
                                 rate.tick_volume,
                                 rate.spread,
                                 rate.real_volume));
}

//
void MTMarkets::barBuilding(string &result, string symbol, ENUM_TIMEFRAMES period, MqlRates &rate, bool prefix = true) {
  long lastBarTime = SeriesInfoInteger(symbol, period, SERIES_LASTBAR_DATE);
  if (lastBarTime != rate.time)
    return;

  if (prefix)
    StringAdd(result, ";");

  StringAdd(result, "building");
}
//+------------------------------------------------------------------+
