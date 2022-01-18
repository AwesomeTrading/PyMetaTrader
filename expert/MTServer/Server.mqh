//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+

#include <Zmq/Zmq.mqh>

#define PROJECT_NAME "MTSERVER"
#define CLIENT_PUSH_URL "tcp://*:30001"
#define CLIENT_PULL_URL "tcp://*:30002"
#define CLIENT_PUB_URL "tcp://*:30003"
#define WORKER_PULL_URL "tcp://127.0.0.1:32001"
#define WORKER_PUSH_URL "tcp://127.0.0.1:32002"
#define WORKER_PUB_URL "tcp://127.0.0.1:32003"
#define WORKER_SUB_URL "tcp://127.0.0.1:32004"

#define ZMQ_WATERMARK 1000

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class MTServer
  {
private:
   Context           *context;
   Socket            *clientPushSocket;
   Socket            *clientPullSocket;
   Socket            *clientPubSocket;

   Socket            *workerPushSocket;
   Socket            *workerPullSocket;
   Socket            *workerSubSocket;
   Socket            *workerXPubSocket;

   datetime          msgTimeout;
   datetime          tradeRefreshStart;
   datetime          tradeRefreshAt;

   bool              startSockets();
   bool              stopSockets();
   bool              checkTimeout(void);
   void              exchangeMsg();
   bool              getMsg(Socket &socket, ZmqMsg &msg);
   bool              sendMsg(Socket &socket, ZmqMsg &msg);

   bool              broadcastWorkers(string msg);
   bool              clearWorkersSubscriptions();
   datetime          getOrdersMinTime();
   void              updateRefreshTrades();
   void              checkRefreshTrades();
   void              doRefreshTrades(void);
public:
                     MTServer(ulong magic);
   bool              start();
   bool              stop();
   void              onTimer();
   void              onTrade();
  };

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::MTServer(ulong magic)
  {
   this.context = new Context(PROJECT_NAME);
   this.clientPushSocket = new Socket(this.context, ZMQ_PUSH);
   this.clientPullSocket = new Socket(this.context, ZMQ_PULL);
   this.clientPubSocket = new Socket(this.context, ZMQ_PUB);

   this.workerPushSocket = new Socket(this.context, ZMQ_PUSH);
   this.workerPullSocket = new Socket(this.context, ZMQ_PULL);
   this.workerSubSocket = new Socket(this.context, ZMQ_PULL);
   this.workerXPubSocket = new Socket(this.context, ZMQ_XPUB);

   this.msgTimeout = TimeCurrent() + 30; // expire at next 30 seconds
   this.tradeRefreshAt = 0;
   this.tradeRefreshStart = this.getOrdersMinTime();
   if(this.tradeRefreshStart == 0)
      this.tradeRefreshStart = TimeCurrent();
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
   return true;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::onTimer(void)
  {
   this.checkTimeout();
   this.exchangeMsg();
   this.checkRefreshTrades();
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::onTrade(void)
  {
   this.updateRefreshTrades();
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::startSockets(void)
  {
// Client
   if(!clientPushSocket.bind(CLIENT_PULL_URL))
     {
      PrintFormat("[CLIENT PUSH] ####ERROR#### Binding MTServer to %s", CLIENT_PULL_URL);
      return false;
     }
   else
     {
      PrintFormat("[CLIENT PUSH] Binding MTServer to %s", CLIENT_PULL_URL);
      this.clientPushSocket.setSendHighWaterMark(ZMQ_WATERMARK);
      this.clientPushSocket.setLinger(0);
     }

   if(!this.clientPullSocket.bind(CLIENT_PUSH_URL))
     {
      PrintFormat("[CLIENT PULL] ####ERROR#### Binding MTServer to %s", CLIENT_PUSH_URL);
      return false;
     }
   else
     {
      PrintFormat("[CLIENT PULL] Binding MTServer to %s", CLIENT_PUSH_URL);
      this.clientPullSocket.setReceiveHighWaterMark(ZMQ_WATERMARK);
      this.clientPullSocket.setLinger(0);
     }

   if(!this.clientPubSocket.bind(CLIENT_PUB_URL))
     {
      PrintFormat("[CLIENT PUB] ####ERROR#### Binding MTServer to %s", CLIENT_PUB_URL);
      return false;
     }
   else
     {
      PrintFormat("[CLIENT PUB] Binding MTServer to port %s", CLIENT_PUB_URL);
      this.clientPubSocket.setSendHighWaterMark(ZMQ_WATERMARK);
      this.clientPubSocket.setLinger(0);
     }

// Worker
   if(!this.workerPushSocket.bind(WORKER_PULL_URL))
     {
      PrintFormat("[WORKER PUSH] ####ERROR#### Binding to %s", WORKER_PULL_URL);
      return false;
     }
   else
     {
      PrintFormat("[WORKER PUSH] Binding to %s", WORKER_PULL_URL);
      this.workerPushSocket.setSendHighWaterMark(ZMQ_WATERMARK);
      this.workerPushSocket.setLinger(0);
     }

   if(!this.workerPullSocket.bind(WORKER_PUSH_URL))
     {
      PrintFormat("[WORKER PULL] ####ERROR#### Binding to %s", WORKER_PUSH_URL);
      return false;
     }
   else
     {
      PrintFormat("[WORKER PULL] Binding to port %s", WORKER_PUSH_URL);
      this.workerPullSocket.setReceiveHighWaterMark(ZMQ_WATERMARK);
      this.workerPullSocket.setLinger(0);
     }

   if(!this.workerSubSocket.bind(WORKER_PUB_URL))
     {
      PrintFormat("[WORKER SUB] ####ERROR#### Binding to %s", WORKER_PUB_URL);
      return false;
     }
   else
     {
      PrintFormat("[WORKER SUB] Binding to %s", WORKER_PUB_URL);
      this.workerSubSocket.setReceiveHighWaterMark(ZMQ_WATERMARK);
      this.workerSubSocket.setLinger(0);
     }


   if(!this.workerXPubSocket.bind(WORKER_SUB_URL))
     {
      PrintFormat("[WORKER XPUB] ####ERROR#### Binding to %s", WORKER_SUB_URL);
      return false;
     }
   else
     {
      PrintFormat("[WORKER XPUB] Binding to %s", WORKER_SUB_URL);
      this.workerXPubSocket.setSendHighWaterMark(ZMQ_WATERMARK);
      this.workerXPubSocket.setLinger(0);
     }

   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::stopSockets(void)
  {
   this.clientPushSocket.unbind(CLIENT_PUSH_URL);
   this.clientPullSocket.unbind(CLIENT_PULL_URL);
   this.clientPubSocket.unbind(CLIENT_PUB_URL);

   this.workerPushSocket.unbind(WORKER_PUSH_URL);
   this.workerPullSocket.unbind(WORKER_PULL_URL);
   this.workerSubSocket.unbind(WORKER_PUB_URL);
   this.workerXPubSocket.unbind(WORKER_SUB_URL);

// Shutdown ZeroMQ Context
   context.shutdown();
   context.destroy(0);
   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::broadcastWorkers(string request)
  {
   ZmqMsg msg(StringFormat("ALL %s", request));
   return this.workerXPubSocket.send(msg, true); // NON-BLOCKING
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::checkTimeout(void)
  {
   if(TimeCurrent() > this.msgTimeout)
     {
      this.msgTimeout = TimeCurrent() + 3 * 60; // expire at next 3 minutes
      this.clearWorkersSubscriptions();
      return false;
     }
   return true;
  }
//+------------------------------------------------------------------+
//| Message exchange between client & workers                        |
//+------------------------------------------------------------------+
void MTServer::exchangeMsg(void)
  {
   ZmqMsg msg;
   while(this.getMsg(this.clientPullSocket, msg))
     {
      this.msgTimeout = TimeCurrent() + 30; // expire at next 30 seconds

      // Send unsub messages to all worker
      if(StringSubstr(msg.getData(), 6) == "UNSUB_")
        {
         this.broadcastWorkers(msg.getData());
        }
      else
         if(!this.sendMsg(this.workerPushSocket, msg))
           {
            PrintFormat("[ERROR] Cannot send msg to worker: %s", msg.getData());
           }
     }

   while(this.getMsg(this.workerPullSocket, msg))
     {
      if(!this.sendMsg(this.clientPushSocket, msg))
        {
         PrintFormat("[ERROR] Cannot send msg to client: %s", msg.getData());
         this.clearWorkersSubscriptions();
        }
     }

   while(this.getMsg(this.workerSubSocket, msg))
     {
      if(!this.sendMsg(this.clientPubSocket, msg))
        {
         PrintFormat("[ERROR] Cannot pub msg to client: %s", msg.getData());
         this.clearWorkersSubscriptions();
        }
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::getMsg(Socket &socket, ZmqMsg &msg)
  {
// Get msg, but don't block.
   socket.recv(msg, true);
   return msg.size() > 0;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTServer::sendMsg(Socket &socket, ZmqMsg &msg)
  {
   return socket.send(msg, true); // NON-BLOCKING
  }
//+------------------------------------------------------------------+
//| UNSUB_ALL                                                        |
//+------------------------------------------------------------------+
bool MTServer::clearWorkersSubscriptions(void)
  {
   return this.broadcastWorkers("UNSUB_ALL");
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::updateRefreshTrades(void)
  {
   this.tradeRefreshAt = TimeCurrent() + 1;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::checkRefreshTrades(void)
  {
   if(this.tradeRefreshAt == 0)
      return;
   if(this.tradeRefreshAt > TimeCurrent())
      return;

   this.doRefreshTrades();
   this.tradeRefreshAt = 0;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::doRefreshTrades(void)
  {
   datetime now = TimeCurrent();
   ZmqMsg msg(StringFormat("REFRESH_TRADES;;%f;%f", this.tradeRefreshStart, (now+1)));
   this.workerPushSocket.send(msg, true); // NON-BLOCKING

// Refresh params
   this.tradeRefreshStart = this.getOrdersMinTime();
   if(this.tradeRefreshStart == 0)
      this.tradeRefreshStart = now;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
datetime MTServer::getOrdersMinTime(void)
  {
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
