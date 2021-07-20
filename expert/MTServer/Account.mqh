//+------------------------------------------------------------------+
//|                                                      ProjectName |
//|                                      Copyright 2018, CompanyName |
//|                                       http://www.companyname.net |
//+------------------------------------------------------------------+
#include  "Helper.mqh"
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class MTAccount
  {
private:
   int               magic;
   int               slippage;

   bool              parseTrade(string &result);

public:
   void              MTAccount();
   bool              getFund(string &result);
   bool              getTrades(string symbol, int mode, string &result);
   bool              getTradeByTicket(int ticket, string &result);
   int               openOrder(string symbol, int type, double lots, double price, double sl, double tp, string comment, string &result);
   bool              modifyOrder(int ticket, double price, double sl, double tp, datetime expiration, string &result);
   bool              closePartialOrder(int ticket, double lots, double price, string &result);
   bool              closeOrder(int ticket, string &result);
  };

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTAccount::MTAccount()
  {
   this.magic = 112233;
   this.slippage = 3;
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
bool MTAccount::getTrades(string symbol, int mode, string &result)
  {
   int total = OrdersTotal();
   if(total == 0)
      return true;

// loop
   for(int i = 0; i < total; i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(StringLen(symbol) > 0 && OrderSymbol() != symbol)
         continue;
      if(OrderType() != mode)
         continue;

      this.parseTrade(result);
     }

   if(total > 0)
     {
      result = StringSubstr(result, 0, StringLen(result)-1);
     }
   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTAccount::getTradeByTicket(int ticket, string &result)
  {
   if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
      return false;
   this.parseTrade(result);
   result = StringSubstr(result, 0, StringLen(result)-1);
   return true;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MTAccount::parseTrade(string &result)
  {
// TICKET|SYMBOL|TYPE|PRICE|LOT|TIME|SL|TP|PNL|COMMISSION|SWAP|COMMENT
   return StringAdd(result, StringFormat("%d|%s|%s|%g|%g|%s|%g|%g|%g|%g|%g;",
                                         OrderTicket(),
                                         OrderSymbol(),
                                         OperationTypeToString(OrderType()),
                                         OrderOpenPrice(),
                                         OrderLots(),
                                         TimeToString(OrderOpenTime()),
                                         OrderStopLoss(),
                                         OrderTakeProfit(),
                                         OrderProfit(),
                                         OrderCommission(),
                                         OrderSwap(),
                                         OrderComment()
                                        ));

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
