//+------------------------------------------------------------------+
//|                                                 MTServer_MT5.mq5 |
//|                                  Copyright 2021, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#include "./Server.mqh"
#define MAGIC_NUMBER 123 + MathRand()
#define DEVIATION 10

input int Server_PortStart = 30000;  // Server: Port start at

MTServer *m_server;
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
  m_server = new MTServer(MAGIC_NUMBER, DEVIATION, Server_PortStart);
  EventSetMillisecondTimer(10);

//---
  if (!m_server.start())
    return INIT_FAILED;
//---
  return INIT_SUCCEEDED;
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
  m_server.stop();
  EventKillTimer();
}
//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer() {
  m_server.onTimer();
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTrade() {
  m_server.onTrade();
}
//+------------------------------------------------------------------+
