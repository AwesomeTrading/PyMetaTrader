//+------------------------------------------------------------------+
//|                                                      ProjectName |
//|                                      Copyright 2018, CompanyName |
//|                                       http://www.companyname.net |
//+------------------------------------------------------------------+
#include  "Helper.mqh"

#ifdef __MQL5__
#include <Trade\Trade.mqh>
#endif

enum ENUM_ORDER_EVENTS
  {
   EVENT_ORDER_OPENED,
   EVENT_ORDER_MODIFIED,
   EVENT_ORDER_COMPLETED,
   EVENT_ORDER_CANCELED,
   EVENT_ORDER_EXPIRED,
  };
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string OrderEventToString(ENUM_ORDER_EVENTS event)
  {
   switch(event)
     {
      case EVENT_ORDER_OPENED:
         return "ORDER_OPENED";
      case EVENT_ORDER_MODIFIED:
         return "ORDER_MODIFIED";
      case EVENT_ORDER_COMPLETED:
         return "ORDER_COMPLETED";
      case EVENT_ORDER_CANCELED:
         return "ORDER_CANCELED";
      case EVENT_ORDER_EXPIRED:
         return "ORDER_EXPIRED";
      default:
         return "UNKNOWN";
     }
  }
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
   bool              getOrderByTicket(ulong ticket, string &result);
   ulong             openOrder(string symbol, int type, double lots, double price, double sl, double tp, string comment, string &result);
   bool              modifyOrder(ulong ticket, double price, double sl, double tp, datetime expiration, string &result);
   bool              closePartialOrder(ulong ticket, double lots, double price, string &result);
   bool              closeOrder(ulong ticket, string &result);
   bool              cancelOrder(ulong ticket, string &result);

   int               getNewOrdersEvents(string &result);
   bool              getOrderEventByTicket(ulong ticket, ENUM_ORDER_EVENTS event, string &result);
   bool              parseSelectedOrderEvent(ENUM_ORDER_EVENTS event, string &result);

   // Position
   bool              getPositions(string symbol, string &result);
   bool              parsePosition(string &result);
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
bool MTAccount::getOrderByTicket(ulong ticket, string &result)
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
   string order = StringFormat("%d|%s|%s|%g|%f|%g|%g|%g|%g|%g|%g|%f|%s|%g|%f;",
                               OrderTicket(),
                               OrderSymbol(),
                               OperationTypeToString(OrderType()),
                               OrderOpenPrice(),
                               OrderOpenTime(),
                               OrderLots(),
                               OrderStopLoss(),
                               OrderTakeProfit(),
                               OrderProfit(),
                               OrderCommission(),
                               OrderSwap(),
                               OrderExpiration(),
                               OrderComment(),
                               OrderClosePrice(),
                               OrderCloseTime()
                              );
#endif
#ifdef __MQL5__
   string order = StringFormat("%d|%s|%s|%g|%f|%g|%g|%g|%g|%g|%g|%f|%s|%g|%f;",
                               OrderGetInteger(ORDER_TICKET),
                               OrderGetString(ORDER_SYMBOL),
                               OperationTypeToString(OrderGetInteger(ORDER_TYPE)),
                               OrderGetDouble(ORDER_PRICE_OPEN),
                               OrderGetInteger(ORDER_TYPE_TIME),
                               OrderGetDouble(ORDER_VOLUME_INITIAL),
                               OrderGetDouble(ORDER_SL),
                               OrderGetDouble(ORDER_TP),
                               0.0,
                               0.0,
                               0.0,
                               OrderGetInteger(ORDER_TIME_EXPIRATION),
                               OrderGetString(ORDER_COMMENT),
                               OrderGetDouble(ORDER_PRICE_CURRENT),
                               0.0
                              );
#endif
   return StringAdd(result, order);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int MTAccount::getNewOrdersEvents(string &result)
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
      if(!HistoryOrderSelect(i))
         break;
      if(OrderGetInteger(ORDER_TIME_DONE) != 0 && OrderGetInteger(ORDER_TIME_DONE) < this.orderEventCheckTime)
         break;
      if(OrderGetInteger(ORDER_TIME_SETUP) < this.orderEventCheckTime)
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

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTAccount::getOrderEventByTicket(ulong ticket, ENUM_ORDER_EVENTS event, string &result)
  {
#ifdef __MQL4__
   if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
      return false;
#endif
#ifdef __MQL5__
   if(!OrderSelect(ticket))
      return false;
#endif
   return this.parseSelectedOrderEvent(event, result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTAccount::parseSelectedOrderEvent(ENUM_ORDER_EVENTS event, string &result)
  {
   StringAdd(result, StringFormat("%s|", OrderEventToString(event)));
   this.parseOrder(result);
   result = StringSubstr(result, 0, StringLen(result)-1);
   return true;
  }
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
bool MTAccount::closePartialOrder(ulong ticket, double lots, double price, string &result)
  {
   price = NormalizeDouble(price, Digits());

#ifdef __MQL4__
   return OrderClose(ticket, lots, price, this.slippage);
#endif
#ifdef __MQL5__
   return this.trade.PositionClosePartial(ticket, lots);
#endif
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTAccount::closeOrder(ulong ticket, string &result)
  {
#ifdef __MQL4__
   if(!OrderSelect(ticket, SELECT_BY_TICKET))
      return false;
   RefreshRates();

   return this.closePartialOrder(ticket, OrderLots(), OrderClosePrice(), result);
#endif
#ifdef __MQL5__
   if(!OrderSelect(ticket))
      return false;

   return this.trade.PositionClose(ticket);
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
bool MTAccount::getPositions(string symbol,string &result)
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
      if("" != PositionGetSymbol(i))
         continue;
      if(StringLen(symbol) > 0 && PositionGetString(POSITION_SYMBOL) != symbol)
         continue;

      this.parsePosition(result);
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
bool MTAccount::parsePosition(string &result)
  {
// TICKET|SYMBOL|TYPE|OPEN_PRICE|OPEN_TIME|LOT|SL|TP|PNL|COMMISSION|SWAP|EXPIRATION|COMMENT|CLOSE_PRICE|CLOSE_TIME

#ifdef __MQL5__
   string order = StringFormat("%d|%s|%s|%g|%f|%g|%g|%g|%g|%g|%g|%f|%s|%g|%f;",
                               PositionGetInteger(POSITION_TICKET),
                               PositionGetString(POSITION_SYMBOL),
                               OperationTypeToString(PositionGetInteger(POSITION_TYPE)),
                               PositionGetDouble(POSITION_PRICE_OPEN),
                               PositionGetInteger(POSITION_TIME),
                               PositionGetDouble(POSITION_VOLUME),
                               PositionGetDouble(POSITION_SL),
                               PositionGetDouble(POSITION_TP),
                               PositionGetDouble(POSITION_PROFIT),
                               0.0,
                               PositionGetDouble(POSITION_SWAP),
                               0,
                               PositionGetString(POSITION_COMMENT),
                               PositionGetDouble(POSITION_PRICE_CURRENT),
                               0.0
                              );
#endif
   return StringAdd(result, order);
  }
//+------------------------------------------------------------------+
