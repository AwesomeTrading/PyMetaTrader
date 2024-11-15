//+------------------------------------------------------------------+
//|                                                      ProjectName |
//|                                      Copyright 2018, CompanyName |
//|                                       http://www.companyname.net |
//+------------------------------------------------------------------+
#include "Helper.mqh"

#ifdef __MQL5__
#include <Trade\SymbolInfo.mqh>
#include <Trade\Trade.mqh>
#endif

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class MTAccount {
 private:
#ifdef __MQL4__
  int                magic;
  int                slippage;
#endif
#ifdef __MQL5__
  CTrade             m_trade;
  CSymbolInfo        m_symbol;
#endif

 public:
  void               MTAccount(ulong magic, int deviation);
  void               ~MTAccount();
  bool               getAccount(string &result);
  bool               getFund(string &result);
  void               refresh(void);

  // Order
  bool               getOrders(string &result, string symbol);
  bool               getOrder(string &result, ulong ticket);
  ulong              openOrder(string &result, string symbol, int type, double lots, double price, double sl, double tp, string comment);
  bool               modifyOrder(string &result, ulong ticket, double price, double sl, double tp, datetime expiration);
  bool               cancelOrder(string &result, ulong ticket);
  bool               parseOrder(string &result, bool prefix);

  // History
  bool               getHistoryOrders(string &result, string symbol, datetime fromDate, datetime toDate);
  bool               getHistoryOrder(string &result, ulong ticket);
  bool               parseHistoryOrder(string &result, ulong ticket, bool prefix);

  bool               getHistoryDeals(string &result, string symbol, datetime fromDate, datetime toDate);
  bool               getHistoryDeal(string &result, ulong ticket);
  bool               parseHistoryDeal(string &result, ulong ticket, bool prefix);

  // Trade
  bool               getTrades(string &result, string symbol);
  bool               getTrade(string &result, ulong ticket);
  bool               modifyTrade(string &result, ulong ticket, double sl, double tp);
  bool               closeTrade(string &result, ulong ticket);
  bool               parseTrade(string &result, bool prefix);
};

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTAccount::MTAccount(ulong magic, int deviation) {
#ifdef __MQL4__
  this.magic = magic;
  this.slippage = deviation;
#endif
#ifdef __MQL5__
  this.m_trade.SetExpertMagicNumber(magic);
  this.m_trade.SetDeviationInPoints(deviation);
#endif
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTAccount::~MTAccount(void) {
}
//+------------------------------------------------------------------+
//| ACCOUNT                                                          |
//+------------------------------------------------------------------+
bool MTAccount::getAccount(string &result) {
#ifdef __MQL4__
  int leverage = AccountLeverage();
#endif
#ifdef __MQL5__
  long id = AccountInfoInteger(ACCOUNT_LOGIN);
  string name = AccountInfoString(ACCOUNT_NAME);
  string company = AccountInfoString(ACCOUNT_COMPANY);
  string server = AccountInfoString(ACCOUNT_SERVER);
  string currency = AccountInfoString(ACCOUNT_CURRENCY);
  double deposit = AccountInfoDouble(ACCOUNT_BALANCE);
  double margin = AccountInfoDouble(ACCOUNT_MARGIN);
  long leverage = AccountInfoInteger(ACCOUNT_LEVERAGE);
// Type
  string type = AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO ? "demo" : "real";
#endif
  int gmtoffset = (int)(MathCeil((double)(TimeTradeServer() - TimeGMT())/10)*10);

  StringAdd(result, StringFormat("id=%I64u", id));
  StringAdd(result, StringFormat("|name=%s", name));
  StringAdd(result, StringFormat("|company=%s", company));
  StringAdd(result, StringFormat("|server=%s", server));
  StringAdd(result, StringFormat("|type=%s", type));
  StringAdd(result, StringFormat("|currency=%s", currency));
  StringAdd(result, StringFormat("|deposit=%g", deposit));
  StringAdd(result, StringFormat("|margin=%g", margin));
  StringAdd(result, StringFormat("|leverage=%d", leverage));
  StringAdd(result, StringFormat("|gmtoffset=%d", gmtoffset));
  return true;
}
//+------------------------------------------------------------------+
//| FUND                                                             |
//+------------------------------------------------------------------+
bool MTAccount::getFund(string &result) {
#ifdef __MQL4__
  double balance = AccountBalance();
  double equity = AccountEquity();
#endif
#ifdef __MQL5__
  double balance = AccountInfoDouble(ACCOUNT_BALANCE);
  double equity = AccountInfoDouble(ACCOUNT_EQUITY);
#endif

  StringAdd(result, StringFormat("balance=%g", balance));
  StringAdd(result, StringFormat("|equity=%g", equity));
  return true;
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTAccount::refresh(void) {
#ifdef __MQL5__
  this.m_symbol.Refresh();
#endif
}
//+------------------------------------------------------------------+
//| ORDERS                                                           |
//+------------------------------------------------------------------+
bool MTAccount::getOrders(string &result, string symbol = "") {
  int total = OrdersTotal();
  if(total == 0)
    return true;

// loop
  for(int i = 0; i < total; i++) {
#ifdef __MQL4__
    if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      continue;
    if(StringLen(symbol) > 0 && OrderSymbol() != symbol)
      continue;
#endif
#ifdef __MQL5__
    if(OrderGetTicket(i) <= 0)
      continue;
    if(StringLen(symbol) > 0 && OrderGetString(ORDER_SYMBOL) != symbol)
      continue;
#endif

    this.parseOrder(result, i > 0);
  }
  return true;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTAccount::getOrder(string &result, ulong ticket) {
#ifdef __MQL4__
  if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
    return false;
#endif
#ifdef __MQL5__
  if(!OrderSelect(ticket))
    return false;
#endif

  this.parseOrder(result, false);
  return true;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
ulong MTAccount::openOrder(string &result, string symbol, int type, double lots, double price, double sl, double tp, string comment) {
#ifdef __MQL4__
  double digits = MarketInfo(symbol, MODE_DIGITS);
#endif
#ifdef __MQL5__
  int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
#endif

  price = NormalizeDouble(price, digits);
  sl = NormalizeDouble(sl, digits);
  tp = NormalizeDouble(tp, digits);

#ifdef __MQL4__
  return OrderSend(symbol, type, lots, price, this.slippage, sl, tp, comment, this.magic);
#endif
#ifdef __MQL5__
// Refresh rates
  this.m_symbol.Name(symbol);
  this.m_symbol.RefreshRates();

  bool ok;
  switch(type) {
  case ORDER_TYPE_BUY:
    ok = this.m_trade.PositionOpen(symbol, (ENUM_ORDER_TYPE)type, lots, this.m_symbol.Ask(), sl, tp, comment);
    break;
  case ORDER_TYPE_SELL:
    ok = this.m_trade.PositionOpen(symbol, (ENUM_ORDER_TYPE)type, lots, this.m_symbol.Bid(), sl, tp, comment);
    break;
  default:
    ok = this.m_trade.OrderOpen(symbol, (ENUM_ORDER_TYPE)type, lots, NULL, price, sl, tp, ORDER_TIME_GTC, 0, comment);
    break;
  }

  if(ok)
    return this.m_trade.ResultOrder();
  return 0;
#endif
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTAccount::modifyOrder(string &result, ulong ticket, double price, double sl, double tp, datetime expiration) {
#ifdef __MQL4__
  double digits = MarketInfo(symbol, MODE_DIGITS);
#endif
#ifdef __MQL5__
  if(!OrderSelect(ticket))
    return false;

  int digits = (int)SymbolInfoInteger(OrderGetString(ORDER_SYMBOL), SYMBOL_DIGITS);
#endif

  price = NormalizeDouble(price, digits);
  sl = NormalizeDouble(sl, digits);
  tp = NormalizeDouble(tp, digits);

#ifdef __MQL4__
  return OrderModify(ticket, price, sl, tp, expiration);
#endif
#ifdef __MQL5__
  return this.m_trade.OrderModify(ticket, price, sl, tp, ORDER_TIME_GTC, expiration);
#endif
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTAccount::cancelOrder(string &result, ulong ticket) {
#ifdef __MQL4__
  return OrderDelete(ticket);
#endif
#ifdef __MQL5__
  return this.m_trade.OrderDelete(ticket);
#endif
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTAccount::parseOrder(string &result, bool prefix = false) {
#ifdef __MQL4__
  ulong ticket = OrderTicket();
  string symbol = OrderSymbol();
  string type = OperationTypeToString(OrderType());
  double openPrice = OrderOpenPrice();
  long openTime = OrderOpenTime();
  double lots = OrderLots();
  double sl = OrderStopLoss();
  double tp = OrderTakeProfit();
  long expiration = OrderExpiration();
  string comment = OrderComment();
#endif
#ifdef __MQL5__
  ulong ticket = OrderGetInteger(ORDER_TICKET);
  ulong position = OrderGetInteger(ORDER_POSITION_ID);
  string symbol = OrderGetString(ORDER_SYMBOL);
  string state = EnumToString((ENUM_ORDER_STATE)OrderGetInteger(ORDER_STATE));
  string type = OperationTypeToString(OrderGetInteger(ORDER_TYPE));
  double openPrice = OrderGetDouble(ORDER_PRICE_OPEN);
  long openTime = OrderGetInteger(ORDER_TIME_SETUP);
  double lots = OrderGetDouble(ORDER_VOLUME_INITIAL);
  double sl = OrderGetDouble(ORDER_SL);
  double tp = OrderGetDouble(ORDER_TP);
  long expiration = OrderGetInteger(ORDER_TIME_EXPIRATION);
  string comment = OrderGetString(ORDER_COMMENT);
  long closeTime = OrderGetInteger(ORDER_TIME_DONE);
#endif

  if(prefix)
    StringAdd(result, ";");

  StringAdd(result, StringFormat("ticket=%I64u", ticket));
  StringAdd(result, StringFormat("|position=%I64u", position));
  StringAdd(result, StringFormat("|symbol=%s", symbol));
  StringAdd(result, StringFormat("|state=%s", state));
  StringAdd(result, StringFormat("|type=%s", type));
  StringAdd(result, StringFormat("|open_price=%g", openPrice));
  StringAdd(result, StringFormat("|open_time=%f", openTime));
  StringAdd(result, StringFormat("|close_time=%f", closeTime));
  StringAdd(result, StringFormat("|lots=%g", lots));
  StringAdd(result, StringFormat("|sl=%g", sl));
  StringAdd(result, StringFormat("|tp=%g", tp));
  StringAdd(result, StringFormat("|expiration=%f", expiration));
  StringAdd(result, StringFormat("|comment=%s", comment));
  return true;
}

//+------------------------------------------------------------------+
//| HISTORY ORDERS                                                   |
//+------------------------------------------------------------------+
bool MTAccount::getHistoryOrders(string &result, string symbol = "", datetime fromDate = 0, datetime toDate = 0) {
  if(toDate == 0)
    toDate = TimeTradeServer();
  if(fromDate == 0)
    // Default get deals from last 7 days
    fromDate = toDate - PERIOD_D1 * 7;

// Select history to query
  if(!HistorySelect(fromDate, toDate))
    return false;

// Get all orders
  int total = HistoryOrdersTotal();
  if(total == 0)
    return true;

// loop
  for(int i = 0; i < total; i++) {
#ifdef __MQL4__
#endif
#ifdef __MQL5__
    ulong ticket = HistoryOrderGetTicket(i);
    if(ticket <= 0)
      continue;
    if(StringLen(symbol) > 0 && HistoryOrderGetString(ticket, ORDER_SYMBOL) != symbol)
      continue;
#endif

    this.parseHistoryOrder(result, ticket, i > 0);
  }
  return true;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTAccount::getHistoryOrder(string &result, ulong ticket) {
#ifdef __MQL4__
  if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
    return false;
#endif
#ifdef __MQL5__
  if(!HistoryOrderSelect(ticket))
    return false;
#endif

  return this.parseHistoryOrder(result, ticket, false);
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTAccount::parseHistoryOrder(string &result, ulong ticket, bool prefix = true) {
#ifdef __MQL4__
  string symbol = OrderSymbol();
  string type = OperationTypeToString(OrderType());
  double openPrice = OrderOpenPrice();
  long openTime = OrderOpenTime();
  double lots = OrderLots();
  double sl = OrderStopLoss();
  double tp = OrderTakeProfit();
  long expiration = OrderExpiration();
  string comment = OrderComment();
#endif
#ifdef __MQL5__
  ulong position = HistoryOrderGetInteger(ticket, ORDER_POSITION_ID);
  string symbol = HistoryOrderGetString(ticket, ORDER_SYMBOL);
  string state = EnumToString((ENUM_ORDER_STATE)HistoryOrderGetInteger(ticket, ORDER_STATE));
  string type = OperationTypeToString(HistoryOrderGetInteger(ticket, ORDER_TYPE));
  double openPrice = HistoryOrderGetDouble(ticket, ORDER_PRICE_OPEN);
  long openTime = HistoryOrderGetInteger(ticket, ORDER_TIME_SETUP);
  double lots = HistoryOrderGetDouble(ticket, ORDER_VOLUME_INITIAL);
  double sl = HistoryOrderGetDouble(ticket, ORDER_SL);
  double tp = HistoryOrderGetDouble(ticket, ORDER_TP);
  long expiration = HistoryOrderGetInteger(ticket, ORDER_TIME_EXPIRATION);
  string comment = HistoryOrderGetString(ticket, ORDER_COMMENT);
  long closeTime = HistoryOrderGetInteger(ticket, ORDER_TIME_DONE);
#endif

  if(prefix)
    StringAdd(result, ";");

  StringAdd(result, StringFormat("ticket=%I64u", ticket));
  StringAdd(result, StringFormat("|position=%I64u", position));
  StringAdd(result, StringFormat("|symbol=%s", symbol));
  StringAdd(result, StringFormat("|state=%s", state));
  StringAdd(result, StringFormat("|type=%s", type));
  StringAdd(result, StringFormat("|open_price=%g", openPrice));
  StringAdd(result, StringFormat("|open_time=%f", openTime));
  StringAdd(result, StringFormat("|close_time=%f", closeTime));
  StringAdd(result, StringFormat("|lots=%g", lots));
  StringAdd(result, StringFormat("|sl=%g", sl));
  StringAdd(result, StringFormat("|tp=%g", tp));
  StringAdd(result, StringFormat("|expiration=%f", expiration));
  StringAdd(result, StringFormat("|comment=%s", comment));
  return true;
}
//+------------------------------------------------------------------+
//| HISTORY DEALS                                                    |
//+------------------------------------------------------------------+
bool MTAccount::getHistoryDeals(string &result, string symbol = "", datetime fromDate = 0, datetime toDate = 0) {
  if(toDate == 0)
    toDate = TimeTradeServer();
  if(fromDate == 0)
    // Default get deals from last 7 days
    fromDate = toDate - PERIOD_D1 * 7;

// Select history to query
  if(!HistorySelect(fromDate, toDate))
    return false;

// Get all deals
  int total = HistoryDealsTotal();
  if(total == 0)
    return true;

// loop
  for(int i = 0; i < total; i++) {
#ifdef __MQL4__
#endif
#ifdef __MQL5__
    ulong ticket = HistoryDealGetTicket(i);
    if(ticket <= 0)
      continue;
    if(StringLen(symbol) > 0 && HistoryDealGetString(ticket, DEAL_SYMBOL) != symbol)
      continue;
#endif

    this.parseHistoryDeal(result, ticket, i > 0);
  }
  return true;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTAccount::getHistoryDeal(string &result, ulong ticket) {
#ifdef __MQL4__
  if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
    return false;
#endif
#ifdef __MQL5__
  if(!HistoryOrderSelect(ticket))
    return false;
#endif

  return this.parseHistoryDeal(result, ticket, false);
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTAccount::parseHistoryDeal(string &result, ulong ticket, bool prefix = true) {
#ifdef __MQL4__
#endif
#ifdef __MQL5__
  ulong order = HistoryDealGetInteger(ticket, DEAL_ORDER);
  ulong position = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
  string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
  string type = EnumToString((ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE));
  string entry = EnumToString((ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY));
  double price = HistoryDealGetDouble(ticket, DEAL_PRICE);
  long time = HistoryDealGetInteger(ticket, DEAL_TIME);
  double lots = HistoryDealGetDouble(ticket, DEAL_VOLUME);
  double sl = HistoryDealGetDouble(ticket, DEAL_SL);
  double tp = HistoryDealGetDouble(ticket, DEAL_TP);
  double commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
  double swap = HistoryDealGetDouble(ticket, DEAL_SWAP);
  double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
  string comment = HistoryDealGetString(ticket, DEAL_COMMENT);
#endif

  if(prefix)
    StringAdd(result, ";");

  StringAdd(result, StringFormat("ticket=%I64u", ticket));
  StringAdd(result, StringFormat("|order=%I64u", order));
  StringAdd(result, StringFormat("|position=%I64u", position));
  StringAdd(result, StringFormat("|symbol=%s", symbol));
  StringAdd(result, StringFormat("|type=%s", type));
  StringAdd(result, StringFormat("|entry=%s", entry));
  StringAdd(result, StringFormat("|price=%g", price));
  StringAdd(result, StringFormat("|time=%f", time));
  StringAdd(result, StringFormat("|lots=%g", lots));
  StringAdd(result, StringFormat("|sl=%g", sl));
  StringAdd(result, StringFormat("|tp=%g", tp));
  StringAdd(result, StringFormat("|commission=%g", commission));
  StringAdd(result, StringFormat("|swap=%g", swap));
  StringAdd(result, StringFormat("|pnl=%g", profit));
  StringAdd(result, StringFormat("|comment=%s", comment));
  return true;
}

//+------------------------------------------------------------------+
//| TRADES                                                           |
//+------------------------------------------------------------------+
bool MTAccount::getTrades(string &result, string symbol = "") {
#ifdef __MQL4__
  int modes[] = {OP_BUY, OP_SELL};
  return this.getOrders(result, symbol, modes);
#endif
#ifdef __MQL5__
  int total = PositionsTotal();
  if(total == 0)
    return true;

// loop
  for(int i = 0; i < total; i++) {
    if(PositionGetTicket(i) <= 0)
      continue;
    if(StringLen(symbol) > 0 && PositionGetString(POSITION_SYMBOL) != symbol)
      continue;

    this.parseTrade(result, i > 0);
  }

  return true;
#endif
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTAccount::getTrade(string &result, ulong ticket) {
#ifdef __MQL4__
  if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
    return false;
#endif
#ifdef __MQL5__
  if(!PositionSelectByTicket(ticket))
    return false;
#endif
  return this.parseTrade(result, false);
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTAccount::modifyTrade(string &result, ulong ticket, double sl, double tp) {
#ifdef __MQL4__
  double digits = MarketInfo(symbol, MODE_DIGITS);
#endif
#ifdef __MQL5__
  if(!PositionSelectByTicket(ticket))
    return false;

  int digits = (int)SymbolInfoInteger(PositionGetString(POSITION_SYMBOL), SYMBOL_DIGITS);
#endif

  sl = NormalizeDouble(sl, digits);
  tp = NormalizeDouble(tp, digits);

#ifdef __MQL4__
#endif
#ifdef __MQL5__
  return this.m_trade.PositionModify(ticket, sl, tp);
#endif
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTAccount::closeTrade(string &result, ulong ticket) {
#ifdef __MQL4__
  if(!OrderSelect(ticket, SELECT_BY_TICKET))
    return false;
  RefreshRates();

  return OrderClose(ticket, OrderLots(), OrderClosePrice(), this.slippage);
#endif
#ifdef __MQL5__
  return this.m_trade.PositionClose(ticket);
#endif
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTAccount::parseTrade(string &result, bool prefix = true) {
  if(prefix)
    StringAdd(result, ";");

#ifdef __MQL4__
#endif
#ifdef __MQL5__
  StringAdd(result, StringFormat("ticket=%I64u", PositionGetInteger(POSITION_TICKET)));
  StringAdd(result, StringFormat("|symbol=%s", PositionGetString(POSITION_SYMBOL)));
  StringAdd(result, StringFormat("|type=%s", OperationTypeToString(PositionGetInteger(POSITION_TYPE))));
  StringAdd(result, StringFormat("|open_price=%g", PositionGetDouble(POSITION_PRICE_OPEN)));
  StringAdd(result, StringFormat("|open_time=%f", PositionGetInteger(POSITION_TIME)));
  StringAdd(result, StringFormat("|lots=%g", PositionGetDouble(POSITION_VOLUME)));
  StringAdd(result, StringFormat("|sl=%g", PositionGetDouble(POSITION_SL)));
  StringAdd(result, StringFormat("|tp=%g", PositionGetDouble(POSITION_TP)));
  StringAdd(result, StringFormat("|pnl=%g", PositionGetDouble(POSITION_PROFIT)));
  StringAdd(result, StringFormat("|swap=%g", PositionGetDouble(POSITION_SWAP)));
  StringAdd(result, StringFormat("|comment=%s", PositionGetString(POSITION_COMMENT)));
#endif
  return true;
}
//+------------------------------------------------------------------+
