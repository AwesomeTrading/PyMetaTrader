//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+

#include <Zmq/Zmq.mqh>

#include "Account.mqh"
#include "Helper.mqh"
#include "Markets.mqh"

#define PROJECT_NAME "MTSERVER"
#define CLIENT_PUSH_URL "tcp://*:30001"
#define CLIENT_PULL_URL "tcp://*:30002"
#define CLIENT_PUB_URL "tcp://*:30003"

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

  ushort             separator;
  datetime           flushSubscriptionsAt;
  datetime           tradeRefreshStart;
  datetime           tradeRefreshAt;

  // Connection
  bool               startSockets();
  bool               stopSockets();
  void               exchangeMsg();
  bool               reply(Socket &socket, string message);

  datetime           getOrdersMinTime();
  void               updateRefreshTrades();
  void               checkRefreshTrades();
  void               doRefreshTrades(void);

  // request
  void               checkRequest(Socket &socket, bool prefix);
  void               parseRequest(string &message, string &retArray[]);
  bool               requestReply(string &id, string &message);
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
                     MTServer(ulong magic, int deviation);
  bool               start();
  bool               stop();
  void               onTimer();
  void               onTrade();
};

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::MTServer(ulong magic, int deviation) {
  this.context = new Context(PROJECT_NAME);
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
  this.exchangeMsg();
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
  if (!clientPushSocket.bind(CLIENT_PULL_URL)) {
    PrintFormat("[CLIENT PUSH] ####ERROR#### Binding MTServer to %s", CLIENT_PULL_URL);
    return false;
  } else {
    PrintFormat("[CLIENT PUSH] Binding MTServer to %s", CLIENT_PULL_URL);
    this.clientPushSocket.setSendHighWaterMark(ZMQ_WATERMARK);
    this.clientPushSocket.setLinger(0);
  }

  if (!this.clientPullSocket.bind(CLIENT_PUSH_URL)) {
    PrintFormat("[CLIENT PULL] ####ERROR#### Binding MTServer to %s", CLIENT_PUSH_URL);
    return false;
  } else {
    PrintFormat("[CLIENT PULL] Binding MTServer to %s", CLIENT_PUSH_URL);
    this.clientPullSocket.setReceiveHighWaterMark(ZMQ_WATERMARK);
    this.clientPullSocket.setLinger(0);
  }

  if (!this.clientPubSocket.bind(CLIENT_PUB_URL)) {
    PrintFormat("[CLIENT PUB] ####ERROR#### Binding MTServer to %s", CLIENT_PUB_URL);
    return false;
  } else {
    PrintFormat("[CLIENT PUB] Binding MTServer to port %s", CLIENT_PUB_URL);
    this.clientPubSocket.setSendHighWaterMark(ZMQ_WATERMARK);
    this.clientPubSocket.setLinger(0);
  }

  return true;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::stopSockets(void) {
  this.clientPushSocket.unbind(CLIENT_PUSH_URL);
  this.clientPullSocket.unbind(CLIENT_PULL_URL);
  this.clientPubSocket.unbind(CLIENT_PUB_URL);

// Shutdown ZeroMQ Context
  context.shutdown();
  context.destroy(0);
  return true;
}

//+------------------------------------------------------------------+
//| Message exchange                         |
//+------------------------------------------------------------------+
void MTServer::exchangeMsg(void) {
  this.checkRequest(this.clientPullSocket);
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
