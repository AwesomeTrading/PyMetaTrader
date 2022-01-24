//+------------------------------------------------------------------+
//|                                                 MTServer_MT5.mq5 |
//|                                  Copyright 2021, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#include "./Worker.mqh"
#define MAGIC_NUMBER 456 + MathRand()
#define DEVIATION 10

MTWorker *m_worker;
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   m_worker = new MTWorker(MAGIC_NUMBER, DEVIATION);
   EventSetMillisecondTimer(10);

//---
   if(!m_worker.start())
      return INIT_FAILED;
//---
   return INIT_SUCCEEDED;
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   m_worker.stop();
   EventKillTimer();
  }
//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
  {
   m_worker.onTimer();
  }
//+------------------------------------------------------------------+
