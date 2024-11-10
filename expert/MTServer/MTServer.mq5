//+------------------------------------------------------------------+
//|                                                 MTServer_MT5.mq5 |
//|                                  Copyright 2021, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#include "./Server.mqh"
#define MAGIC_NUMBER 123 + MathRand()
#define DEVIATION 10

input string Server_Request_URL = "tcp://127.0.0.1:28028";    // Server: Request URL
input string Server_Subscribe_URL = "tcp://127.0.0.1:28029";  // Server: Subscribe URL

MTServer *m_server;
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
  m_server = new MTServer(MAGIC_NUMBER, DEVIATION);
  EventSetMillisecondTimer(10);

//---
  if (!m_server.start(Server_Request_URL, Server_Subscribe_URL))
    return INIT_FAILED;
//---
  return INIT_SUCCEEDED;
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
  m_server.stop();
  delete m_server;
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
