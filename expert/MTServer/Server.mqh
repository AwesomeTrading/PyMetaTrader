//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+

#include <Zmq/Zmq.mqh>
#include  "Markets.mqh"
#include  "Account.mqh"
#include  "Helper.mqh"

#define PROJECT_NAME "MTSERVER"
#define ZEROMQ_PROTOCOL "tcp"
#define HOSTNAME "*"
#define PUSH_PORT 32768
#define PULL_PORT 32769
#define PUB_PORT 32770


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
class MTServer
  {
private:
   Context           *context;
   Socket            *pushSocket;
   Socket            *pullSocket;
   Socket            *pubSocket;
   MTMarkets         *markets;
   MTAccount         *account;
   datetime          pingExpire;

   bool              startSockets();
   bool              stopSockets();
   bool              status();
   bool              reply(Socket& socket, string message);

   // subscribers
   void              checkSubscribers();
   void              clearSubscribers();
   bool              processSubBars();
   bool              processSubQuotes();


   // request
   void              checkRequest();
   void              parseRequest(string& message, string& retArray[]);
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
   bool              processRequestFund(string &params[]);

   bool              processRequestOrders(string &params[]);
   bool              processRequestOpenOrder(string &params[]);
   bool              processRequestModifyOrder(string &params[]);
   bool              processRequestCancelOrder(string &params[]);
   void              throwOrderEvent(ENUM_EVENTS event, ulong ticket);

   bool              processRequestTrades(string &params[]);
   bool              processRequestModifyTrade(string &params[]);
   bool              processRequestCloseTrade(string &params[]);
   void              throwTradeEvent(ENUM_EVENTS event, ulong ticket, string trade);

   bool              processRequestDeals(string &params[]);
public:
                     MTServer(ulong magic, int deviation);
   bool              start();
   bool              stop();
   void              onTick();
   void              onTimer();
   void              onTrade();
  };

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::MTServer(ulong magic, int deviation)
  {
   this.context = new Context(PROJECT_NAME);
   this.pushSocket = new Socket(this.context, ZMQ_PUSH);
   this.pullSocket = new Socket(this.context, ZMQ_PULL);
   this.pubSocket = new Socket(this.context, ZMQ_PUB);

   this.markets = new MTMarkets();
   this.account = new MTAccount(magic, deviation);

   this.pingExpire = TimeCurrent() + 30; // expire at next 30 seconds
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::start(void)
  {
   Print("Start Server");

   this.context.setBlocky(false);

   this.startSockets();
   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::stop(void)
  {
   Print("Stop Server");
   this.stopSockets();

   /*delete context;
   delete pushSocket;
   delete pullSocket;
   delete pubSocket;*/
   return true;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::onTick(void)
  {
#ifdef __MQL4__
   RefreshRates();
#endif
   if(TimeCurrent() > this.pingExpire)
     {
      this.pingExpire = TimeCurrent() + 5 * 60; // expire at next 5 minutes
      this.clearSubscribers();
      return;
     }

   this.checkSubscribers();
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::onTimer(void)
  {
   this.checkRequest();
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::onTrade(void)
  {
// History
   string historyOrders = StringFormat("ORDERS %s|", EventToString(EVENT_COMPLETED));
   string historyDeals = StringFormat("DEALS %s|", EventToString(EVENT_COMPLETED));
   this.account.checkHistory(historyOrders, historyDeals);
   this.reply(pubSocket, historyOrders);
   this.reply(pubSocket, historyDeals);

// Open orders
   string orders = StringFormat("ORDERS %s|", EventToString(EVENT_MODIFIED));
   this.account.getOrders(orders);
   this.reply(pubSocket, orders);

// Trades
   string trades = StringFormat("TRADES %s|", EventToString(EVENT_MODIFIED));
   this.account.getTrades(trades);
   this.reply(pubSocket, trades);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::startSockets(void)
  {
   Print("Start socket");

// Send responses to PULL_PORT that client is listening on.
   if(!pushSocket.bind(StringFormat("%s://%s:%d", ZEROMQ_PROTOCOL, HOSTNAME, PULL_PORT)))
     {
      PrintFormat("[PUSH] ####ERROR#### Binding MTServer to Socket on Port %d",PULL_PORT);
      return false;
     }
   else
     {
      PrintFormat("[PUSH] Binding MTServer to Socket on Port %d",PULL_PORT);
      pushSocket.setSendHighWaterMark(1);
      pushSocket.setLinger(0);
     }

// Receive commands from PUSH_PORT that client is sending to.
   if(!pullSocket.bind(StringFormat("%s://%s:%d", ZEROMQ_PROTOCOL, HOSTNAME, PUSH_PORT)))
     {
      PrintFormat("[PULL] ####ERROR#### Binding MT4 Server to Socket on Port %d",PUSH_PORT);
      return false;
     }
   else
     {
      PrintFormat("[PULL] Binding MT4 Server to Socket on Port %d",PUSH_PORT);
      pullSocket.setReceiveHighWaterMark(1);
      pullSocket.setLinger(0);
     }

// Send new market data to PUB_PORT that client is subscribed to.
   if(!pubSocket.bind(StringFormat("%s://%s:%d", ZEROMQ_PROTOCOL, HOSTNAME, PUB_PORT)))
     {
      PrintFormat("[PUB] ####ERROR#### Binding MT4 Server to Socket on Port %s",PUB_PORT);
      return false;
     }
   else
     {
      PrintFormat("[PUB] Binding MT4 Server to Socket on Port %d",PUB_PORT);
      pubSocket.setSendHighWaterMark(1);
      pubSocket.setLinger(0);
     }

   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::stopSockets(void)
  {
   Print("[PUSH] Unbinding MT4 Server from Socket on Port " + IntegerToString(PULL_PORT) + "..");
   pushSocket.unbind(StringFormat("%s://%s:%d", ZEROMQ_PROTOCOL, HOSTNAME, PULL_PORT));
   pushSocket.disconnect(StringFormat("%s://%s:%d", ZEROMQ_PROTOCOL, HOSTNAME, PULL_PORT));

   Print("[PULL] Unbinding MT4 Server from Socket on Port " + IntegerToString(PUSH_PORT) + "..");
   pullSocket.unbind(StringFormat("%s://%s:%d", ZEROMQ_PROTOCOL, HOSTNAME, PUSH_PORT));
   pullSocket.disconnect(StringFormat("%s://%s:%d", ZEROMQ_PROTOCOL, HOSTNAME, PUSH_PORT));

   Print("[PUB] Unbinding MT4 Server from Socket on Port " + IntegerToString(PUB_PORT) + "..");
   pubSocket.unbind(StringFormat("%s://%s:%d", ZEROMQ_PROTOCOL, HOSTNAME, PUB_PORT));
   pubSocket.disconnect(StringFormat("%s://%s:%d", ZEROMQ_PROTOCOL, HOSTNAME, PUB_PORT));

// Shutdown ZeroMQ Context
   context.shutdown();
   context.destroy(0);
   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::status(void)
  {
   if(IsStopped())
      return false;

   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::reply(Socket& socket, string message)
  {
   Print("Reply: " + message);
   ZmqMsg msg(message);
   bool ok = socket.send(msg, true); // NON-BLOCKING
   if(!ok)
      Print("[ERROR] Cannot send data to socket");
   return ok;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::checkSubscribers()
  {
   this.processSubBars();
   this.processSubQuotes();
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::clearSubscribers()
  {
   Print("Clear all subscribers");
   this.markets.clearBarSubscribers();
   this.markets.clearQuoteSubscribers();
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::processSubBars()
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
bool MTServer::processSubQuotes()
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
void MTServer::checkRequest()
  {
   if(!this.status())
      return;

   ZmqMsg request;

// Get client's response, but don't block.
   pullSocket.recv(request, true);

   if(request.size() == 0)
      return;

// Message components for later.
   string params[10];
   uchar data[];

// Get data from request
   ArrayResize(data, (int)request.size());
   request.getData(data);
   string dataStr = CharArrayToString(data);

// Process data
   this.parseRequest(dataStr, params);

// Interpret data
   this.processRequest(params);

   int errorCode = GetLastError();
   if(errorCode != 0)
      PrintFormat("ERROR request[%s]: (%d) %s", dataStr, errorCode, ErrorDescription(errorCode));
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::parseRequest(string& message, string& result[])
  {
   Print("Request: " + message);
   ushort separator = StringGetCharacter(";", 0);
   int splits = StringSplit(message, separator, result);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::requestReply(string &id, string &message)
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
bool MTServer::processRequest(string &params[])
  {
   string action = params[0];

// ping
   if(action == "PING")
      return this.processRequestPing(params);

// markets
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
   if(action == "MARKETS")
      return this.processRequestMarkets(params);
   if(action == "TIME")
      return this.processRequestTime(params);

// account
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
      return  this.processRequestTrades(params);
   if(action == "MODIFY_TRADE")
      return this.processRequestModifyTrade(params);
   if(action == "CLOSE_TRADE")
      return this.processRequestCloseTrade(params);

   if(action == "DEALS")
      return this.processRequestDeals(params);

   return false;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::processRequestPing(string &params[])
  {
   this.pingExpire = TimeCurrent() + 30; // expire at next 30 seconds
   string result = "PONG";
   return this.requestReply(params[1], result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::processRequestBars(string &params[])
  {
   string symbol = params[2];
   ENUM_TIMEFRAMES period = GetTimeframe(params[3]);
   datetime startTime = TimestampToTime(params[4]);
   datetime endTime = TimestampToTime(params[5]);

   string result = "";
   this.markets.getBars(symbol, period, startTime, endTime, result);
   return this.requestReply(params[1], result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::processRequestSubBars(string &params[])
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
bool MTServer::processRequestUnsubBars(string &params[])
  {
   string symbol = params[2];
   ENUM_TIMEFRAMES period = GetTimeframe(params[3]);
   this.markets.unsubscribeBar(symbol, period);

   string result = "OK";
   return this.requestReply(params[1], result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::processRequestQuotes(string &params[])
  {
   string result = "";
   this.markets.getQuotes(result);
   return this.requestReply(params[1], result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::processRequestSubQuotes(string &params[])
  {
   string symbol = params[2];
   this.markets.subscribeQuote(symbol);

   string result = "OK";
   return this.requestReply(params[1], result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::processRequestUnsubQuotes(string &params[])
  {
   string symbol = params[2];
   this.markets.unsubscribeQuote(symbol);

   string result = "OK";
   return this.requestReply(params[1], result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::processRequestTime(string &params[])
  {
   string result = StringFormat("%f", TimeCurrent());
   return this.requestReply(params[1], result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::processRequestMarkets(string &params[])
  {
   string result = "";
   this.markets.getMarkets(result);
   return this.requestReply(params[1], result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::processRequestFund(string &params[])
  {
   string result = "";
   this.account.getFund(result);
   return this.requestReply(params[1], result);
  }

//+------------------------------------------------------------------+
//| ORDERS                                                           |
//+------------------------------------------------------------------+
bool MTServer::processRequestOrders(string &params[])
  {
   string symbol = params[2];
   string result = "";
   this.account.getOrders(result, symbol);
   return this.requestReply(params[1], result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::processRequestOpenOrder(string &params[])
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
   this.requestReply(params[1], result);

// Throw event
   if(ticket > 0)
      // Market order return trade ticket
      if(type == ORDER_TYPE_BUY || type == ORDER_TYPE_SELL)
         this.throwTradeEvent(EVENT_OPENED, ticket);
      else
         this.throwOrderEvent(EVENT_OPENED, ticket);

   return ticket > 0;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::processRequestModifyOrder(string &params[])
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
   bool ok = this.account.modifyOrder(ticket, price, sl, tp, expiration, result);
   this.requestReply(params[1], result);

// event MODIFY ORDER
   if(ok)
      this.throwOrderEvent(EVENT_MODIFIED, ticket);
   return ok;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::processRequestCancelOrder(string &params[])
  {
#ifdef __MQL4__
   ulong ticket = StrToInteger(params[2]);
#endif
#ifdef __MQL5__
   ulong ticket = StringToInteger(params[2]);
#endif

   string result = "";
   bool ok = this.account.cancelOrder(ticket, result);
   this.requestReply(params[1], result);

// event CANCEL ORDER
   if(ok)
      this.throwOrderEvent(EVENT_CANCELED, ticket);
   return ok;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::throwOrderEvent(ENUM_EVENTS event, ulong ticket)
  {
   string order = "";
   switch(event)
     {
      case EVENT_CANCELED:
      case EVENT_COMPLETED:
         this.account.getHistoryOrder(ticket, order);
         break;
      default:
         this.account.getOrder(ticket, order);
         break;
     }

   string result = StringFormat("ORDERS %s|%s", EventToString(event), order);
   this.reply(pubSocket, result);
  }

//+------------------------------------------------------------------+
//| TRADES                                                           |
//+------------------------------------------------------------------+
bool MTServer::processRequestTrades(string &params[])
  {
   string symbol = params[2];
   string result = "";
   this.account.getTrades(result, symbol);
   return this.requestReply(params[1], result);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::processRequestModifyTrade(string &params[])
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
   bool ok = this.account.modifyTrade(ticket, sl, tp, result);
   this.requestReply(params[1], result);

// event MODIFY ORDER
   if(ok)
      this.throwTradeEvent(EVENT_MODIFIED, ticket);
   return ok;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::processRequestCloseTrade(string &params[])
  {
#ifdef __MQL4__
   ulong ticket = StrToInteger(params[2]);
#endif
#ifdef __MQL5__
   ulong ticket = StringToInteger(params[2]);
#endif
   string trade = "";
   this.account.getTrade(ticket, trade);

   string result = "";
   bool ok = this.account.closeTrade(ticket, result);
   this.requestReply(params[1], result);

// event COMPLETED TRADE
   if(ok)
      this.throwTradeEvent(EVENT_COMPLETED, ticket, trade);
   return ok;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::throwTradeEvent(ENUM_EVENTS event, ulong ticket, string trade = "")
  {
   switch(event)
     {
      case EVENT_COMPLETED:
         break;
      default:
         this.account.getTrade(ticket, trade);
         break;
     }

   string result = StringFormat("TRADES %s|%s", EventToString(event), trade);
   this.reply(pubSocket, result);
  }
//+------------------------------------------------------------------+
//| DEALS                                                            |
//+------------------------------------------------------------------+
bool MTServer::processRequestDeals(string &params[])
  {
   string symbol = params[2];
   datetime fromDate = TimestampToGMTTime(params[3]);

   string result = "";
   this.account.getHistoryDeals(result, symbol, fromDate);
   return this.requestReply(params[1], result);
  }
//+------------------------------------------------------------------+
