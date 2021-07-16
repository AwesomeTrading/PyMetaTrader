//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+

#include <Zmq/Zmq.mqh>
#include  "Markets.mqh"
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
   MTMarkets           *markets;

   bool              startSockets();
   bool              stopSockets();
   bool              status();
   void              checkRequest();
   void              parseRequest(string& message, string& retArray[]);
   void              reply(Socket& socket, string message);
   void              processRequest(string &compArray[]);
   void              processRequestHistory(string &params[]);
   void              processRequestSymbols(string &params[]);

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

   delete context;
   delete pushSocket;
   delete pullSocket;
   delete pubSocket;
   return true;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::onTick(void)
  {
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
   Print("Stop socket");

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
// Is _StopFlag == True, inform the client application
   if(IsStopped())
     {
      //InformPullClient(pullSocket, "{'_response': 'EA_IS_STOPPED'}");
      return(false);
     }

// Default
   return(true);
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
void MTServer::processRequest(string &params[])
  {
   string action = params[0];

   if(action == "HISTORY")
     {
      this.processRequestHistory(params);
      return;
     }
   if(action == "SYMBOLS")
     {
      this.processRequestSymbols(params);
      return;
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::parseRequest(string& message, string& result[])
  {
   Print("Parsing: " + message);

   string sep = ";";
   ushort u_sep = StringGetCharacter(sep,0);
   int splits = StringSplit(message, u_sep, result);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::reply(Socket& socket, string message)
  {
   Print("Reply: " + message);
   ZmqMsg msg(message);
   socket.send(msg,true); // NON-BLOCKING
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

   this.markets.history(symbol, period, startTime, endTime, result);
   this.reply(pushSocket, result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTServer::processRequestSymbols(string &params[])
  {
   string result = StringFormat("SYMBOLS|%s|", params[1]);
   this.markets.getSymbols(result);
   this.reply(pushSocket, result);
  }

//+------------------------------------------------------------------+
