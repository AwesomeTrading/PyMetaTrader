//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+

#include <Zmq/Zmq.mqh>

#include "Account.mqh"
#include "Helper.mqh"
#include "Markets.mqh"

#define ZMQ_WATERMARK 1000

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class MTServer {
 private:
  Context            *context;

  Socket             *clientPushSocket;
  Socket             *clientPullSocket;
  Socket             *clientPubSocket;

  MTMarkets          *markets;
  MTAccount          *account;

  string             url_push;
  string             url_pull;
  string             url_pub;

  ushort             separator;
  datetime           flushSubscriptionsAt;
  datetime           tradeRefreshStart;
  datetime           tradeRefreshAt;

  // Connection
  bool               startSockets();
  bool               stopSockets();

  datetime           getOrdersMinTime();
  void               updateRefreshTrades();
  void               checkRefreshTrades();
  void               doRefreshTrades(void);

  // request
  void               checkRequest(Socket &socket, bool prefix);
  void               parseRequest(string &message, string &retArray[]);
  bool               requestReply(string &id, string &message);
  bool               reply(Socket &socket, string message);
  bool               processRequest(string &compArray[]);
  bool               processRequestPing(string &params[]);

  // subscribers
  void               checkMarketSubscriptions();
  void               flushMarketSubscriptions();
  void               clearMarketSubscriptions();
  bool               publicSubscriptionBars();
  bool               publicSubscriptionQuotes();
  bool               processRequestUnsubAll(string &params[]);

  // Market
  bool               processRequestBars(string &params[]);
  bool               processRequestSubBars(string &params[]);
  bool               processRequestUnsubBars(string &params[]);

  bool               processRequestQuotes(string &params[]);
  bool               processRequestSubQuotes(string &params[]);
  bool               processRequestUnsubQuotes(string &params[]);

  bool               processRequestTime(string &params[]);
  bool               processRequestMarkets(string &params[]);

  // Account
  bool               processRequestAccount(string &params[]);
  bool               processRequestFund(string &params[]);

  bool               processRequestOrders(string &params[]);
  bool               processRequestOpenOrder(string &params[]);
  bool               processRequestModifyOrder(string &params[]);
  bool               processRequestCancelOrder(string &params[]);

  bool               processRequestTrades(string &params[]);
  bool               processRequestModifyTrade(string &params[]);
  bool               processRequestCloseTrade(string &params[]);

  bool               processRequestDeals(string &params[]);

  bool               publicRequestRefreshTrades(datetime fromDate, datetime toDate);

 public:
                     MTServer(ulong magic, int deviation, int portStart);
  bool               start();
  bool               stop();
  void               onTimer();
  void               onTrade();
};

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::MTServer(ulong magic, int deviation, int portStart) {
  this.context = new Context(StringFormat("MTServer-%d", magic));

  this.url_push = StringFormat("tcp://*:%d", portStart);
  this.url_pull = StringFormat("tcp://*:%d", portStart + 1);
  this.url_pub = StringFormat("tcp://*:%d", portStart + 2);

  this.clientPushSocket = new Socket(this.context, ZMQ_PUSH);
  this.clientPullSocket = new Socket(this.context, ZMQ_PULL);
  this.clientPubSocket = new Socket(this.context, ZMQ_PUB);

  this.markets = new MTMarkets();
  this.account = new MTAccount(magic, deviation);

  this.flushSubscriptionsAt = 0;
  this.separator = StringGetCharacter(";", 0);

  this.tradeRefreshAt = 0;
  this.tradeRefreshStart = this.getOrdersMinTime();
  if (this.tradeRefreshStart == 0)
    this.tradeRefreshStart = TimeCurrent();
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::start(void) {
  Print("Start Server");
  this.context.setBlocky(false);
  this.startSockets();
  return true;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::stop(void) {
  Print("Stop Server");
  this.stopSockets();
  return true;
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::onTimer(void) {
  this.checkRequest(this.clientPullSocket);
  this.checkMarketSubscriptions();
  this.checkRefreshTrades();
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::onTrade(void) {
  this.updateRefreshTrades();
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::startSockets(void) {
// Client
  if (!clientPushSocket.bind(this.url_pull)) {
    PrintFormat("[CLIENT PUSH] ####ERROR#### Binding MTServer to %s", this.url_pull);
    return false;
  } else {
    PrintFormat("[CLIENT PUSH] Binding MTServer to %s", this.url_pull);
    this.clientPushSocket.setSendHighWaterMark(ZMQ_WATERMARK);
    this.clientPushSocket.setLinger(0);
  }

  if (!this.clientPullSocket.bind(this.url_push)) {
    PrintFormat("[CLIENT PULL] ####ERROR#### Binding MTServer to %s", this.url_push);
    return false;
  } else {
    PrintFormat("[CLIENT PULL] Binding MTServer to %s", this.url_push);
    this.clientPullSocket.setReceiveHighWaterMark(ZMQ_WATERMARK);
    this.clientPullSocket.setLinger(0);
  }

  if (!this.clientPubSocket.bind(this.url_pub)) {
    PrintFormat("[CLIENT PUB] ####ERROR#### Binding MTServer to %s", this.url_pub);
    return false;
  } else {
    PrintFormat("[CLIENT PUB] Binding MTServer to port %s", this.url_pub);
    this.clientPubSocket.setSendHighWaterMark(ZMQ_WATERMARK);
    this.clientPubSocket.setLinger(0);
  }

  return true;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::stopSockets(void) {
  this.clientPushSocket.unbind(this.url_push);
  this.clientPullSocket.unbind(this.url_pull);
  this.clientPubSocket.unbind(this.url_pub);

// Shutdown ZeroMQ Context
  context.shutdown();
  context.destroy(0);
  return true;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::checkRequest(Socket &socket, bool prefix = false) {
  if (IsStopped())
    return;

  ZmqMsg request;

// Get client's response, but don't block.
  socket.recv(request, true);

  if (request.size() == 0)
    return;

// Message components for later.
  string params[10];
  string message = request.getData();
  if (prefix) {
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
bool MTServer::requestReply(string &id, string &message) {
  int errorCode = GetLastError();
  string msg;
  if (errorCode == 0) {
    msg = StringFormat("OK|%s|", id);
    StringAdd(msg, message);
  } else {
    msg = StringFormat("KO|%s|%s", id, GetErrorDescription(errorCode));
  }

  ResetLastError();
  return this.reply(this.clientPushSocket, msg);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::reply(Socket &socket, string message) {
  Print("<- Reply: " + message);
  ZmqMsg msg(message);
  bool ok = socket.send(msg, true);  // NON-BLOCKING
  if (!ok)
    Print("[ERROR] Cannot send data to socket");
  return ok;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::processRequest(string &params[]) {
  string action = params[0];

// ping
  if (action == "PING")
    return this.processRequestPing(params);

// markets
  if (action == "BARS")
    return this.processRequestBars(params);
  if (action == "QUOTES")
    return this.processRequestQuotes(params);
  if (action == "MARKETS")
    return this.processRequestMarkets(params);
  if (action == "TIME")
    return this.processRequestTime(params);
  if (action == "SUB_BARS")
    return this.processRequestSubBars(params);
  if (action == "UNSUB_BARS")
    return this.processRequestUnsubBars(params);
  if (action == "SUB_QUOTES")
    return this.processRequestSubQuotes(params);
  if (action == "UNSUB_QUOTES")
    return this.processRequestUnsubQuotes(params);
  if (action == "UNSUB_ALL")
    return this.processRequestUnsubAll(params);

// account
  if (action == "ACCOUNT")
    return this.processRequestAccount(params);
  if (action == "FUND")
    return this.processRequestFund(params);

  if (action == "ORDERS")
    return this.processRequestOrders(params);
  if (action == "OPEN_ORDER")
    return this.processRequestOpenOrder(params);
  if (action == "MODIFY_ORDER")
    return this.processRequestModifyOrder(params);
  if (action == "CANCEL_ORDER")
    return this.processRequestCancelOrder(params);

  if (action == "TRADES")
    return this.processRequestTrades(params);
  if (action == "MODIFY_TRADE")
    return this.processRequestModifyTrade(params);
  if (action == "CLOSE_TRADE")
    return this.processRequestCloseTrade(params);

  if (action == "DEALS")
    return this.processRequestDeals(params);

  return false;
}

//+------------------------------------------------------------------+
//| SUBSCRIBERS                                                      |
//+------------------------------------------------------------------+
void MTServer::checkMarketSubscriptions() {
  if (this.flushSubscriptionsAt > TimeCurrent())
    return;

  this.flushMarketSubscriptions();
  this.flushSubscriptionsAt = TimeCurrent() + 2;  // flush every 2 seconds
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::updateRefreshTrades(void) {
  this.tradeRefreshAt = TimeCurrent() + 1;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::checkRefreshTrades(void) {
  if (this.tradeRefreshAt == 0)
    return;
  if (this.tradeRefreshAt > TimeCurrent())
    return;

  this.doRefreshTrades();
  this.tradeRefreshAt = 0;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::doRefreshTrades(void) {
  datetime now = TimeCurrent();
  this.publicRequestRefreshTrades(this.tradeRefreshStart, now + 1);

// Refresh params
  this.tradeRefreshStart = this.getOrdersMinTime();
  if (this.tradeRefreshStart == 0)
    this.tradeRefreshStart = now;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
datetime MTServer::getOrdersMinTime(void) {
  int total = OrdersTotal();
  if (total == 0)
    return 0;

#ifdef __MQL5__
  if (OrderGetTicket(0))
    return (datetime)OrderGetInteger(ORDER_TIME_SETUP);
#endif

  return 0;
}
//+------------------------------------------------------------------+
#include "Request.mqh"
//+------------------------------------------------------------------+
