//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class MTAccount
  {

public:
   void              MTAccount();
   bool              getFund(string &result);
   bool              getTrades(string symbol, int mode, string &result);
  };

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MTAccount::MTAccount()
  {
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
      if(!OrderSelect(i,SELECT_BY_POS, MODE_TRADES))
         continue;
      if(StringLen(symbol) > 0 && OrderSymbol() != symbol)
         continue;
      if(OrderType() != mode)
         continue;

      // TICKET|SYMBOL|TYPE|PRICE|LOT|TIME|SL|TP|PNL|COMMISSION|SWAP|COMMENT
      StringAdd(result, StringFormat("%d|%s|%s|%g|%g|%s|%g|%g|%g|%g|%g;",
                                     OrderTicket(),
                                     OrderSymbol(),
                                     OrderType(),
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

   result = StringSubstr(result, 0, StringLen(result)-1);
   return true;
  }
//+------------------------------------------------------------------+
