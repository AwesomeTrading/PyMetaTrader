//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+

#include <Zmq/Zmq.mqh>
#include "Markets.mqh"
#include "Account.mqh"
#include "Helper.mqh"

#define PROJECT_NAME "MTSERVER_WORKER"
#define WORKER_PULL_URL "tcp://127.0.0.1:32001"
#define WORKER_PUSH_URL "tcp://127.0.0.1:32002"
#define WORKER_PUB_URL "tcp://127.0.0.1:32003"
#define WORKER_SUB_URL "tcp://127.0.0.1:32004"

enum ENUM_EVENTS
  {
   EVENT_OPENED,
   EVENT_MODIFIED,
   EVENT_COMPLETED,
   EVENT_CANCELED,
   EVENT_EXPIRED,
  };

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string EventToString(ENUM_EVENTS event)
  {
   switch(event)
     {
      case EVENT_OPENED:
         return "OPENED";
      case EVENT_MODIFIED:
         return "MODIFIED";
      case EVENT_COMPLETED:
         return "COMPLETED";
      case EVENT_CANCELED:
         return "CANCELED";
      case EVENT_EXPIRED:
         return "EXPIRED";
      default:
         return "UNKNOWN";
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class MTWorker
  {
private:
   Context           *context;
   Socket            *pushSocket;
   Socket            *pullSocket;
   Socket            *pubSocket;
   Socket            *subSocket;
   MTMarkets         *markets;
   MTAccount         *account;
   datetime          flushSubscriptionsAt;
   ushort            separator;

   bool              startSockets();
   bool              stopSockets();
   bool              reply(Socket &socket, string message);

   // subscribers
   void              checkMarketSubscriptions();
   void              flushMarketSubscriptions();
   void              clearMarketSubscriptions();
   bool              publicSubscriptionBars();
   bool              publicSubscriptionQuotes();
   bool              processRequestUnsubAll(string &params[]);

   // request
   void              checkRequest(Socket &socket, bool prefix);
   void              parseRequest(string &message, string &retArray[]);
   bool              requestReply(string &id, string &message);
   bool              processRequest(string &compArray[]);
   bool              processRequestPing(string &params[]);

   // market
   bool              processRequestBars(string &params[]);
   bool              processRequestSubBars(string &params[]);
   bool              processRequestUnsubBars(string &params[]);

   bool              processRequestQuotes(string &params[]);
   bool              processRequestSubQuotes(string &params[]);
   bool              processRequestUnsubQuotes(string &params[]);

   bool              processRequestTime(string &params[]);
   bool              processRequestMarkets(string &params[]);

   // account
   bool              processRequestAccount(string &params[]);
   bool              processRequestFund(string &params[]);

   bool              processRequestOrders(string &params[]);
   bool              processRequestOpenOrder(string &params[]);
   bool              processRequestModifyOrder(string &params[]);
   bool              processRequestCancelOrder(string &params[]);

   bool              processRequestTrades(string &params[]);
   bool              processRequestModifyTrade(string &params[]);
   bool              processRequestCloseTrade(string &params[]);

   bool              processRequestDeals(string &params[]);

   bool              publicRequestRefreshTrades(string &params[]);
public:
                     MTWorker(ulong magic, int deviation);
   bool              start();
   bool              stop();
   void              onTimer();
  };

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTWorker::MTWorker(ulong magic, int deviation)
  {
   this.context = new Context(StringFormat("%s-%d", PROJECT_NAME, magic));
   this.pushSocket = new Socket(this.context, ZMQ_PUSH);
   this.pullSocket = new Socket(this.context, ZMQ_PULL);
   this.pubSocket = new Socket(this.context, ZMQ_PUSH);
   this.subSocket = new Socket(this.context, ZMQ_SUB);
   this.subSocket.setSubscribe("ALL");

   this.markets = new MTMarkets();
   this.account = new MTAccount(magic, deviation);

   this.flushSubscriptionsAt = 0;
   this.separator  = StringGetCharacter(";", 0);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTWorker::start(void)
  {
   Print("Start worker");
   this.context.setBlocky(false);
   this.startSockets();
   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTWorker::stop(void)
  {
   Print("Stop worker");
   this.stopSockets();
   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTWorker::onTimer(void)
  {
   this.checkRequest(pullSocket);
   this.checkRequest(subSocket, true);
   this.checkMarketSubscriptions();
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTWorker::startSockets(void)
  {
// Connect to sends message to server
   if(!pushSocket.connect(WORKER_PUSH_URL))
     {
      PrintFormat("[PUSH] ERROR when connect worker to %s", WORKER_PUSH_URL);
      return false;
     }
   else
     {
      PrintFormat("[PUSH] Connected worker to %s", WORKER_PUSH_URL);
     }

// Connect to recieves message from server
   if(!pullSocket.connect(WORKER_PULL_URL))
     {
      PrintFormat("[PULL] ERROR when connect Worker to %s", WORKER_PULL_URL);
      return false;
     }
   else
     {
      PrintFormat("[PULL] Connected Worker to %s", WORKER_PULL_URL);
     }

// Connect to public message to server
   if(!pubSocket.connect(WORKER_PUB_URL))
     {
      PrintFormat("[PUB] ERROR when connect Worker to %s", WORKER_PUB_URL);
      return false;
     }
   else
     {
      PrintFormat("[PUB] Connected Worker to %s", WORKER_PUB_URL);
     }

// Connect to subscribe message from server
   if(!subSocket.connect(WORKER_SUB_URL))
     {
      PrintFormat("[SUB] ERROR when connect Worker to %s", WORKER_SUB_URL);
      return false;
     }
   else
     {
      PrintFormat("[SUB] Connected Worker to %s", WORKER_SUB_URL);
     }
   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTWorker::stopSockets(void)
  {
   PrintFormat("[PUSH] Disconnect worker from %s...", WORKER_PUSH_URL);
   this.pushSocket.disconnect(WORKER_PUSH_URL);

   PrintFormat("[PULL] Disconnect worker from %s...", WORKER_PULL_URL);
   this.pullSocket.disconnect(WORKER_PULL_URL);

   PrintFormat("[PUB] Disconnect worker from %s...", WORKER_PUB_URL);
   this.pubSocket.disconnect(WORKER_PUB_URL);

   PrintFormat("[PUB] Disconnect worker from %s...", WORKER_SUB_URL);
   this.subSocket.disconnect(WORKER_SUB_URL);

// Shutdown ZeroMQ Context
   this.context.shutdown();
   this.context.destroy(0);
   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTWorker::reply(Socket &socket, string message)
  {
   Print("<- Reply: " + message);
   ZmqMsg msg(message);
   bool ok = socket.send(msg, true); // NON-BLOCKING
   if(!ok)
      Print("[ERROR] Cannot send data to socket");
   return ok;
  }

//+------------------------------------------------------------------+
//| SUBSCRIBERS                                                      |
//+------------------------------------------------------------------+
void MTWorker::checkMarketSubscriptions()
  {
   if(this.flushSubscriptionsAt > TimeCurrent())
      return;

   this.flushMarketSubscriptions();
   this.flushSubscriptionsAt = TimeCurrent() + 2; // flush every 2 seconds
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTWorker::flushMarketSubscriptions()
  {
   this.publicSubscriptionBars();
   this.publicSubscriptionQuotes();
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTWorker::publicSubscriptionBars()
  {
   if(!this.markets.hasBarSubscribers())
      return true;

   string result = "BARS ";
   this.markets.getLastBars(result);
   return this.reply(pubSocket, result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTWorker::publicSubscriptionQuotes()
  {
   if(!this.markets.hasQuoteSubscribers())
      return true;

   string result = "QUOTES ";
   this.markets.getLastQuotes(result);
   return this.reply(pubSocket, result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTWorker::checkRequest(Socket &socket, bool prefix=false)
  {
   if(IsStopped())
      return;

   ZmqMsg request;

// Get client's response, but don't block.
   socket.recv(request, true);

   if(request.size() == 0)
      return;

// Message components for later.
   string params[10];
   string message = request.getData();
   if(prefix)
     {
      int idx = StringFind(message, " ");
      message = StringSubstr(message, idx + 1);
     }

// Process data
   Print("-> Request: " + message);
   StringSplit(message, separator, params);

// Interpret data
   this.processRequest(params);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTWorker::parseRequest(string &message, string &result[])
  {
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTWorker::requestReply(string &id, string &message)
  {
   int errorCode = GetLastError();
   string msg;
   if(errorCode == 0)
     {
      msg = StringFormat("OK|%s|", id);
      StringAdd(msg, message);
     }
   else
     {
      msg = StringFormat("KO|%s|%s", id, GetErrorDescription(errorCode));
     }

   ResetLastError();
   return this.reply(pushSocket, msg);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTWorker::processRequest(string &params[])
  {
   string action = params[0];

// ping
   if(action == "PING")
      return this.processRequestPing(params);

// markets
   if(action == "MARKETS")
      return this.processRequestMarkets(params);
   if(action == "TIME")
      return this.processRequestTime(params);
   if(action == "BARS")
      return this.processRequestBars(params);
   if(action == "SUB_BARS")
      return this.processRequestSubBars(params);
   if(action == "UNSUB_BARS")
      return this.processRequestUnsubBars(params);
   if(action == "QUOTES")
      return this.processRequestQuotes(params);
   if(action == "SUB_QUOTES")
      return this.processRequestSubQuotes(params);
   if(action == "UNSUB_QUOTES")
      return this.processRequestUnsubQuotes(params);
   if(action == "UNSUB_ALL")
      return this.processRequestUnsubAll(params);

// account
   if(action == "ACCOUNT")
      return this.processRequestAccount(params);
   if(action == "FUND")
      return this.processRequestFund(params);

   if(action == "ORDERS")
      return this.processRequestOrders(params);
   if(action == "OPEN_ORDER")
      return this.processRequestOpenOrder(params);
   if(action == "MODIFY_ORDER")
      return this.processRequestModifyOrder(params);
   if(action == "CANCEL_ORDER")
      return this.processRequestCancelOrder(params);

   if(action == "TRADES")
      return this.processRequestTrades(params);
   if(action == "MODIFY_TRADE")
      return this.processRequestModifyTrade(params);
   if(action == "CLOSE_TRADE")
      return this.processRequestCloseTrade(params);

   if(action == "DEALS")
      return this.processRequestDeals(params);

   if(action == "REFRESH_TRADES")
      return this.publicRequestRefreshTrades(params);

   return false;
  }

//+------------------------------------------------------------------+
//|  PING                                                            |
//+------------------------------------------------------------------+
bool MTWorker::processRequestPing(string &params[])
  {
   string result = "PONG";
   return this.requestReply(params[1], result);
  }

//+------------------------------------------------------------------+
//| MARKET BARS                                                      |
//+------------------------------------------------------------------+
bool MTWorker::processRequestBars(string &params[])
  {
   string symbol = params[2];
   ENUM_TIMEFRAMES period = GetTimeframe(params[3]);
   datetime startTime = TimestampToGMTTime(params[4]);
   datetime endTime = TimestampToGMTTime(params[5]);

   string result = "";
   this.markets.getBars(symbol, period, startTime, endTime, result);
   return this.requestReply(params[1], result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTWorker::processRequestSubBars(string &params[])
  {
   string symbol = params[2];
   ENUM_TIMEFRAMES period = GetTimeframe(params[3]);
   this.markets.subscribeBar(symbol, period);
   string result = "OK";
   return this.requestReply(params[1], result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTWorker::processRequestUnsubBars(string &params[])
  {
   string symbol = params[2];
   ENUM_TIMEFRAMES period = GetTimeframe(params[3]);
   this.markets.unsubscribeBar(symbol, period);

   string result = "OK";
   return this.requestReply(params[1], result);
  }

//+------------------------------------------------------------------+
//| MARKET QUOTES                                                    |
//+------------------------------------------------------------------+
bool MTWorker::processRequestQuotes(string &params[])
  {
   string result = "";
   this.markets.getQuotes(result);
   return this.requestReply(params[1], result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTWorker::processRequestSubQuotes(string &params[])
  {
   string symbol = params[2];
   this.markets.subscribeQuote(symbol);

   string result = "OK";
   return this.requestReply(params[1], result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTWorker::processRequestUnsubQuotes(string &params[])
  {
   string symbol = params[2];
   this.markets.unsubscribeQuote(symbol);

   string result = "OK";
   return this.requestReply(params[1], result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTWorker::processRequestUnsubAll(string &params[])
  {
   Print("Clear all subscribers");

   this.markets.clearBarSubscribers();
   this.markets.clearQuoteSubscribers();

// Unsubscribe and doesn't response anything
   return true;
  }

//+------------------------------------------------------------------+
//| MARKET TIME                                                      |
//+------------------------------------------------------------------+
bool MTWorker::processRequestTime(string &params[])
  {
   string result = StringFormat("%f", TimeCurrent());
   return this.requestReply(params[1], result);
  }

//+------------------------------------------------------------------+
//| MARKETS                                                          |
//+------------------------------------------------------------------+
bool MTWorker::processRequestMarkets(string &params[])
  {
   string result = "";
   this.markets.getMarkets(result);
   return this.requestReply(params[1], result);
  }

//+------------------------------------------------------------------+
//| ACCOUNT                                                          |
//+------------------------------------------------------------------+
bool MTWorker::processRequestAccount(string &params[])
  {
   string result = "";
   this.account.getAccount(result);
   return this.requestReply(params[1], result);
  }

//+------------------------------------------------------------------+
//| FUND                                                             |
//+------------------------------------------------------------------+
bool MTWorker::processRequestFund(string &params[])
  {
   string result = "";
   this.account.getFund(result);
   return this.requestReply(params[1], result);
  }

//+------------------------------------------------------------------+
//| ORDERS                                                           |
//+------------------------------------------------------------------+
bool MTWorker::processRequestOrders(string &params[])
  {
   string symbol = params[2];
   string result = "";
   this.account.getOrders(result, symbol);
   return this.requestReply(params[1], result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTWorker::processRequestOpenOrder(string &params[])
  {
   string symbol = params[2];
   int type = StringToOperationType(params[3]);
   double lots = StringToDouble(params[4]);
   double price = StringToDouble(params[5]);
   double sl = StringToDouble(params[6]);
   double tp = StringToDouble(params[7]);
   string comment = params[8];

   string result = "";
   ulong ticket = this.account.openOrder(symbol, type, lots, price, sl, tp, comment, result);

   StringAdd(result, IntegerToString(ticket));
   return this.requestReply(params[1], result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTWorker::processRequestModifyOrder(string &params[])
  {
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
   this.account.modifyOrder(ticket, price, sl, tp, expiration, result);
   return this.requestReply(params[1], result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTWorker::processRequestCancelOrder(string &params[])
  {
#ifdef __MQL4__
   ulong ticket = StrToInteger(params[2]);
#endif
#ifdef __MQL5__
   ulong ticket = StringToInteger(params[2]);
#endif

   string result = "";
   this.account.cancelOrder(ticket, result);
   return this.requestReply(params[1], result);
  }

//+------------------------------------------------------------------+
//| TRADES                                                           |
//+------------------------------------------------------------------+
bool MTWorker::processRequestTrades(string &params[])
  {
   string symbol = params[2];
   string result = "";
   this.account.getTrades(result, symbol);
   return this.requestReply(params[1], result);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTWorker::processRequestModifyTrade(string &params[])
  {
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
   this.account.modifyTrade(ticket, sl, tp, result);
   return this.requestReply(params[1], result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTWorker::processRequestCloseTrade(string &params[])
  {
#ifdef __MQL4__
   ulong ticket = StrToInteger(params[2]);
#endif
#ifdef __MQL5__
   ulong ticket = StringToInteger(params[2]);
#endif
   string result = "";
   this.account.closeTrade(ticket, result);
   return this.requestReply(params[1], result);
  }
//+------------------------------------------------------------------+
//| DEALS                                                            |
//+------------------------------------------------------------------+
bool MTWorker::processRequestDeals(string &params[])
  {
   string symbol = params[2];
   datetime fromDate = TimestampToGMTTime(params[3]);

   string result = "";
   this.account.getHistoryDeals(result, symbol, fromDate);
   return this.requestReply(params[1], result);
  }

//+------------------------------------------------------------------+
//| REFRESH TRADES                                                   |
//+------------------------------------------------------------------+
bool MTWorker::publicRequestRefreshTrades(string &params[])
  {
   datetime fromDate = TimestampToGMTTime(params[2]);
   datetime toDate = TimestampToGMTTime(params[3]);

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
   return this.reply(pubSocket, refresh);
  }
//+------------------------------------------------------------------+
