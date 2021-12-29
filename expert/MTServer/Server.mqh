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
   void              reply(Socket& socket, string message);

   // subscribers
   void              checkSubscribers();
   void              clearSubscribers();
   void              processSubBars();
   void              processSubQuotes();


   // request
   void              checkRequest();
   void              parseRequest(string& message, string& retArray[]);
   void              requestReply(string &id, string &message);
   void              processRequest(string &compArray[]);
   void              processRequestPing(string &params[]);

   // market
   void              processRequestBars(string &params[]);
   void              processRequestSubBars(string &params[]);
   void              processRequestUnsubBars(string &params[]);

   void              processRequestQuotes(string &params[]);
   void              processRequestSubQuotes(string &params[]);
   void              processRequestUnsubQuotes(string &params[]);

   void              processRequestTime(string &params[]);
   void              processRequestMarkets(string &params[]);

   // account
   void              processRequestFund(string &params[]);

   void              processRequestOrders(string &params[]);
   void              processRequestOpenOrder(string &params[]);
   void              processRequestModifyOrder(string &params[]);
   void              processRequestCancelOrder(string &params[]);
   void              throwOrderEvent(ENUM_EVENTS event, ulong ticket);

   void              processRequestTrades(string &params[]);
   void              processRequestCloseTrade(string &params[]);
   void              throwTradeEvent(ENUM_EVENTS event, ulong ticket);

public:
                     MTServer(ulong magic, int deviation);
   bool              start();
   bool              stop();
   void              onTick();
   void              onTimer();
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
void MTServer::reply(Socket& socket, string message)
  {
   Print("Reply: " + message);
   ZmqMsg msg(message);
   if(!socket.send(msg, true)) // NON-BLOCKING
     {
      Print("[ERROR] Cannot send data to socket");
     }
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
void MTServer::processSubBars()
  {
   if(!this.markets.hasBarSubscribers())
      return;

   string result = "BARS ";
   this.markets.getLastBars(result);
   this.reply(pubSocket, result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::processSubQuotes()
  {
   if(!this.markets.hasQuoteSubscribers())
      return;

   string result = "QUOTES ";
   this.markets.getLastQuotes(result);
   this.reply(pubSocket, result);
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
void MTServer::requestReply(string &id, string &message)
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
   this.reply(pushSocket, msg);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::processRequest(string &params[])
  {
   string action = params[0];

// ping
   if(action == "PING")
     {
      this.processRequestPing(params);
      return;
     }

// markets
   if(action == "BARS")
     {
      this.processRequestBars(params);
      return;
     }
   if(action == "SUB_BARS")
     {
      this.processRequestSubBars(params);
      return;
     }
   if(action == "UNSUB_BARS")
     {
      this.processRequestUnsubBars(params);
      return;
     }
   if(action == "QUOTES")
     {
      this.processRequestQuotes(params);
      return;
     }
   if(action == "SUB_QUOTES")
     {
      this.processRequestSubQuotes(params);
      return;
     }
   if(action == "UNSUB_QUOTES")
     {
      this.processRequestUnsubQuotes(params);
      return;
     }
   if(action == "MARKETS")
     {
      this.processRequestMarkets(params);
      return;
     }
   if(action == "TIME")
     {
      this.processRequestTime(params);
      return;
     }

// account
   if(action == "FUND")
     {
      this.processRequestFund(params);
      return;
     }
   if(action == "TRADES")
     {
      this.processRequestTrades(params);
      return;
     }

   if(action == "CLOSE_TRADE")
     {
      this.processRequestCloseTrade(params);
      return;
     }
   if(action == "ORDERS")
     {
      this.processRequestOrders(params);
      return;
     }
   if(action == "OPEN_ORDER")
     {
      this.processRequestOpenOrder(params);
      return;
     }
   if(action == "MODIFY_ORDER")
     {
      this.processRequestModifyOrder(params);
      return;
     }
   if(action == "CANCEL_ORDER")
     {
      this.processRequestCancelOrder(params);
      return;
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::processRequestPing(string &params[])
  {
   this.pingExpire = TimeCurrent() + 30; // expire at next 30 seconds
   string result = "PONG";
   this.requestReply(params[1], result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::processRequestBars(string &params[])
  {
   string symbol = params[2];
   ENUM_TIMEFRAMES period = GetTimeframe(params[3]);
   datetime startTime = TimestampToTime(params[4]);
   datetime endTime = TimestampToTime(params[5]);

   string result = "";
   this.markets.getBars(symbol, period, startTime, endTime, result);
   this.requestReply(params[1], result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::processRequestSubBars(string &params[])
  {
   string symbol = params[2];
   ENUM_TIMEFRAMES period = GetTimeframe(params[3]);
   this.markets.subscribeBar(symbol, period);
   string result = "OK";
   this.requestReply(params[1], result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::processRequestUnsubBars(string &params[])
  {
   string symbol = params[2];
   ENUM_TIMEFRAMES period = GetTimeframe(params[3]);
   this.markets.unsubscribeBar(symbol, period);

   string result = "OK";
   this.requestReply(params[1], result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::processRequestQuotes(string &params[])
  {
   string result = "";
   this.markets.getQuotes(result);
   this.requestReply(params[1], result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::processRequestSubQuotes(string &params[])
  {
   string symbol = params[2];
   this.markets.subscribeQuote(symbol);

   string result = "OK";
   this.requestReply(params[1], result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::processRequestUnsubQuotes(string &params[])
  {
   string symbol = params[2];
   this.markets.unsubscribeQuote(symbol);

   string result = "OK";
   this.requestReply(params[1], result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::processRequestTime(string &params[])
  {
   string result = StringFormat("%f", TimeCurrent());
   this.requestReply(params[1], result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::processRequestMarkets(string &params[])
  {
   string result = "";
   this.markets.getMarkets(result);
   this.requestReply(params[1], result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::processRequestFund(string &params[])
  {
   string result = "";
   this.account.getFund(result);
   this.requestReply(params[1], result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::processRequestTrades(string &params[])
  {
   string symbol = params[2];
   string result = "";
   this.account.getTrades(symbol, result);
   this.requestReply(params[1], result);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::processRequestCloseTrade(string &params[])
  {
#ifdef __MQL4__
   ulong ticket = StrToInteger(params[2]);
#endif
#ifdef __MQL5__
   ulong ticket = StringToInteger(params[2]);
#endif

   string result = "";
   bool ok = this.account.closeTrade(ticket, result);
   this.requestReply(params[1], result);

// event COMPLETED TRADE
   this.throwTradeEvent(EVENT_COMPLETED, ticket);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::throwTradeEvent(ENUM_EVENTS event, ulong ticket)
  {
   string trade = "";
   switch(event)
     {
      case EVENT_CANCELED:
      case EVENT_COMPLETED:
         this.account.getHistoryOrder(ticket, trade);
         break;
      default:
         this.account.getTrade(ticket, trade);
         break;
     }
   trade = StringSubstr(trade, 0, StringLen(trade)-1);

   string result = StringFormat("TRADES %s|%s", EventToString(event), trade);
   this.reply(pubSocket, result);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::processRequestOrders(string &params[])
  {
   string symbol = params[2];
   int modes[] = {};

   string result = "";
   this.account.getOrders(symbol, modes, result);
   this.requestReply(params[1], result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::processRequestOpenOrder(string &params[])
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
// Market order return trade ticket
   if(type == ORDER_TYPE_BUY || type == ORDER_TYPE_SELL)
     {
      this.throwTradeEvent(EVENT_OPENED, ticket);
     }
   else
     {
      this.throwOrderEvent(EVENT_OPENED, ticket);
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::processRequestModifyOrder(string &params[])
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
   this.throwOrderEvent(EVENT_MODIFIED, ticket);
  }


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::processRequestCancelOrder(string &params[])
  {
#ifdef __MQL4__
   ulong ticket = StrToInteger(params[2]);
#endif
#ifdef __MQL5__
   ulong ticket = StringToInteger(params[2]);
#endif

   string result = "";
   this.account.cancelOrder(ticket, result);
   this.requestReply(params[1], result);

// event CANCEL ORDER
   this.throwOrderEvent(EVENT_CANCELED, ticket);
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
   order = StringSubstr(order, 0, StringLen(order)-1);

   string result = StringFormat("ORDERS %s|%s", EventToString(event), order);
   this.reply(pubSocket, result);
  }
//+------------------------------------------------------------------+
