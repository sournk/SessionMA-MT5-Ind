#property copyright   "Denis Kislitsyn"
#property link        "https://kislitsyn.me/peronal/algo"
#property description "Session MA Indictor"
#property description "The MA is calculated only on bars that are inside the session."
#property description "The indicator is useful for trading sessions and for making calculations over long periods."
#property version     "1.00"
#property icon        "img\\logo\\logo_64.ico"

#property strict

#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   1

#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_width1  1


input uint                    InpMAPeriod                    = 14;           // MA Period
input uint                    InpMAShift                     = 0;            // MA Shift
input ENUM_MA_METHOD          InpMAMethod                    = MODE_SMA;     // MA Method
input ENUM_APPLIED_PRICE      InpAppliedPrice                = PRICE_CLOSE;  // Applied Price
input uint                    InpSessionStartHour            = 10;           // Session Start Hour (0-23)
input uint                    InpSessionStartMin             = 0;            // Session Start Min (0-59)
input uint                    InpSessionEndHour              = 18;           // Session End Hour (0-23)
input uint                    InpSessionEndMin               = 0;            // Session End Min (0-59)
input bool                    InpSessionIntradayOnly         = false;        // Session Only Intraday

double   maBuffer[];
double   session_prices[];
int      session_last_idx;
datetime session_last_dt;

//+------------------------------------------------------------------+
//| MAMethod to strinf
//+------------------------------------------------------------------+
string MaMethodToString(const ENUM_MA_METHOD _method) {
  string str = EnumToString(_method);
  StringReplace(str, "MODE_", "");
  return str;
}

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()  {
  if(InpMAPeriod <= 0) {
    Print("'MA Period' must be possitive");
    return(INIT_PARAMETERS_INCORRECT);
  }

  session_last_idx = -1;
  session_last_dt = 0;
  SetIndexBuffer(0, maBuffer, INDICATOR_DATA);
  PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);
  IndicatorSetString(INDICATOR_SHORTNAME, 
                     StringFormat("Session %s(%d,%d)", 
                                  MaMethodToString(InpMAMethod), InpMAPeriod, InpMAShift));
  return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Check time is valid
//+------------------------------------------------------------------+
bool IsTimeValid(const datetime _dt) {
  MqlDateTime dt;
  TimeToStruct(_dt, dt);
  int current_minutes = dt.hour * 60 + dt.min;
  
  int session_start = (int)InpSessionStartHour * 60 + (int)InpSessionStartMin;
  int session_end   = (int)InpSessionEndHour   * 60 + (int)InpSessionEndMin;
  
  if(session_start <= session_end) 
    return current_minutes >= session_start && current_minutes < session_end;
    
  return false;
}

//+------------------------------------------------------------------+
//| Возвращает true, если два datetime относятся к одному дню       |
//+------------------------------------------------------------------+
bool IsSameDay(datetime dt1, datetime dt2) {
  MqlDateTime t1, t2;
  TimeToStruct(dt1, t1);
  TimeToStruct(dt2, t2);
  
  return (t1.year == t2.year &&
         t1.mon  == t2.mon &&
       t1.day  == t2.day);
}

//+------------------------------------------------------------------+
//| Add price to session slice arr
//+------------------------------------------------------------------+
void AddPriceToSession(const int _idx,
                       const datetime &_t[],
                       const double &_o[],
                       const double &_h[],
                       const double &_l[],
                       const double &_c[]) {

  int _ma_idx = _idx - (int)InpMAShift;
  if(_ma_idx < 0) return;
  if(!IsTimeValid(_t[_ma_idx])) return;

  // 01. Clear session slice if it's a new date
  // InpSessionIntradayOnly==true: Remove all other day slice pos
  if(InpSessionIntradayOnly) 
    if(!IsSameDay(session_last_dt, _t[_idx])) 
      ArrayFree(session_prices);
  
  // 02. Save new price
  double price = GetPrice(InpAppliedPrice, _o[_ma_idx], _h[_ma_idx], _l[_ma_idx], _c[_ma_idx]);
  // _idx is a new bar => append is to session slice
  if(_ma_idx > session_last_idx)
    ArrayResize(session_prices, ArraySize(session_prices)+1);

  // Save price to the last pos of session slice
  session_prices[ArraySize(session_prices)-1] = price;
  
  // Remove prices from the head when slice len is more than MAPeriod
  while(ArraySize(session_prices) > (int)InpMAPeriod) 
    ArrayRemove(session_prices, 0, 1);
    
  // Save last bar idx and dt
  session_last_idx = _idx;
  session_last_dt = _t[_idx];
}


//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[]) {

  int start = MathMax(prev_calculated-1, 0);
  for(int i=start; i<rates_total; i++) {
    maBuffer[i] = 0.0;
    if(!IsTimeValid(time[i])) continue;
    
    AddPriceToSession(i, time, open, high, low, close);
    maBuffer[i] = CalcMAArray(session_prices, InpMAMethod);
  }

  return(rates_total);
}

//+------------------------------------------------------------------+
//| Возвращает цену по выбранному типу                              |
//+------------------------------------------------------------------+
double GetPrice(ENUM_APPLIED_PRICE price_type, double open, double high, double low, double close) {
  switch(price_type) {
  case PRICE_CLOSE:
    return(close);
  case PRICE_OPEN:
    return(open);
  case PRICE_HIGH:
    return(high);
  case PRICE_LOW:
    return(low);
  case PRICE_MEDIAN:
    return((high + low) / 2.0);
  case PRICE_TYPICAL:
    return((high + low + close) / 3.0);
  case PRICE_WEIGHTED:
    return((high + low + close + close) / 4.0);
  }
  return(close);
}

//+------------------------------------------------------------------+
//| Calculate MA for a given array
//+------------------------------------------------------------------+
double CalcMAArray(const double &src[], ENUM_MA_METHOD method) {
  int start = 0;
  int cnt = ArraySize(src);
  if(cnt <= 0) return 0.0;
  int end = cnt-1;  

  if(method == MODE_SMA){
    double sum = 0.0;
    for(int i=start; i<=end; i++) 
      sum += src[i];
    return (cnt>0) ? sum/cnt : 0.0;
  }
  
  if(method == MODE_EMA) {
    double k = 2.0 / (cnt+1);
    double ema = src[start]; // start from the oldest
    for(int i=start+1; i<=end; i++)
      ema = src[i]*k + ema*(1.0-k);
    return ema;
  }
  
  if(method == MODE_SMMA) {
    double sum1 = 0;
    for(int i=start; i<=end; i++)
      sum1 += src[i];
    double smma = sum1 / cnt;
    for(int i=start+1; i<=end; i++) 
      smma = (smma * (cnt - 1) + src[i]) / cnt;
    return smma;
  }
  
  if(method == MODE_LWMA) {
    double sum = 0.0, weight_sum = 0.0;
    for(int i=start; i<=end; i++) {
      int weight = i-start+1;
      sum += src[i]*weight;
      weight_sum += weight;
    }
    return (weight_sum > 0) ? (sum / weight_sum) : 0.0;
  }
  
  return 0.0;
}
