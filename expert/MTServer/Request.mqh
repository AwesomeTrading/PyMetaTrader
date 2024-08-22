//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+

#include <Zmq/Zmq.mqh>

#include "Account.mqh"
#include "Helper.mqh"
#include "Markets.mqh"

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::flushMarketSubscriptions() {
  this.publicSubscriptionBars();
  this.publicSubscriptionQuotes();
  this.publicSubscriptionTicks();
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::publicSubscriptionBars() {
  if(!this.markets.hasBarSubscribers())
    return true;

  string result = "BARS ";
  this.markets.getLastBars(result);
  return this.reply(clientPubSocket, result);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::publicSubscriptionQuotes() {
  if(!this.markets.hasQuoteSubscribers())
    return true;

  string result = "QUOTES ";
  this.markets.getLastQuotes(result);
  return this.reply(clientPubSocket, result);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::publicSubscriptionTicks() {
  if(!this.markets.hasTickSubscribers())
    return true;

  string result = "TICKS ";
  this.markets.getLastTicks(result);
  return this.reply(clientPubSocket, result);
}

//+------------------------------------------------------------------+
//|  PING                                                            |
//+------------------------------------------------------------------+
bool MTServer::processRequestPing(string &params[]) {
  string result = "PONG";
  return this.requestReply(params[1], result);
}

//+------------------------------------------------------------------+
//| MARKET BARS                                                      |
//+------------------------------------------------------------------+
bool MTServer::processRequestBars(string &params[]) {
  string symbol = params[2];
  ENUM_TIMEFRAMES period = GetTimeframe(params[3]);
  datetime startTime = TimestampToGMTTime(params[4]);
  datetime endTime = TimestampToGMTTime(params[5]);

  string result = "";
  this.markets.getBars(result, symbol, period, startTime, endTime);
  return this.requestReply(params[1], result);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::processRequestSubBars(string &params[]) {
  string symbol = params[2];
  ENUM_TIMEFRAMES period = GetTimeframe(params[3]);
  this.markets.subscribeBar(symbol, period);
  string result = "OK";
  return this.requestReply(params[1], result);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::processRequestUnsubBars(string &params[]) {
  string symbol = params[2];
  ENUM_TIMEFRAMES period = GetTimeframe(params[3]);
  this.markets.unsubscribeBar(symbol, period);

  string result = "OK";
  return this.requestReply(params[1], result);
}

//+------------------------------------------------------------------+
//| MARKET QUOTES                                                    |
//+------------------------------------------------------------------+
bool MTServer::processRequestQuotes(string &params[]) {
  string result = "";
  this.markets.getQuotes(result);
  return this.requestReply(params[1], result);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::processRequestSubQuotes(string &params[]) {
  int size = ArraySize(params);

  string symbol;
  for(int i = 2; i < size; i++) {
    symbol= params[i];
    this.markets.subscribeQuote(symbol);
  }

  string result = "OK";
  return this.requestReply(params[1], result);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::processRequestUnsubQuotes(string &params[]) {
  int size = ArraySize(params);

  string symbol;
  for(int i = 2; i < size; i++) {
    symbol= params[i];
    this.markets.unsubscribeQuote(symbol);
  }

  string result = "OK";
  return this.requestReply(params[1], result);
}

//+------------------------------------------------------------------+
//| MARKET TICKS                                                     |
//+------------------------------------------------------------------+
bool MTServer::processRequestTicks(string &params[]) {
  string result = "";
  this.markets.getTicks(result);
  return this.requestReply(params[1], result);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::processRequestSubTicks(string &params[]) {
  string symbol = params[2];
  this.markets.subscribeTick(symbol);

  string result = "OK";
  return this.requestReply(params[1], result);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::processRequestUnsubTicks(string &params[]) {
  string symbol = params[2];
  this.markets.unsubscribeTick(symbol);

  string result = "OK";
  return this.requestReply(params[1], result);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::processRequestUnsubAll(string &params[]) {
  Print("Clear all subscribers");

  this.markets.clearBarSubscribers();
  this.markets.clearQuoteSubscribers();

// Unsubscribe and doesn't response anything
  return true;
}

//+------------------------------------------------------------------+
//| MARKET TIME                                                      |
//+------------------------------------------------------------------+
bool MTServer::processRequestTime(string &params[]) {
  string result = StringFormat("%f", TimeTradeServer());
  return this.requestReply(params[1], result);
}

//+------------------------------------------------------------------+
//| MARKETS                                                          |
//+------------------------------------------------------------------+
bool MTServer::processRequestMarkets(string &params[]) {
  string result = "";
  this.markets.getMarkets(result);
  return this.requestReply(params[1], result);
}

//+------------------------------------------------------------------+
//| ACCOUNT                                                          |
//+------------------------------------------------------------------+
bool MTServer::processRequestAccount(string &params[]) {
  string result = "";
  this.account.getAccount(result);
  return this.requestReply(params[1], result);
}

//+------------------------------------------------------------------+
//| FUND                                                             |
//+------------------------------------------------------------------+
bool MTServer::processRequestFund(string &params[]) {
  string result = "";
  this.account.getFund(result);
  return this.requestReply(params[1], result);
}

//+------------------------------------------------------------------+
//| ORDERS                                                           |
//+------------------------------------------------------------------+
bool MTServer::processRequestOrders(string &params[]) {
  string symbol = params[2];
  string result = "";
  this.account.getOrders(result, symbol);
  return this.requestReply(params[1], result);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::processRequestOpenOrder(string &params[]) {
  string symbol = params[2];
  int type = StringToOperationType(params[3]);
  double lots = StringToDouble(params[4]);
  double price = StringToDouble(params[5]);
  double sl = StringToDouble(params[6]);
  double tp = StringToDouble(params[7]);
  string comment = params[8];

  string result = "";
  ulong ticket = this.account.openOrder(result, symbol, type, lots, price, sl, tp, comment);

  StringAdd(result, IntegerToString(ticket));
  return this.requestReply(params[1], result);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::processRequestModifyOrder(string &params[]) {
#ifdef __MQL4__
  ulong ticket = StrToInteger(params[2]);
#endif
#ifdef __MQL5__
  ulong ticket = StringToInteger(params[2]);
#endif

  double price = StringToDouble(params[3]);
  double sl = StringToDouble(params[4]);
  double tp = StringToDouble(params[5]);
  datetime expiration = TimestampToGMTTime(params[6]);

// process
  string result = "";
  this.account.modifyOrder(result, ticket, price, sl, tp, expiration);
  return this.requestReply(params[1], result);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::processRequestCancelOrder(string &params[]) {
#ifdef __MQL4__
  ulong ticket = StrToInteger(params[2]);
#endif
#ifdef __MQL5__
  ulong ticket = StringToInteger(params[2]);
#endif

  string result = "";
  this.account.cancelOrder(result, ticket);
  return this.requestReply(params[1], result);
}

//+------------------------------------------------------------------+
//| TRADES                                                           |
//+------------------------------------------------------------------+
bool MTServer::processRequestTrades(string &params[]) {
  string symbol = params[2];
  string result = "";
  this.account.getTrades(result, symbol);
  return this.requestReply(params[1], result);
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::processRequestModifyTrade(string &params[]) {
#ifdef __MQL4__
  ulong ticket = StrToInteger(params[2]);
#endif
#ifdef __MQL5__
  ulong ticket = StringToInteger(params[2]);
#endif
  double sl = StringToDouble(params[3]);
  double tp = StringToDouble(params[4]);

// process
  string result = "";
  this.account.modifyTrade(result, ticket, sl, tp);
  return this.requestReply(params[1], result);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::processRequestCloseTrade(string &params[]) {
#ifdef __MQL4__
  ulong ticket = StrToInteger(params[2]);
#endif
#ifdef __MQL5__
  ulong ticket = StringToInteger(params[2]);
#endif
  string result = "";
  this.account.closeTrade(result, ticket);
  return this.requestReply(params[1], result);
}
//+------------------------------------------------------------------+
//| DEALS                                                            |
//+------------------------------------------------------------------+
bool MTServer::processRequestDeals(string &params[]) {
  string symbol = params[2];
  datetime fromDate = TimestampToGMTTime(params[3]);

  string result = "";
  this.account.getHistoryDeals(result, symbol, fromDate);
  return this.requestReply(params[1], result);
}

//+------------------------------------------------------------------+
//| REFRESH TRADES                                                   |
//+------------------------------------------------------------------+
bool MTServer::publicRequestRefreshTrades(datetime fromDate, datetime toDate) {
// datetime fromDate = TimestampToGMTTime(fromTime);
// datetime toDate = TimestampToGMTTime(toTime);

  this.account.refresh();

// History orders
  string historyOrders = "HISTORY_ORDERS ";
  this.account.getHistoryOrders(historyOrders, "", fromDate, toDate);

// History deals
  string historyDeals = "HISTORY_DEALS ";
  this.account.getHistoryDeals(historyDeals, "", fromDate, toDate);

// Open orders
  string orders = "ORDERS ";
  this.account.getOrders(orders);

// Trades
  string trades = "TRADES ";
  this.account.getTrades(trades);

  string refresh = StringFormat("REFRESH %s\n%s\n%s\n%s", historyOrders, historyDeals, orders, trades);

// Public instead of requestReply
  return this.reply(clientPubSocket, refresh);
}
//+------------------------------------------------------------------+
