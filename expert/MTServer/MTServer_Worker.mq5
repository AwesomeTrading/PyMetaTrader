//+------------------------------------------------------------------+
//|                                                 MTServer_MT5.mq5 |
//|                                  Copyright 2021, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#include "./Worker.mqh"
#define MAGIC_NUMBER 1232131235587
#define DEVIATION 10
MTWorker *worker;
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   worker = new MTWorker(MAGIC_NUMBER, DEVIATION);
   EventSetMillisecondTimer(10);

//---
   if(!worker.start())
      return INIT_FAILED;
//---
   return INIT_SUCCEEDED;
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   worker.stop();
   EventKillTimer();
  }
//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
  {
   worker.onTimer();
  }
//+------------------------------------------------------------------+
