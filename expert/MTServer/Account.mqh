//+------------------------------------------------------------------+
//|                                                      ProjectName |
//|                                      Copyright 2018, CompanyName |
//|                                       http://www.companyname.net |
//+------------------------------------------------------------------+
#include  "Helper.mqh"


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
   int               magic;
   int               slippage;
   datetime          orderEventCheckTime;

   bool              parseOrder(string &result);

public:
   void              MTAccount();
   bool              getFund(string &result);
   bool              getOrders(string symbol, int &modes[], string &result);
   bool              getOrderByTicket(int ticket, string &result);
   int               openOrder(string symbol, int type, double lots, double price, double sl, double tp, string comment, string &result);
   bool              modifyOrder(int ticket, double price, double sl, double tp, datetime expiration, string &result);
   bool              closePartialOrder(int ticket, double lots, double price, string &result);
   bool              closeOrder(int ticket, string &result);

   int               getNewOrdersEvents(string &result);
   bool              getOrderEventByTicket(int ticket, ENUM_ORDER_EVENTS event, string &result);
   bool              parseSelectedOrderEvent(ENUM_ORDER_EVENTS event, string &result);
  };

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTAccount::MTAccount()
  {
   this.magic = 112233;
   this.slippage = 3;

   this.orderEventCheckTime = TimeCurrent();
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTAccount::getFund(string &result)
  {
   StringAdd(result, StringFormat("%g|%g", AccountBalance(), AccountEquity()));
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
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(StringLen(symbol) > 0 && OrderSymbol() != symbol)
         continue;
      if(ArraySize(modes) > 0 && !ArrayExist(modes, OrderType()))
         continue;

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
bool MTAccount::getOrderByTicket(int ticket, string &result)
  {
   if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
      return false;
   this.parseOrder(result);
   result = StringSubstr(result, 0, StringLen(result)-1);
   return true;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTAccount::parseOrder(string &result)
  {
// TICKET|SYMBOL|TYPE|OPEN_PRICE|LOT|OPEN_TIME|SL|TP|PNL|COMMISSION|SWAP|COMMENT|CLOSE_PRICE|CLOSE_TIME
   return StringAdd(result, StringFormat("%d|%s|%s|%g|%s|%g|%g|%g|%g|%g|%g|%s|%g|%s;",
                                         OrderTicket(),
                                         OrderSymbol(),
                                         OperationTypeToString(OrderType()),
                                         OrderOpenPrice(),
                                         TimeToString(OrderOpenTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                                         OrderLots(),
                                         OrderStopLoss(),
                                         OrderTakeProfit(),
                                         OrderProfit(),
                                         OrderCommission(),
                                         OrderSwap(),
                                         OrderComment(),
                                         OrderClosePrice(),
                                         TimeToString(OrderCloseTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS)
                                        ));

  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int MTAccount::getNewOrdersEvents(string &result)
  {
   int total = OrdersHistoryTotal();
   int size = 0;
   for(int i = total - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
         break;
      if(OrderCloseTime() != 0 && OrderCloseTime() < this.orderEventCheckTime)
         break;
      if(OrderOpenTime() < this.orderEventCheckTime)
         break;

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
bool MTAccount::getOrderEventByTicket(int ticket, ENUM_ORDER_EVENTS event, string &result)
  {
   if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
      return false;
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
int MTAccount::openOrder(string symbol, int type, double lots, double price, double sl, double tp, string comment, string &result)
  {
   price = NormalizeDouble(price, Digits());
   sl = NormalizeDouble(sl, Digits());
   tp = NormalizeDouble(tp, Digits());

   return OrderSend(symbol, type, lots, price, this.slippage, sl, tp, comment, this.magic);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTAccount::modifyOrder(int ticket, double price, double sl, double tp, datetime expiration, string &result)
  {
   price = NormalizeDouble(price, Digits());
   sl = NormalizeDouble(sl, Digits());
   tp = NormalizeDouble(tp, Digits());

   return OrderModify(ticket, price, sl, tp, expiration, 0);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTAccount::closePartialOrder(int ticket, double lots, double price, string &result)
  {
   RefreshRates();
   price = NormalizeDouble(price, Digits());
   return OrderClose(ticket, lots, price, this.slippage);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTAccount::closeOrder(int ticket, string &result)
  {
   return this.closePartialOrder(ticket, 0, 0, result);
  }
//+------------------------------------------------------------------+
