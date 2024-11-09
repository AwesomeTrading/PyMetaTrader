//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+

#include <Zmq/Zmq.mqh>

#include "Account.mqh"
#include "Helper.mqh"
#include "Markets.mqh"

#define ZMQ_WATERMARK 10000

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class MTServer {
 private:
  Context            *context;

  Socket             *clientRequestSocket;
  Socket             *clientPubSocket;

  MTMarkets          *markets;
  MTAccount          *account;

  ushort             separator;
  datetime           flushSubscriptionsAt;
  datetime           tradeRefreshStart;
  datetime           tradeRefreshAt;

  // Connection
  datetime           getOrdersMinTime();
  void               updateRefreshTrades();
  void               checkRefreshTrades();
  void               doRefreshTrades(void);

  // request
  void               checkRequest(bool prefix);
  void               parseRequest(string &message, string &retArray[]);
  bool               requestReply(string &id, string &message);
  bool               reply(Socket &socket, string message);
  bool               processRequest(string &params[], string &response);
  bool               processRequestPing(string &params[], string &response);

  // subscribers
  void               checkMarketSubscriptions();
  void               flushMarketSubscriptions();
  void               clearMarketSubscriptions();
  bool               publicSubscriptionBars();
  bool               publicSubscriptionQuotes();
  bool               publicSubscriptionTicks();
  bool               processRequestUnsubAll(string &params[], string &response);

  // Market
  bool               processRequestBars(string &params[], string &response);
  bool               processRequestSubBars(string &params[], string &response);
  bool               processRequestUnsubBars(string &params[], string &response);

  bool               processRequestQuotes(string &params[], string &response);
  bool               processRequestSubQuotes(string &params[], string &response);
  bool               processRequestUnsubQuotes(string &params[], string &response);

  bool               processRequestTicks(string &params[], string &response);
  bool               processRequestSubTicks(string &params[], string &response);
  bool               processRequestUnsubTicks(string &params[], string &response);

  bool               processRequestTime(string &params[], string &response);
  bool               processRequestMarkets(string &params[], string &response);

  // Account
  bool               processRequestAccount(string &params[], string &response);
  bool               processRequestFund(string &params[], string &response);

  bool               processRequestOrders(string &params[], string &response);
  bool               processRequestOpenOrder(string &params[], string &response);
  bool               processRequestModifyOrder(string &params[], string &response);
  bool               processRequestCancelOrder(string &params[], string &response);

  bool               processRequestTrades(string &params[], string &response);
  bool               processRequestModifyTrade(string &params[], string &response);
  bool               processRequestCloseTrade(string &params[], string &response);

  bool               processRequestDeals(string &params[], string &response);

  bool               publicRequestRefreshTrades(datetime fromDate, datetime toDate);

 public:
  MTServer(ulong magic, int deviation);
  bool               start(string brokerRequestURL, string brokerSubcribeURL);
  bool               stop();
  void               onTimer();
  void               onTrade();
};

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::MTServer(ulong magic, int deviation) {
  this.context = new Context(StringFormat("MTServer-%d", magic));
  this.clientRequestSocket = new Socket(this.context, ZMQ_REQ);
  this.clientPubSocket = new Socket(this.context, ZMQ_PUB);

  this.markets = new MTMarkets();
  this.account = new MTAccount(magic, deviation);

  this.flushSubscriptionsAt = 0;
  this.separator = StringGetCharacter(";", 0);

  this.tradeRefreshAt = 0;
  this.tradeRefreshStart = this.getOrdersMinTime();
  if(this.tradeRefreshStart == 0)
    this.tradeRefreshStart = TimeTradeServer();
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::start(string brokerRequestURL, string brokerSubcribeURL) {
  Print("Start Server");
  this.context.setBlocky(false);


  if(!this.clientRequestSocket.connect(brokerRequestURL)) {
    PrintFormat("[CLIENT REQ] ####ERROR#### connect to %s", brokerRequestURL);
    return false;
  } else {
    PrintFormat("[CLIENT REQ] Connected to %s",brokerRequestURL);
    //this.clientPushSocket.setSendHighWaterMark(ZMQ_WATERMARK);
    //this.clientPushSocket.setLinger(0);
  }
  /*if(!this.clientPubSocket.bind(brokerSubcribeURL)) {
    PrintFormat("[CLIENT PUB] ####ERROR#### Binding MTServer to %s", brokerSubcribeURL);
    return;
  } else {
    PrintFormat("[CLIENT PUB] Binding MTServer to port %s", brokerSubcribeURL);
    //this.clientPubSocket.setSendHighWaterMark(ZMQ_WATERMARK);
    //this.clientPubSocket.setLinger(0);
  }*/

  // Register worker to MQ Broker
  ZmqMsg ready("READY");
  this.clientRequestSocket.send(ready);
  return true;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::stop(void) {
  Print("Stop Server");
// Shutdown ZeroMQ Context
  context.shutdown();
  context.destroy(0);
  return true;
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::onTimer(void) {
  this.checkRequest();
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
void MTServer::checkRequest(bool prefix = false) {
  if(IsStopped())
    return;

  ZmqMsg request;

// Get client's response, block.
  this.clientRequestSocket.recv(request, true);
  if(request.size() == 0)
    return;

  string address = request.getData();

  this.clientRequestSocket.recv(request); // Envelope delimiter
  this.clientRequestSocket.recv(request); // Response from worker
  string message = request.getData();

// Process data
  PrintFormat("-> Request[%s]: %s", address, message);

  string params[];
  StringSplit(message, separator, params);

// Interpret data
  string result = "";
  bool ok = this.processRequest(params, result);

  this.clientRequestSocket.sendMore(address);
  this.clientRequestSocket.sendMore();

  // Reply
  string msg;
  if(ok) {
    msg = StringFormat("OK|%s", result);
  } else {
    int errorCode = GetLastError();
    msg = StringFormat("KO|%s", GetErrorDescription(errorCode));
  }

  Print("<- Reply: " + msg);
  this.clientRequestSocket.send(msg);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::requestReply(string &id, string &message) {
  int errorCode = GetLastError();
  string msg;
  if(errorCode == 0) {
    msg = StringFormat("OK|%s|", id);
    StringAdd(msg, message);
  } else {
    msg = StringFormat("KO|%s|%s", id, GetErrorDescription(errorCode));
  }

  ResetLastError();
  return this.reply(this.clientRequestSocket, msg);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::reply(Socket &socket, string message) {
  Print("<- Reply: " + message);
  ZmqMsg msg(message);
  bool ok = socket.send(msg, true);  // NON-BLOCKING
  if(!ok)
    Print("[ERROR] Cannot send data to socket");
  return ok;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::processRequest(string &params[], string &response) {
  string action = params[0];

// ping
  if(action == "PING")
    return this.processRequestPing(params, response);

// markets
  if(action == "BARS")
    return this.processRequestBars(params, response);
  if(action == "QUOTES")
    return this.processRequestQuotes(params, response);
  if(action == "MARKETS")
    return this.processRequestMarkets(params, response);
  if(action == "TIME")
    return this.processRequestTime(params, response);
  if(action == "SUB_BARS")
    return this.processRequestSubBars(params, response);
  if(action == "UNSUB_BARS")
    return this.processRequestUnsubBars(params, response);
  if(action == "SUB_QUOTES")
    return this.processRequestSubQuotes(params, response);
  if(action == "UNSUB_QUOTES")
    return this.processRequestUnsubQuotes(params, response);
  if(action == "SUB_TICKS")
    return this.processRequestSubTicks(params, response);
  if(action == "UNSUB_TICKS")
    return this.processRequestUnsubTicks(params, response);
  if(action == "UNSUB_ALL")
    return this.processRequestUnsubAll(params, response);

// account
  if(action == "ACCOUNT")
    return this.processRequestAccount(params, response);
  if(action == "FUND")
    return this.processRequestFund(params, response);

  if(action == "ORDERS")
    return this.processRequestOrders(params, response);
  if(action == "OPEN_ORDER")
    return this.processRequestOpenOrder(params, response);
  if(action == "MODIFY_ORDER")
    return this.processRequestModifyOrder(params, response);
  if(action == "CANCEL_ORDER")
    return this.processRequestCancelOrder(params, response);

  if(action == "TRADES")
    return this.processRequestTrades(params, response);
  if(action == "MODIFY_TRADE")
    return this.processRequestModifyTrade(params, response);
  if(action == "CLOSE_TRADE")
    return this.processRequestCloseTrade(params, response);

  if(action == "DEALS")
    return this.processRequestDeals(params, response);

  return false;
}

//+------------------------------------------------------------------+
//| SUBSCRIBERS                                                      |
//+------------------------------------------------------------------+
void MTServer::checkMarketSubscriptions() {
  if(this.flushSubscriptionsAt > TimeTradeServer())
    return;

  this.flushMarketSubscriptions();
  this.flushSubscriptionsAt = TimeTradeServer() + 2;  // flush every 2 seconds
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::updateRefreshTrades(void) {
  this.tradeRefreshAt = TimeTradeServer() + 1;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::checkRefreshTrades(void) {
  if(this.tradeRefreshAt == 0)
    return;
  if(this.tradeRefreshAt > TimeTradeServer())
    return;

  this.doRefreshTrades();
  this.tradeRefreshAt = 0;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::doRefreshTrades(void) {
  datetime now = TimeTradeServer();
  this.publicRequestRefreshTrades(this.tradeRefreshStart, now + 1);

// Refresh params
  this.tradeRefreshStart = this.getOrdersMinTime();
  if(this.tradeRefreshStart == 0)
    this.tradeRefreshStart = now;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
datetime MTServer::getOrdersMinTime(void) {
  int total = OrdersTotal();
  if(total == 0)
    return 0;

#ifdef __MQL5__
  if(OrderGetTicket(0))
    return (datetime)OrderGetInteger(ORDER_TIME_SETUP);
#endif

  return 0;
}
//+------------------------------------------------------------------+
#include "Request.mqh"
//+------------------------------------------------------------------+
