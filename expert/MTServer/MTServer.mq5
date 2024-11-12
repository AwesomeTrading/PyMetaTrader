//+------------------------------------------------------------------+
//|                                                 MTServer_MT5.mq5 |
//|                                  Copyright 2021, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#include "./Server.mqh"
#define MAGIC_NUMBER 123 + MathRand()
#define DEVIATION 10

input string Server_Request_URL = "tcp://127.0.0.1:22990";    // Server: Request URL
input int Server_Request_Timeout = 60;  // Server: Request timeout in second
input string Server_Subscribe_URL = "tcp://127.0.0.1:22991";  // Server: Subscribe URL
input int Server_Subscribe_Delay = 1;  // Server: Subscribe delay in second

MTServer *m_server;
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
  m_server = new MTServer(MAGIC_NUMBER, DEVIATION, Server_Request_URL, Server_Request_Timeout, Server_Subscribe_URL, Server_Subscribe_Delay);
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
