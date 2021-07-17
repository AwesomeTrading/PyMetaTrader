//+------------------------------------------------------------------+
//|                                                      ProjectName |
//|                                      Copyright 2018, CompanyName |
//|                                       http://www.companyname.net |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class Instrument
  {

protected:
   string            symbol;
   ENUM_TIMEFRAMES   timeframe;
   //datetime lastUpdate;

public:

   void              Instrument()
     {
      symbol = "";
      timeframe = PERIOD_CURRENT;
      // lastUpdate = 0;
     }


   string            getSymbol()    { return symbol; }
   ENUM_TIMEFRAMES   getTimeframe() { return timeframe; }
   // datetime        getLastPublishTimestamp() { return lastUpdate; }
   // void            setLastPublishTimestamp(datetime tmstmp) { _last_pub_rate = tmstmp; }


   void              setup(string arg_symbol, ENUM_TIMEFRAMES arg_timeframe)
     {
      symbol = arg_symbol;
      timeframe = arg_timeframe;
      //_last_pub_rate = 0;
     }

   //--------------------------------------------------------------
   /** Get last N MqlRates from this instrument (symbol-timeframe)
    *  @param rates Receives last 'count' rates
    *  @param count Number of requested rates
    *  @return Number of returned rates
    */
   int               GetRates(MqlRates& rates[], int count)
     {
      // ensures that symbol is setup
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
public:
   void              MTMarkets();
   bool              history(string symbol, ENUM_TIMEFRAMES period, datetime startTime, datetime endTime, string &result);
   bool              subscribeBar(string symbol, ENUM_TIMEFRAMES period);
   bool              subscribeTicker(string symbol);
   bool              getMarkets(string &result);
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

   result = StringSubstr(result, 0, StringLen(result)-1);
   return true;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTMarkets::history(string symbol, ENUM_TIMEFRAMES period, datetime startTime, datetime endTime, string &result)
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
      StringAdd(result, StringFormat("%s|%g|%g|%g|%g|%d|%d|%d;",
                                     TimeToString(ratesArray[i].time, TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                                     ratesArray[i].open,
                                     ratesArray[i].high,
                                     ratesArray[i].low,
                                     ratesArray[i].close,
                                     ratesArray[i].tick_volume,
                                     ratesArray[i].spread,
                                     ratesArray[i].real_volume));
     }

   result = StringSubstr(result, 0, StringLen(result)-1);
   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTMarkets::subscribeBar(string symbol, ENUM_TIMEFRAMES period)
  {
   int size = ArraySize(this.instruments);
   ArrayResize(this.instruments, size +1);
   this.instruments[size].setup(symbol, period);
   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTMarkets::subscribeTicker(string symbol)
  {
   int size = ArraySize(this.symbols);
   ArrayResize(this.symbols, size +1);
   this.symbols[size] = symbol;
   return true;
  }

//+------------------------------------------------------------------+
