//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string GetTimeframeText(ENUM_TIMEFRAMES tf)
  {
// Standard timeframes
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
         return "UNKNOWN";
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES GetTimeframe(string tf)
  {
   if(tf == "M1")
      return  PERIOD_M1;
   if(tf == "M5")
      return  PERIOD_M5;
   if(tf == "M15")
      return  PERIOD_M15;
   if(tf == "M30")
      return  PERIOD_M30;
   if(tf == "H1")
      return  PERIOD_H1;
   if(tf == "H4")
      return  PERIOD_H4;
   if(tf == "D1")
      return  PERIOD_D1;
   if(tf == "W1")
      return  PERIOD_W1;
   if(tf == "MN1")
      return  PERIOD_MN1;

   return -1;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
template<typename T>
T StringToEnum(string str,T enu)
  {
   for(int i=0; i<256; i++)
      if(EnumToString(enu=(T)i)==str)
         return(enu);

   return(-1);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
template <typename T>
void ArrayRemove(T& A[], T value)
  {
   bool isShiftOn = false;
   for(int i=0; i < ArraySize(A) - 1; i++)
     {
      if(A[i] == value)
        {
         isShiftOn = true;
        }
      if(isShiftOn == true)
        {
         A[i] = A[i + 1];
        }
     }
   ArrayResize(A, ArraySize(A) - 1);
  }
//+------------------------------------------------------------------+
