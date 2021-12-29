//+------------------------------------------------------------------+
//|                                                 MTServer_MT5.mq5 |
//|                                  Copyright 2021, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#include "./Server.mqh"
#define MAGIC_NUMBER 1122334455
#define DEVIATION 10
MTServer *server;
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   server = new MTServer(MAGIC_NUMBER, DEVIATION);
   EventSetMillisecondTimer(10);

//---
   if(!server.start())
      return INIT_FAILED;
//---
   return INIT_SUCCEEDED;
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   server.stop();
   EventKillTimer();
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   server.onTick();
  }
//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
  {
   server.onTimer();
  }
//+------------------------------------------------------------------+
