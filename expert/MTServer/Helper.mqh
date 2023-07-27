//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int StringToOperationType(string type) {
#ifdef __MQL4__
  if (type == "BUY_MARKET")
    return OP_BUY;
  if (type == "SELL_MARKET")
    return OP_SELL;
  if (type == "BUY_LIMIT")
    return OP_BUYLIMIT;
  if (type == "SELL_LIMIT")
    return OP_SELLLIMIT;
  if (type == "BUY_STOP")
    return OP_BUYSTOP;
  if (type == "SELL_STOP")
    return OP_SELLSTOP;
#endif
#ifdef __MQL5__
  if (type == "BUY_MARKET")
    // Can using for position because ORDER_TYPE_BUY == POSITION_TYPE_BUY
    return ORDER_TYPE_BUY;
  if (type == "SELL_MARKET")
    // Can using for position because ORDER_TYPE_SELL == POSITION_TYPE_SELL
    return ORDER_TYPE_SELL;
  if (type == "BUY_LIMIT")
    return ORDER_TYPE_BUY_LIMIT;
  if (type == "SELL_LIMIT")
    return ORDER_TYPE_SELL_LIMIT;
  if (type == "BUY_STOP")
    return ORDER_TYPE_BUY_STOP;
  if (type == "SELL_STOP")
    return ORDER_TYPE_SELL_STOP;
#endif

  PrintFormat("Cannot parse operation type %s", type);
  return -1;
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string OperationTypeToString(long type) {
#ifdef __MQL4__
  if (type == OP_BUY)
    return "BUY_MARKET";
  if (type == OP_SELL)
    return "SELL_MARKET";
  if (type == OP_BUYLIMIT)
    return "BUY_LIMIT";
  if (type == OP_SELLLIMIT)
    return "SELL_LIMIT";
  if (type == OP_BUYSTOP)
    return "BUY_STOP";
  if (type == OP_SELLSTOP)
    return "SELL_STOP";
#endif
#ifdef __MQL5__
// Can using for position because ORDER_TYPE_BUY == POSITION_TYPE_BUY
  if (type == ORDER_TYPE_BUY)
    return "BUY_MARKET";
// Can using for position because ORDER_TYPE_SELL == POSITION_TYPE_SELL
  if (type == ORDER_TYPE_SELL)
    return "SELL_MARKET";
  if (type == ORDER_TYPE_BUY_LIMIT)
    return "BUY_LIMIT";
  if (type == ORDER_TYPE_SELL_LIMIT)
    return "SELL_LIMIT";
  if (type == ORDER_TYPE_BUY_STOP)
    return "BUY_STOP";
  if (type == ORDER_TYPE_SELL_STOP)
    return "SELL_STOP";
#endif

  PrintFormat("Operation type %s parse faile", type);
  return "UNKNOWN";
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string GetTimeframeText(ENUM_TIMEFRAMES tf) {
  return StringSubstr(EnumToString(tf), 7);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES GetTimeframe(string tf) {
  if (tf == "M1")
    return PERIOD_M1;
  if (tf == "M2")
    return PERIOD_M2;
  if (tf == "M3")
    return PERIOD_M3;
  if (tf == "M4")
    return PERIOD_M4;
  if (tf == "M5")
    return PERIOD_M5;
  if (tf == "M6")
    return PERIOD_M6;
  if (tf == "M10")
    return PERIOD_M10;
  if (tf == "M12")
    return PERIOD_M12;
  if (tf == "M15")
    return PERIOD_M15;
  if (tf == "M20")
    return PERIOD_M20;
  if (tf == "M30")
    return PERIOD_M30;
  if (tf == "H1")
    return PERIOD_H1;
  if (tf == "H2")
    return PERIOD_H2;
  if (tf == "H4")
    return PERIOD_H4;
  if (tf == "H6")
    return PERIOD_H6;
  if (tf == "H8")
    return PERIOD_H8;
  if (tf == "D1")
    return PERIOD_D1;
  if (tf == "W1")
    return PERIOD_W1;
  if (tf == "MN1")
    return PERIOD_MN1;

  PrintFormat("[ERROR] Cannot parse timeframe %s", tf);
  return -1;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
template <typename T>
T StringToEnum(string str, T enu) {
  for (int i = 0; i < 256; i++)
    if (EnumToString(enu = (T)i) == str)
      return (enu);

  return (-1);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
template <typename T>
void ArrayRemove(T &A[], T value) {
  int size = ArraySize(A);
  bool isShift = false;
  for (int i = 0; i < size; i++) {
    if (A[i] == value) {
      isShift = true;
    }
    if (isShift == true && i + 1 < size) {
      A[i] = A[i + 1];
    }
  }
  if (isShift)
    ArrayResize(A, size - 1);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
template <typename T>
T ArrayExist(T &list[], T element) {
  for (int i = ArraySize(list) - 1; i >= 0; i--)
    if (list[i] == element)
      return true;

  return false;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
datetime TimestampToTime(string timestamp) {
  return TimestampToTime(StringToDouble(timestamp));
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
datetime TimestampToTime(double timestamp) {
  return (datetime)timestamp + TimeGMTOffset();
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
datetime TimestampToGMTTime(string timestamp) {
  return TimestampToGMTTime(StringToDouble(timestamp));
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
datetime TimestampToGMTTime(double timestamp) {
  return (datetime)timestamp;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MarketIsOpen(string symbol) {
  MqlDateTime time;
  datetime now = TimeCurrent();
  TimeToStruct(now, time);

  uint nowSeconds = (time.hour * 3600) + (time.min * 60) + time.sec;

  datetime from, to;
  uint session = 0;
  while (SymbolInfoSessionTrade(symbol, (ENUM_DAY_OF_WEEK)time.day_of_week, session, from, to)) {
    if (from < nowSeconds && nowSeconds < to)
      return true;
    session++;
  }

  ResetLastError();
  return false;
}
//+------------------------------------------------------------------+
