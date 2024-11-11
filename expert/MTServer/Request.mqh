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
  if (!this.markets.hasBarSubscribers())
    return true;

  string result = "BARS ";
  this.markets.getLastBars(result);
  return this.reply(clientPubSocket, result);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::publicSubscriptionQuotes() {
  if (!this.markets.hasQuoteSubscribers())
    return true;

  string result = "QUOTES ";
  this.markets.getLastQuotes(result);
  return this.reply(clientPubSocket, result);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::publicSubscriptionTicks() {
  if (!this.markets.hasTickSubscribers())
    return true;

  string result = "TICKS ";
  this.markets.getLastTicks(result);
  return this.reply(clientPubSocket, result);
}

//+------------------------------------------------------------------+
//|  PING                                                            |
//+------------------------------------------------------------------+
bool MTServer::processRequestPing(string &params[], string &response) {
  response += "PONG";
  return true;
}

//+------------------------------------------------------------------+
//| MARKET BARS                                                      |
//+------------------------------------------------------------------+
bool MTServer::processRequestBars(string &params[], string &response) {
  string symbol = params[1];
  ENUM_TIMEFRAMES period = GetTimeframe(params[2]);
  datetime startTime = TimestampToGMTTime(params[3]);
  datetime endTime = TimestampToGMTTime(params[4]);

  this.markets.getBars(response, symbol, period, startTime, endTime);
  return true;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::processRequestSubBars(string &params[], string &response) {
  string symbol = params[1];
  ENUM_TIMEFRAMES period = GetTimeframe(params[2]);
  this.markets.subscribeBar(symbol, period);

  response += "OK";
  return true;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::processRequestUnsubBars(string &params[], string &response) {
  string symbol = params[1];
  ENUM_TIMEFRAMES period = GetTimeframe(params[2]);
  this.markets.unsubscribeBar(symbol, period);

  response += "OK";
  return true;
}

//+------------------------------------------------------------------+
//| MARKET QUOTES                                                    |
//+------------------------------------------------------------------+
bool MTServer::processRequestQuotes(string &params[], string &response) {
  this.markets.getQuotes(response);
  return true;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::processRequestSubQuotes(string &params[], string &response) {
  int size = ArraySize(params);

  string symbol;
  for (int i = 2; i < size; i++) {
    symbol = params[i];
    this.markets.subscribeQuote(symbol);
  }

  response += "OK";
  return true;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::processRequestUnsubQuotes(string &params[], string &response) {
  int size = ArraySize(params);

  string symbol;
  for (int i = 2; i < size; i++) {
    symbol = params[i];
    this.markets.unsubscribeQuote(symbol);
  }

  response += "OK";
  return true;
}

//+------------------------------------------------------------------+
//| MARKET TICKS                                                     |
//+------------------------------------------------------------------+
bool MTServer::processRequestTicks(string &params[], string &response) {
  this.markets.getTicks(response);
  return true;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::processRequestSubTicks(string &params[], string &response) {
  string symbol = params[1];
  this.markets.subscribeTick(symbol);

  response += "OK";
  return true;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::processRequestUnsubTicks(string &params[], string &response) {
  string symbol = params[1];
  this.markets.unsubscribeTick(symbol);

  response += "OK";
  return true;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::processRequestUnsubAll(string &params[], string &response) {
  Print("Clear all subscribers");

  this.markets.clearBarSubscribers();
  this.markets.clearQuoteSubscribers();

// Unsubscribe and doesn't response anything
  return true;
}

//+------------------------------------------------------------------+
//| MARKET TIME                                                      |
//+------------------------------------------------------------------+
bool MTServer::processRequestTime(string &params[], string &response) {
  response += StringFormat("%f", TimeTradeServer());
  return true;
}

//+------------------------------------------------------------------+
//| MARKETS                                                          |
//+------------------------------------------------------------------+
bool MTServer::processRequestMarkets(string &params[], string &response) {
  this.markets.getMarkets(response);
  return true;
}

//+------------------------------------------------------------------+
//| ACCOUNT                                                          |
//+------------------------------------------------------------------+
bool MTServer::processRequestAccount(string &params[], string &response) {
  return this.account.getAccount(response);
}

//+------------------------------------------------------------------+
//| FUND                                                             |
//+------------------------------------------------------------------+
bool MTServer::processRequestFund(string &params[], string &response) {
  this.account.getFund(response);
  return true;
}

//+------------------------------------------------------------------+
//| ORDERS                                                           |
//+------------------------------------------------------------------+
bool MTServer::processRequestOrders(string &params[], string &response) {
  string symbol = params[1];

  this.account.getOrders(response, symbol);
  return true;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::processRequestOpenOrder(string &params[], string &response) {
  string symbol = params[1];
  int type = StringToOperationType(params[2]);
  double lots = StringToDouble(params[3]);
  double price = StringToDouble(params[4]);
  double sl = StringToDouble(params[5]);
  double tp = StringToDouble(params[6]);
  string comment = params[7];

  ulong ticket = this.account.openOrder(response, symbol, type, lots, price, sl, tp, comment);
  StringAdd(response, IntegerToString(ticket));
  return true;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::processRequestModifyOrder(string &params[], string &response) {
#ifdef __MQL4__
  ulong ticket = StrToInteger(params[1]);
#endif
#ifdef __MQL5__
  ulong ticket = StringToInteger(params[1]);
#endif

  double price = StringToDouble(params[2]);
  double sl = StringToDouble(params[3]);
  double tp = StringToDouble(params[4]);
  datetime expiration = TimestampToGMTTime(params[5]);

// process
  this.account.modifyOrder(response, ticket, price, sl, tp, expiration);
  return true;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::processRequestCancelOrder(string &params[], string &response) {
#ifdef __MQL4__
  ulong ticket = StrToInteger(params[1]);
#endif
#ifdef __MQL5__
  ulong ticket = StringToInteger(params[1]);
#endif

  this.account.cancelOrder(response, ticket);
  return true;
}

//+------------------------------------------------------------------+
//| TRADES                                                           |
//+------------------------------------------------------------------+
bool MTServer::processRequestTrades(string &params[], string &response) {
  string symbol = params[1];

  this.account.getTrades(response, symbol);
  return true;
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::processRequestModifyTrade(string &params[], string &response) {
#ifdef __MQL4__
  ulong ticket = StrToInteger(params[1]);
#endif
#ifdef __MQL5__
  ulong ticket = StringToInteger(params[1]);
#endif
  double sl = StringToDouble(params[2]);
  double tp = StringToDouble(params[3]);

// process
  this.account.modifyTrade(response, ticket, sl, tp);
  return true;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::processRequestCloseTrade(string &params[], string &response) {
#ifdef __MQL4__
  ulong ticket = StrToInteger(params[1]);
#endif
#ifdef __MQL5__
  ulong ticket = StringToInteger(params[1]);
#endif

  this.account.closeTrade(response, ticket);
  return true;
}
//+------------------------------------------------------------------+
//| DEALS                                                            |
//+------------------------------------------------------------------+
bool MTServer::processRequestDeals(string &params[], string &response) {
  string symbol = params[1];
  datetime fromDate = TimestampToGMTTime(params[2]);

  this.account.getHistoryDeals(response, symbol, fromDate);
  return true;
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
