//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int StringToOperationType(string type)
  {
#ifdef __MQL4__
   if(type == "BUY_MARKET")
      return OP_BUY;
   if(type == "SELL_MARKET")
      return OP_SELL;
   if(type == "BUY_LIMIT")
      return OP_BUYLIMIT;
   if(type == "SELL_LIMIT")
      return OP_SELLLIMIT;
   if(type == "BUY_STOP")
      return OP_BUYSTOP;
   if(type == "SELL_STOP")
      return OP_SELLSTOP;
#endif
#ifdef __MQL5__
   if(type == "BUY_MARKET")
      // Can using for position because ORDER_TYPE_BUY == POSITION_TYPE_BUY
      return ORDER_TYPE_BUY;
   if(type == "SELL_MARKET")
      // Can using for position because ORDER_TYPE_SELL == POSITION_TYPE_SELL
      return ORDER_TYPE_SELL;
   if(type == "BUY_LIMIT")
      return ORDER_TYPE_BUY_LIMIT;
   if(type == "SELL_LIMIT")
      return ORDER_TYPE_SELL_LIMIT;
   if(type == "BUY_STOP")
      return ORDER_TYPE_BUY_STOP;
   if(type == "SELL_STOP")
      return ORDER_TYPE_SELL_STOP;
#endif

   PrintFormat("Cannot parse operation type %s", type);
   return -1;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string OperationTypeToString(long type)
  {
#ifdef __MQL4__
   if(type == OP_BUY)
      return "BUY_MARKET";
   if(type == OP_SELL)
      return "SELL_MARKET";
   if(type == OP_BUYLIMIT)
      return "BUY_LIMIT";
   if(type == OP_SELLLIMIT)
      return "SELL_LIMIT";
   if(type == OP_BUYSTOP)
      return "BUY_STOP";
   if(type == OP_SELLSTOP)
      return "SELL_STOP";
#endif
#ifdef __MQL5__
// Can using for position because ORDER_TYPE_BUY == POSITION_TYPE_BUY
   if(type == ORDER_TYPE_BUY)
      return "BUY_MARKET";
// Can using for position because ORDER_TYPE_SELL == POSITION_TYPE_SELL
   if(type == ORDER_TYPE_SELL)
      return "SELL_MARKET";
   if(type == ORDER_TYPE_BUY_LIMIT)
      return "BUY_LIMIT";
   if(type == ORDER_TYPE_SELL_LIMIT)
      return "SELL_LIMIT";
   if(type == ORDER_TYPE_BUY_STOP)
      return "BUY_STOP";
   if(type == ORDER_TYPE_SELL_STOP)
      return "SELL_STOP";
#endif

   PrintFormat("Operation type %s parse faile", type);
   return "UNKNOWN";
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string GetTimeframeText(ENUM_TIMEFRAMES tf)
  {
   switch(tf)
     {
      case PERIOD_M1:
         return "M1";
      case PERIOD_M5:
         return "M5";
      case PERIOD_M15:
         return "M15";
      case PERIOD_M30:
         return "M30";
      case PERIOD_H1:
         return "H1";
      case PERIOD_H4:
         return "H4";
      case PERIOD_D1:
         return "D1";
      case PERIOD_W1:
         return "W1";
      case PERIOD_MN1:
         return "MN1";
      default:
         PrintFormat("Timeframe %s parse faile", EnumToString(tf));
         return "UNKNOWN";
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES GetTimeframe(string tf)
  {
   if(tf == "M1")
      return PERIOD_M1;
   if(tf == "M5")
      return PERIOD_M5;
   if(tf == "M15")
      return PERIOD_M15;
   if(tf == "M30")
      return PERIOD_M30;
   if(tf == "H1")
      return PERIOD_H1;
   if(tf == "H4")
      return PERIOD_H4;
   if(tf == "D1")
      return PERIOD_D1;
   if(tf == "W1")
      return PERIOD_W1;
   if(tf == "MN1")
      return PERIOD_MN1;

   PrintFormat("[ERROR] Cannot parse timeframe %s", tf);
   return -1;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
template <typename T>
T StringToEnum(string str, T enu)
  {
   for(int i = 0; i < 256; i++)
      if(EnumToString(enu = (T)i) == str)
         return (enu);

   return (-1);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
template <typename T>
void ArrayRemove(T &A[], T value)
  {
   int size = ArraySize(A);
   bool isShift = false;
   for(int i = 0; i < size; i++)
     {
      if(A[i] == value)
        {
         isShift = true;
        }
      if(isShift == true && i + 1 < size)
        {
         A[i] = A[i + 1];
        }
     }
   if(isShift)
      ArrayResize(A, size - 1);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
template <typename T>
T ArrayExist(T &list[], T element)
  {
   for(int i = ArraySize(list) - 1; i >= 0; i--)
      if(list[i] == element)
         return true;

   return false;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
datetime TimestampToTime(string timestamp)
  {
   return TimestampToTime(StringToDouble(timestamp));
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
datetime TimestampToTime(double timestamp)
  {
   return (datetime)timestamp + TimeGMTOffset();
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
datetime TimestampToGMTTime(string timestamp)
  {
   return TimestampToGMTTime(StringToDouble(timestamp));
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
datetime TimestampToGMTTime(double timestamp)
  {
   return (datetime)timestamp;
  }
//+------------------------------------------------------------------+
