//+------------------------------------------------------------------+
//|                                                      ProjectName |
//|                                      Copyright 2018, CompanyName |
//|                                       http://www.companyname.net |
//+------------------------------------------------------------------+
#include  "Helper.mqh"

#ifdef __MQL5__
#include <Trade\Trade.mqh>
#endif

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class MTAccount
  {
private:
#ifdef __MQL4__
   int               magic;
   int               slippage;
#endif
#ifdef __MQL5__
   CTrade            trade;
#endif
   datetime          orderEventCheckTime;

   bool              parseOrder(string &result);

public:
   void              MTAccount(ulong magic, int deviation);
   bool              getFund(string &result);
   // Order
   bool              getOrders(string symbol, int &modes[], string &result);
   bool              getOrder(ulong ticket, string &result);
   ulong             openOrder(string symbol, int type, double lots, double price, double sl, double tp, string comment, string &result);
   bool              modifyOrder(ulong ticket, double price, double sl, double tp, datetime expiration, string &result);
   bool              cancelOrder(ulong ticket, string &result);

   // History order
   bool              getHistoryOrder(ulong ticket, string &result);
   bool              parseHistoryOrder(ulong ticket, string &result);
   int               checkHistoryOrders(string &result);

   // Trade
   bool              getTrades(string symbol, string &result);
   bool              getTrade(ulong ticket, string &result);
   bool              closeTrade(ulong ticket, string &result);
   bool              parseTrade(string &result);
  };

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTAccount::MTAccount(ulong magic, int deviation)
  {
#ifdef __MQL4__
   this.magic = magic;
   this.slippage = deviation;
#endif
#ifdef __MQL5__
   this.trade.SetExpertMagicNumber(magic);
   this.trade.SetDeviationInPoints(deviation);
#endif

   this.orderEventCheckTime = TimeCurrent();
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTAccount::getFund(string &result)
  {
#ifdef __MQL4__
   string info = StringFormat("%g|%g", AccountBalance(), AccountEquity());
#endif
   string info = StringFormat("%g|%g", AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY));
#ifdef __MQL5__

#endif
   StringAdd(result, info);
   return true;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTAccount::getOrders(string symbol, int &modes[], string &result)
  {
   int total = OrdersTotal();
   if(total == 0)
      return true;

// loop
   bool hasData = false;
   for(int i = 0; i < total; i++)
     {
#ifdef __MQL4__
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(StringLen(symbol) > 0 && OrderSymbol() != symbol)
         continue;
      if(ArraySize(modes) > 0 && !ArrayExist(modes, OrderType()))
         continue;
#endif
#ifdef __MQL5__
      if(OrderGetTicket(i) <= 0)
         continue;
      if(StringLen(symbol) > 0 && OrderGetString(ORDER_SYMBOL) != symbol)
         continue;
      if(ArraySize(modes) > 0 && !ArrayExist(modes, (int)OrderGetInteger(ORDER_TYPE)))
         continue;
#endif

      this.parseOrder(result);
      hasData = true;
     }

   if(hasData)
     {
      result = StringSubstr(result, 0, StringLen(result)-1);
     }
   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTAccount::getOrder(ulong ticket, string &result)
  {
#ifdef __MQL4__
   if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
      return false;
#endif
#ifdef __MQL5__
   if(!OrderSelect(ticket))
      return false;
#endif

   this.parseOrder(result);
   result = StringSubstr(result, 0, StringLen(result)-1);
   return true;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTAccount::parseOrder(string &result)
  {
// TICKET|SYMBOL|TYPE|OPEN_PRICE|OPEN_TIME|LOT|SL|TP|PNL|COMMISSION|SWAP|EXPIRATION|COMMENT|CLOSE_PRICE|CLOSE_TIME
#ifdef __MQL4__
   ulong ticket = OrderTicket();
   string symbol = OrderSymbol();
   string type = OperationTypeToString(OrderType());
   double openPrice = OrderOpenPrice();
   long openTime = OrderOpenTime();
   double lots = OrderLots();
   double sl = OrderStopLoss();
   double tp = OrderTakeProfit();
   double closePrice = OrderClosePrice();
   double closeTime= OrderCloseTime();
   long expiration= OrderExpiration();
   string comment= OrderComment();
#endif
#ifdef __MQL5__
   ulong ticket = OrderGetInteger(ORDER_TICKET);
   string symbol = OrderGetString(ORDER_SYMBOL);
   string type = OperationTypeToString(OrderGetInteger(ORDER_TYPE));
   double openPrice = OrderGetDouble(ORDER_PRICE_OPEN);
   long openTime = OrderGetInteger(ORDER_TIME_SETUP);
   double lots = OrderGetDouble(ORDER_VOLUME_INITIAL);
   double sl = OrderGetDouble(ORDER_SL);
   double tp = OrderGetDouble(ORDER_TP);
   long expiration= OrderGetInteger(ORDER_TIME_EXPIRATION);
   string comment= OrderGetString(ORDER_COMMENT);
   double closePrice = 0;
   long closeTime= 0;
#endif

   StringAdd(result, StringFormat("ticket=%d", ticket));
   StringAdd(result, StringFormat("|symbol=%s", symbol));
   StringAdd(result, StringFormat("|type=%s", type));
   StringAdd(result, StringFormat("|open_price=%g", openPrice));
   StringAdd(result, StringFormat("|open_time=%f", openTime));
   StringAdd(result, StringFormat("|lots=%g", lots));
   StringAdd(result, StringFormat("|sl=%g", sl));
   StringAdd(result, StringFormat("|tp=%g", tp));
   StringAdd(result, StringFormat("|expiration=%f", expiration));
   StringAdd(result, StringFormat("|comment=%s", comment));
   StringAdd(result, StringFormat("|close_price=%g", closePrice));
   StringAdd(result, StringFormat("|close_time=%f", closeTime));
   return StringAdd(result, ";");
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
/*
int MTAccount::checkHistoryOrders(string &result)
  {
#ifdef __MQL4__
   int total = OrdersHistoryTotal();
#endif
#ifdef __MQL5__
   int total = HistoryOrdersTotal();
#endif

   int size = 0;
   for(int i = total - 1; i >= 0; i--)
     {

#ifdef __MQL4__
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
         break;
      if(OrderCloseTime() != 0 && OrderCloseTime() < this.orderEventCheckTime)
         break;
      if(OrderOpenTime() < this.orderEventCheckTime)
         break;
#endif
#ifdef __MQL5__
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket <= 0)
         break;
      if(HistoryOrderGetInteger(ticket, ORDER_TIME_DONE) != 0 && HistoryOrderGetInteger(ticket, ORDER_TIME_DONE) < this.orderEventCheckTime)
         break;
      if(HistoryOrderGetInteger(ticket, ORDER_TIME_SETUP) < this.orderEventCheckTime)
         break;
#endif

      size++;
      this.parseOrder(result);
     }
   this.orderEventCheckTime = TimeCurrent();

   if(size > 0)
     {
      result = StringSubstr(result, 0, StringLen(result)-1);
     }
   return size;
  }
*/
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
ulong MTAccount::openOrder(string symbol, int type, double lots, double price, double sl, double tp, string comment, string &result)
  {
   price = NormalizeDouble(price, Digits());
   sl = NormalizeDouble(sl, Digits());
   tp = NormalizeDouble(tp, Digits());

#ifdef __MQL4__
   return OrderSend(symbol, type, lots, price, this.slippage, sl, tp, comment, this.magic);
#endif
#ifdef __MQL5__
   bool ok;
   switch(type)
     {
      case ORDER_TYPE_BUY:
      case ORDER_TYPE_SELL:
         ok = this.trade.PositionOpen(symbol, (ENUM_ORDER_TYPE)type, lots, price, sl, tp, comment);
         break;
      default:
         ok = this.trade.OrderOpen(symbol, (ENUM_ORDER_TYPE)type, lots, NULL, price, sl, tp, ORDER_TIME_GTC, 0, comment);
         break;
     }

   if(ok)
      return this.trade.ResultOrder();
   return 0;
#endif
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTAccount::modifyOrder(ulong ticket, double price, double sl, double tp, datetime expiration, string &result)
  {
   price = NormalizeDouble(price, Digits());
   sl = NormalizeDouble(sl, Digits());
   tp = NormalizeDouble(tp, Digits());

#ifdef __MQL4__
   return OrderModify(ticket, price, sl, tp, expiration);
#endif
#ifdef __MQL5__
   return this.trade.OrderModify(ticket, price, sl, tp, ORDER_TIME_GTC, expiration);
#endif
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTAccount::cancelOrder(ulong ticket, string &result)
  {
#ifdef __MQL4__
   return OrderDelete(ticket);
#endif
#ifdef __MQL5__
   return this.trade.OrderDelete(ticket);
#endif
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTAccount::getHistoryOrder(ulong ticket, string &result)
  {
#ifdef __MQL4__
   if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
      return false;
#endif
#ifdef __MQL5__
   if(!HistoryOrderSelect(ticket))
      return false;
#endif

   this.parseHistoryOrder(ticket, result);
   result = StringSubstr(result, 0, StringLen(result)-1);
   return true;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTAccount::parseHistoryOrder(ulong ticket, string &result)
  {
#ifdef __MQL4__
   string symbol = OrderSymbol();
   string type = OperationTypeToString(OrderType());
   double openPrice = OrderOpenPrice();
   long openTime = OrderOpenTime();
   double lots = OrderLots();
   double sl = OrderStopLoss();
   double tp = OrderTakeProfit();
   double closePrice = OrderClosePrice();
   double closeTime= OrderCloseTime();
   long expiration= OrderExpiration();
   string comment= OrderComment();
#endif
#ifdef __MQL5__
   string symbol = HistoryOrderGetString(ticket, ORDER_SYMBOL);
   string type = OperationTypeToString(HistoryOrderGetInteger(ticket, ORDER_TYPE));
   double openPrice = HistoryOrderGetDouble(ticket, ORDER_PRICE_OPEN);
   long openTime = HistoryOrderGetInteger(ticket, ORDER_TIME_SETUP);
   double lots = HistoryOrderGetDouble(ticket, ORDER_VOLUME_INITIAL);
   double sl = HistoryOrderGetDouble(ticket, ORDER_SL);
   double tp = HistoryOrderGetDouble(ticket, ORDER_TP);
   long expiration= HistoryOrderGetInteger(ticket, ORDER_TIME_EXPIRATION);
   string comment= HistoryOrderGetString(ticket, ORDER_COMMENT);
   double closePrice = 0;
   long closeTime= 0;
#endif

   StringAdd(result, StringFormat("ticket=%d", ticket));
   StringAdd(result, StringFormat("|symbol=%s", symbol));
   StringAdd(result, StringFormat("|type=%s", type));
   StringAdd(result, StringFormat("|open_price=%g", openPrice));
   StringAdd(result, StringFormat("|open_time=%f", openTime));
   StringAdd(result, StringFormat("|lots=%g", lots));
   StringAdd(result, StringFormat("|sl=%g", sl));
   StringAdd(result, StringFormat("|tp=%g", tp));
   StringAdd(result, StringFormat("|expiration=%f", expiration));
   StringAdd(result, StringFormat("|comment=%s", comment));
   StringAdd(result, StringFormat("|close_price=%g", closePrice));
   StringAdd(result, StringFormat("|close_time=%f", closeTime));
   return StringAdd(result, ";");
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
/*
bool MTAccount::closePartialTrade(ulong ticket, double lots, double price, string &result)
  {
   price = NormalizeDouble(price, Digits());

#ifdef __MQL4__
   return OrderClose(ticket, lots, price, this.slippage);
#endif
#ifdef __MQL5__
   return this.trade.PositionClosePartial(ticket, lots);
#endif
  }
*/

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTAccount::getTrades(string symbol,string &result)
  {
#ifdef __MQL4__
   int modes[] = {OP_BUY, OP_SELL};
   return this.getOrders(symbol, modes, result);
#endif
#ifdef __MQL5__
   int total = PositionsTotal();
   if(total == 0)
      return true;

// loop
   bool hasData = false;
   for(int i = 0; i < total; i++)
     {
      if("" == PositionGetSymbol(i))
         continue;
      if(StringLen(symbol) > 0 && PositionGetString(POSITION_SYMBOL) != symbol)
         continue;

      this.parseTrade(result);
      hasData = true;
     }

   if(hasData)
     {
      result = StringSubstr(result, 0, StringLen(result)-1);
     }
   return true;
#endif

  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTAccount::getTrade(ulong ticket, string &result)
  {
#ifdef __MQL4__
   if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
      return false;
#endif
#ifdef __MQL5__
   if(!PositionSelectByTicket(ticket))
      return false;
#endif

   this.parseTrade(result);
   result = StringSubstr(result, 0, StringLen(result)-1);
   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTAccount::closeTrade(ulong ticket, string &result)
  {
#ifdef __MQL4__
   if(!OrderSelect(ticket, SELECT_BY_TICKET))
      return false;
   RefreshRates();

   return OrderClose(ticket, OrderLots(), OrderClosePrice(), this.slippage);
#endif
#ifdef __MQL5__
   return this.trade.PositionClose(ticket);
#endif
  }


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTAccount::parseTrade(string &result)
  {
#ifdef __MQL5__
   StringAdd(result, StringFormat("ticket=%d", PositionGetInteger(POSITION_TICKET)));
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
   StringAdd(result, StringFormat("|current_price=%f", PositionGetDouble(POSITION_PRICE_CURRENT)));
#endif
   return StringAdd(result, ";");
  }
//+------------------------------------------------------------------+
