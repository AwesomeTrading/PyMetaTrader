//+------------------------------------------------------------------+
//|                                                      ProjectName |
//|                                      Copyright 2018, CompanyName |
//|                                       http://www.companyname.net |
//+------------------------------------------------------------------+

#include  "Helper.mqh"
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class Instrument
  {
protected:
   string            symbol;
   ENUM_TIMEFRAMES   timeframe;

public:
   string            getSymbol()    { return symbol; }
   ENUM_TIMEFRAMES   getTimeframe() { return timeframe; }

   void              Instrument()
     {
      symbol = "";
      timeframe = PERIOD_CURRENT;
     }

   void              setup(string arg_symbol, ENUM_TIMEFRAMES arg_timeframe)
     {
      symbol = arg_symbol;
      timeframe = arg_timeframe;
     }

   bool              equal(string arg_symbol, ENUM_TIMEFRAMES arg_timeframe)
     {
      return this.symbol == arg_symbol && this.timeframe == arg_timeframe;
     }

   int               GetRates(MqlRates& rates[], int count)
     {
      if(StringLen(symbol) == 0)
         return 0;

      return CopyRates(symbol, timeframe, 0, count, rates);
     }
  };


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class MTMarkets
  {

private:
   string            symbols[];
   Instrument        instruments[];

   void              parseRate(MqlRates& rate, string &result);
   void              parseMarketInfo(string symbol, string &result);

public:
   void              MTMarkets();
   bool              getMarkets(string &result);
   bool              getHistory(string symbol, ENUM_TIMEFRAMES period, datetime startTime, datetime endTime, string &result);

   bool              subscribeBar(string symbol, ENUM_TIMEFRAMES period);
   bool              unsubscribeBar(string symbol, ENUM_TIMEFRAMES period);
   bool              hasBarSubscribers(void);
   void              clearBarSubscribers(void);
   bool              getLastBars(string &result);

   bool              subscribeQuote(string symbol);
   bool              unsubscribeQuote(string symbol);
   bool              hasQuoteSubscribers(void);
   void              clearQuoteSubscribers(void);
   bool              getLastQuotes(string &result);
  };

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTMarkets::MTMarkets()
  {
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTMarkets::getMarkets(string &result)
  {
   int total = SymbolsTotal(false);
   if(total == 0)
      return true;

   for(int i = 0; i< total; i++)
     {
      string symbol = SymbolName(i, false);
      this.parseMarketInfo(symbol, result);
     }

   if(total > 0)
     {
      result = StringSubstr(result, 0, StringLen(result)-1);
     }
   return true;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTMarkets::getHistory(string symbol, ENUM_TIMEFRAMES period, datetime startTime, datetime endTime, string &result)
  {
   MqlRates ratesArray[];
   int ratesCount = 0;

// Handling ERR_HISTORY_WILL_UPDATED (4066) and ERR_NO_HISTORY_DATA (4073) errors.
// For non-chart symbols and time frames MT4 often needs a few requests until the data is available.
// But even after 10 requests it can happen that it is not available. So it is best to have the charts open.
   for(int i=0; i<10; i++)
     {
      ratesCount = CopyRates(symbol, period, startTime, endTime, ratesArray);
      int errorCode = GetLastError();
      // Print("errorCode: ", errorCode);
      if(ratesCount > 0 || (errorCode != 4066 && errorCode != 4073))
         break;

      Sleep(200);
     }

// cannot load history data
   if(ratesCount <= 0)
      return false;

// add history to response string
   for(int i = 0; i < ratesCount; i++)
     {
      this.parseRate(ratesArray[i], result);
     }

   if(ratesCount > 0)
     {
      result = StringSubstr(result, 0, StringLen(result)-1);
     }
   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTMarkets::subscribeBar(string symbol, ENUM_TIMEFRAMES period)
  {
   int size = ArraySize(this.instruments);
   for(int i = 0; i < size; i++)
     {
      if(this.instruments[i].equal(symbol, period))
         return true;
     }

   ArrayResize(this.instruments, size +1);
   this.instruments[size].setup(symbol, period);
   return true;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTMarkets::unsubscribeBar(string symbol, ENUM_TIMEFRAMES period)
  {
   int size = ArraySize(this.instruments);
   bool shift = false;
   for(int i = 0; i < size; i++)
     {
      Instrument instrument = this.instruments[i];

      // replace instrument
      if(shift)
        {
         this.instruments[i - 1] = instrument;
         continue;
        }

      // find instrument
      if(instrument.equal(symbol, period))
        {
         shift= true;
         continue;
        }
     }

   if(shift)
     {
      ArrayResize(this.instruments, size -1);
     }
   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTMarkets::hasBarSubscribers(void)
  {
   return ArraySize(this.instruments) > 0;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTMarkets::clearBarSubscribers(void)
  {
   ArrayResize(this.instruments, 0);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTMarkets::getLastBars(string &result)
  {
   MqlRates rates[1];
   int size = ArraySize(this.instruments);

   for(int i = 0; i < size; i++)
     {
      Instrument instrument = this.instruments[i];
      instrument.GetRates(rates, 1);
      StringAdd(result, StringFormat("%s|%s|",
                                     instrument.getSymbol(),
                                     GetTimeframeText(instrument.getTimeframe())));
      this.parseRate(rates[0], result);
     }

   if(size > 0)
     {
      result = StringSubstr(result, 0, StringLen(result)-1);
     }
   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTMarkets::parseRate(MqlRates& rate, string &result)
  {
   StringAdd(result, StringFormat("%s|%g|%g|%g|%g|%d|%d|%d;",
                                  TimeToString(rate.time, TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                                  rate.open,
                                  rate.high,
                                  rate.low,
                                  rate.close,
                                  rate.tick_volume,
                                  rate.spread,
                                  rate.real_volume));
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTMarkets::subscribeQuote(string symbol)
  {
   int size = ArraySize(this.symbols);
   for(int i = 0; i < size; i++)
     {
      if(this.symbols[i] == symbol)
         return true;
     }

   ArrayResize(this.symbols, size +1);
   this.symbols[size] = symbol;
   return true;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTMarkets::unsubscribeQuote(string symbol)
  {
   ArrayRemove(this.symbols, symbol);
   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTMarkets::hasQuoteSubscribers(void)
  {
   return ArraySize(this.symbols) > 0;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTMarkets::clearQuoteSubscribers(void)
  {
   ArrayResize(this.symbols, 0);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTMarkets::getLastQuotes(string &result)
  {
   int size = ArraySize(this.symbols);
   for(int i = 0; i < size; i++)
     {
      string symbol = this.symbols[i];
      this.parseMarketInfo(symbol, result);
     }

   if(size > 0)
     {
      result = StringSubstr(result, 0, StringLen(result)-1);
     }
   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTMarkets::parseMarketInfo(string symbol, string &result)
  {
// SYMBOL|SYMBOL_DESCRIPTION|SYMBOL_CURRENCY_BASE|MODE_LOW|MODE_HIGH|MODE_BID|MODE_ASK|MODE_POINT|MODE_DIGITS|MODE_SPREAD|MODE_TICKSIZE|MODE_MINLOT|MODE_LOTSTEP|MODE_MAXLOT
   StringAdd(result, StringFormat("%s|%s|%s|%g|%g|%g|%g|%g|%g|%g|%g|%g|%g|%g;",
                                  symbol,
                                  SymbolInfoString(symbol, SYMBOL_DESCRIPTION),
                                  SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE),
                                  MarketInfo(symbol, MODE_LOW),
                                  MarketInfo(symbol, MODE_HIGH),
                                  MarketInfo(symbol, MODE_BID),
                                  MarketInfo(symbol, MODE_ASK),
                                  MarketInfo(symbol, MODE_POINT),
                                  MarketInfo(symbol, MODE_DIGITS),
                                  MarketInfo(symbol, MODE_SPREAD),
                                  MarketInfo(symbol, MODE_TICKSIZE),
                                  MarketInfo(symbol, MODE_MINLOT),
                                  MarketInfo(symbol, MODE_LOTSTEP),
                                  MarketInfo(symbol, MODE_MAXLOT)
                                 ));
  }
//+------------------------------------------------------------------+
