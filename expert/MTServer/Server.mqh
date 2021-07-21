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
   void              replyOrderEvents(string events);

   // subscribers
   void              checkSubscribers();
   void              clearSubscribers();
   void              processSubBars();
   void              processSubQuotes();


   // request
   void              checkRequest();
   void              parseRequest(string& message, string& retArray[]);
   void              processRequest(string &compArray[]);
   void              processRequestPing(string &params[]);

   void              processRequestSubBars(string &params[]);
   void              processRequestUnsubBars(string &params[]);
   void              processRequestSubQuotes(string &params[]);
   void              processRequestUnsubQuotes(string &params[]);

   void              processRequestTime(string &params[]);
   void              processRequestHistory(string &params[]);
   void              processRequestMarkets(string &params[]);

   void              processRequestFund(string &params[]);
   void              processRequestOrders(string &params[]);
   void              processRequestTrades(string &params[]);
   void              processRequestOpenOrder(string &params[]);
   void              processRequestModifyOrder(string &params[]);
   void              processRequestCloseOrder(string &params[]);

public:
                     MTServer();
   bool              start();
   bool              stop();
   void              onTick();
   void              onTimer();
  };

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::MTServer(void)
  {
   this.context = new Context(PROJECT_NAME);
   this.pushSocket = new Socket(this.context, ZMQ_PUSH);
   this.pullSocket = new Socket(this.context, ZMQ_PULL);
   this.pubSocket = new Socket(this.context, ZMQ_PUB);

   this.markets = new MTMarkets();
   this.account = new MTAccount();

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
   RefreshRates();
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
void MTServer::replyOrderEvents(string events)
  {
   string result = StringFormat("ORDERS %s", events);
   this.reply(pubSocket, result);
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
   ArrayResize(data, request.size());
   request.getData(data);
   string dataStr = CharArrayToString(data);

// Process data
   this.parseRequest(dataStr, params);

// Interpret data
   this.processRequest(params);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::parseRequest(string& message, string& result[])
  {
   Print("Parsing: " + message);
   ushort u_sep = StringGetCharacter(";", 0);
   int splits = StringSplit(message, u_sep, result);
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
   if(action == "HISTORY")
     {
      this.processRequestHistory(params);
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
   if(action == "CLOSE_ORDER")
     {
      this.processRequestCloseOrder(params);
      return;
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::processRequestPing(string &params[])
  {
   this.pingExpire = TimeCurrent() + 30; // expire at next 30 seconds

   string result = StringFormat("PING|%s|PONG", params[1]);
   this.reply(pushSocket, result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::processRequestSubBars(string &params[])
  {
   string symbol = params[2];
   ENUM_TIMEFRAMES period = GetTimeframe(params[3]);
   this.markets.subscribeBar(symbol, period);

   string result = StringFormat("SUB_BARS|%s|OK", params[1]);
   this.reply(pushSocket, result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::processRequestUnsubBars(string &params[])
  {
   string symbol = params[2];
   ENUM_TIMEFRAMES period = GetTimeframe(params[3]);
   this.markets.unsubscribeBar(symbol, period);

   string result = StringFormat("UNSUB_BARS|%s|OK", params[1]);
   this.reply(pushSocket, result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::processRequestSubQuotes(string &params[])
  {
   string symbol = params[2];
   this.markets.subscribeQuote(symbol);

   string result = StringFormat("SUB_QUOTES|%s|OK", params[1]);
   this.reply(pushSocket, result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::processRequestUnsubQuotes(string &params[])
  {
   string symbol = params[2];
   this.markets.unsubscribeQuote(symbol);

   string result = StringFormat("UNSUB_QUOTES|%s|OK", params[1]);
   this.reply(pushSocket, result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::processRequestTime(string &params[])
  {
   string result = StringFormat("TIME|%s|%d", params[1], TimeCurrent());
   this.reply(pushSocket, result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::processRequestHistory(string &params[])
  {
   string symbol = params[2];
   ENUM_TIMEFRAMES period = GetTimeframe(params[3]);
   datetime startTime = StringToTime(params[4]);
   datetime endTime = StringToTime(params[5]);
   string result = StringFormat("HISTORY|%s|%s|%s|", params[1], params[2], params[3]);

   this.markets.getHistory(symbol, period, startTime, endTime, result);
   this.reply(pushSocket, result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::processRequestMarkets(string &params[])
  {
   string result = StringFormat("MARKETS|%s|", params[1]);
   this.markets.getMarkets(result);
   this.reply(pushSocket, result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::processRequestFund(string &params[])
  {
   string result = StringFormat("FUND|%s|", params[1]);
   this.account.getFund(result);
   this.reply(pushSocket, result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::processRequestTrades(string &params[])
  {
   string symbol = params[2];
   int modes[] = {OP_BUY, OP_SELL};
   string result = StringFormat("TRADES|%s|", params[1]);
   this.account.getOrders(symbol, modes, result);
   this.reply(pushSocket, result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::processRequestOrders(string &params[])
  {
   string symbol = params[2];
   int modes[] = {OP_BUYLIMIT, OP_BUYSTOP, OP_SELLLIMIT, OP_SELLSTOP};
   string result = StringFormat("ORDERS|%s|", params[1]);
   this.account.getOrders(symbol, modes, result);
   this.reply(pushSocket, result);
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

   string result = StringFormat("OPEN_ORDER|%s|", params[1]);
   int ticket = this.account.openOrder(symbol, type, lots, price, sl, tp, comment, result);
   if(ticket >= 0)
     {
      StringAdd(result, IntegerToString(ticket));
     }
   this.reply(pushSocket, result);

// put event OPEN ORDER
   string event = "";
   this.account.getOrderEventByTicket(ticket, EVENT_ORDER_OPENED, event);
   this.replyOrderEvents(event);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::processRequestModifyOrder(string &params[])
  {
   int ticket = StrToInteger(params[2]);
   double price = StringToDouble(params[3]);
   double sl = StringToDouble(params[4]);
   double tp = StringToDouble(params[5]);
   datetime expiration = StringToTime(params[6]);

   string result = StringFormat("MODIFY_ORDER|%s|", params[1]);
   bool ok = this.account.modifyOrder(ticket, price, sl, tp, expiration, result);
   if(ok)
     {
      StringAdd(result, "OK");
     }
   this.reply(pushSocket, result);

// put event MODIFY ORDER
   string event = "";
   this.account.getOrderEventByTicket(ticket, EVENT_ORDER_MODIFIED, event);
   this.replyOrderEvents(event);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::processRequestCloseOrder(string &params[])
  {
   int ticket = StrToInteger(params[2]);

   string result = StringFormat("CLOSE_ORDER|%s|", params[1]);
   bool ok = this.account.closeOrder(ticket, result);
   if(ok)
     {
      StringAdd(result, "OK");
     }
   this.reply(pushSocket, result);

// put event COMPLETED ORDER
   string event = "";
   this.account.getOrderEventByTicket(ticket, EVENT_ORDER_COMPLETED, event);
   this.replyOrderEvents(event);
  }
//+------------------------------------------------------------------+
