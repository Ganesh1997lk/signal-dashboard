//+------------------------------------------------------------------+
//|              Custom Indicator for MetaTrader 5                     |
//|               Trend, Signals, and High/Low Levels                |
//|                 Translated from TradingView Pine Script          |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property indicator_chart_window

#property indicator_buffers 7
#property indicator_plots   3

//--- Indicator Plots
//--- plot Trend Line (Color Changing)
#property indicator_label1  "Trend Line"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_style1  STYLE_SOLID
#property indicator_width1  3

//--- plot Buy Signal Arrow
#property indicator_label2  "Buy Signal"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrGreen
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

//--- plot Sell Signal Arrow
#property indicator_label3  "Sell Signal"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrRed
#property indicator_style3  STYLE_SOLID
#property indicator_width3  2

//--- Global variables for High/Low tracking
double periodHigh = 0;
double periodLow = 0;
datetime periodTime = 0;

//--- Indicator buffers
double TrendLineBuffer[];
double TrendLineColorBuffer[]; // Buffer for trend line color
double BuySignalBuffer[];
double SellSignalBuffer[];
double RsiBuffer[];
double UpBuffer[];
double DownBuffer[];

//--- Enumeration for timeframe selection
enum ENUM_TIMEFRAMES
  {
   DAILY,   // Daily
   WEEKLY,  // Weekly
   MONTHLY, // Monthly
   YEARLY   // Yearly
  };

//--- Input parameters
input int RsiPeriod = 84;                                // MajorTrend RSI Period
input int SmaPeriod = 80;                                // Trend Line SMA Period
input ENUM_TIMEFRAMES HighLowTimeframe = DAILY;          // High/Low Timeframe
input bool EnableRsiBuyAlert = true;                     // Enable RSI Buy Alert
input bool EnableRsiSellAlert = true;                    // Enable RSI Sell Alert
input bool EnableNewHighAlert = true;                    // Enable New High Alert
input bool EnableNewLowAlert = true;                     // Enable New Low Alert

//+------------------------------------------------------------------+
//| Indicator initialization function                                |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- Set TrendLine buffer with color
   SetIndexBuffer(0, TrendLineBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, TrendLineColorBuffer, INDICATOR_COLOR_INDEX);
   PlotIndexSetString(0, PLOT_LABEL, "Trend Line");
   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, SmaPeriod);
   // Define 4 colors for the line
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 0, clrLime);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 1, clrRed);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 2, clrYellow);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 3, clrGray);

//--- Set BuySignal buffer
   SetIndexBuffer(2, BuySignalBuffer, INDICATOR_DATA);
   PlotIndexSetInteger(2, PLOT_ARROW, 233);
   PlotIndexSetString(2, PLOT_LABEL, "Buy Signal");

//--- Set SellSignal buffer
   SetIndexBuffer(3, SellSignalBuffer, INDICATOR_DATA);
   PlotIndexSetInteger(3, PLOT_ARROW, 234);
   PlotIndexSetString(3, PLOT_LABEL, "Sell Signal");

//--- Calculation buffers
   SetIndexBuffer(4, RsiBuffer, INDICATOR_CALCULATIONS);
   SetIndexBuffer(5, UpBuffer, INDICATOR_CALCULATIONS);
   SetIndexBuffer(6, DownBuffer, INDICATOR_CALCULATIONS);

//--- Set empty values
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Check if a new period has started                                |
//+------------------------------------------------------------------+
bool IsNewPeriod(datetime newTime)
  {
   if(periodTime == 0) return true;

   MqlDateTime new_time_struct, old_time_struct;
   TimeToStruct(newTime, new_time_struct);
   TimeToStruct(periodTime, old_time_struct);

   // This logic handles year transitions correctly for all cases
   if(new_time_struct.year != old_time_struct.year) return true;

   switch(HighLowTimeframe)
     {
      case DAILY:
         return(new_time_struct.day_of_year != old_time_struct.day_of_year);
      case WEEKLY:
         // A new week starts when the day of the week resets (e.g., from 6 (Saturday) to 0 (Sunday))
         return(new_time_struct.day_of_week < old_time_struct.day_of_week);
      case MONTHLY:
         return(new_time_struct.mon != old_time_struct.mon);
      case YEARLY: // This case is already handled by the year check above
         return false;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Custom RSI Calculation (Wilder's smoothing)                      |
//+------------------------------------------------------------------+
void CalculateRSI(const int rates_total, const int prev_calculated, const double &price[], double &up[], double &down[], double &rsi[])
  {
   int start;
   if(prev_calculated == 0)
     {
      start = 1;
      up[0] = 0;
      down[0] = 0;
     }
   else
     {
      start = prev_calculated - 1;
     }

   for(int i = start; i < rates_total; i++)
     {
      double change = price[i] - price[i - 1];
      double up_val = (change > 0) ? change : 0;
      double down_val = (change < 0) ? -change : 0;

      // Wilder's Smoothing (RMA)
      up[i] = (up[i - 1] * (RsiPeriod - 1) + up_val) / RsiPeriod;
      down[i] = (down[i - 1] * (RsiPeriod - 1) + down_val) / RsiPeriod;

      if(down[i] == 0)
         rsi[i] = 100;
      else
        {
         double rs = up[i] / down[i];
         rsi[i] = 100 - (100 / (1 + rs));
        }
     }
  }

//+------------------------------------------------------------------+
//| Indicator calculation function                                   |
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
                const int &spread[])
  {
   int start = (prev_calculated > 0) ? prev_calculated - 1 : 0;

//--- Calculate indicators
   CalculateRSI(rates_total, prev_calculated, close, UpBuffer, DownBuffer, RsiBuffer);

   double sma_values[];
   ArrayResize(sma_values, rates_total);
   bool sma_is_ready = (SimpleMA(SmaPeriod, 0, rates_total, close, sma_values) >= SmaPeriod);

//--- Main loop for indicator logic
   for(int i = start; i < rates_total; i++)
     {
      //--- High/Low Logic (always runs)
      bool is_new_period = IsNewPeriod(time[i]);
      bool new_high_formed = false;
      bool new_low_formed = false;

      if(is_new_period)
        {
         periodHigh = high[i];
         periodLow = low[i];
         periodTime = time[i];
        }
      else
        {
         if(high[i] > periodHigh)
           {
            periodHigh = high[i];
            new_high_formed = true;
           }
         if(low[i] < periodLow)
           {
            periodLow = low[i];
            new_low_formed = true;
           }
        }

      //--- Logic that depends on SMA buffer being ready
      if(sma_is_ready)
        {
         //--- Set empty values for signals by default
         BuySignalBuffer[i] = EMPTY_VALUE;
         SellSignalBuffer[i] = EMPTY_VALUE;

         //--- Trend Line
         TrendLineBuffer[i] = sma_values[i];

         //--- Set Trend Line Color based on RSI
         if(RsiBuffer[i] > 50.5)
            TrendLineColorBuffer[i] = 0; // Lime
         else if(RsiBuffer[i] < 49.5)
            TrendLineColorBuffer[i] = 1; // Red
         else if(RsiBuffer[i] == 50)
            TrendLineColorBuffer[i] = 3; // Gray
         else
            TrendLineColorBuffer[i] = 2; // Yellow

         //--- Buy/Sell Signal Logic
         double mup = 50.5;
         double mdo = 49.5;

         if(i > 0) // Need previous bar to check for crossover
           {
            bool buy_signal = RsiBuffer[i] > mup && RsiBuffer[i - 1] <= mup;
            bool sell_signal = RsiBuffer[i] < mdo && RsiBuffer[i - 1] >= mdo;

            if(buy_signal)
              {
               BuySignalBuffer[i] = low[i] - _Point * 10;
              }
            if(sell_signal)
              {
               SellSignalBuffer[i] = high[i] + _Point * 10;
              }

            //--- Alerts (only for the most recent, unconfirmed bar)
            if(i == rates_total - 1)
              {
               if(EnableRsiBuyAlert && buy_signal)
                  Alert(_Symbol, " - RSI Buy Signal");
               if(EnableRsiSellAlert && sell_signal)
                  Alert(_Symbol, " - RSI Sell Signal");
               if(EnableNewHighAlert && new_high_formed)
                  Alert(_Symbol, " - New Period High: ", DoubleToString(periodHigh, _Digits));
               if(EnableNewLowAlert && new_low_formed)
                  Alert(_Symbol, " - New Period Low: ", DoubleToString(periodLow, _Digits));
              }
           }
        }
      else
        {
         //--- Set empty values if SMA is not ready
         TrendLineBuffer[i] = EMPTY_VALUE;
         BuySignalBuffer[i] = EMPTY_VALUE;
         SellSignalBuffer[i] = EMPTY_VALUE;
        }
     }

//--- Drawing High/Low Lines (runs only once per tick)
   string high_line_name = "PeriodHighLine_" + IntegerToString(ChartID());
   string low_line_name = "PeriodLowLine_" + IntegerToString(ChartID());

   if(periodHigh > 0 && periodLow > 0) // Don't draw if not initialized
     {
      //--- High Line
      if(ObjectFind(ChartID(), high_line_name) < 0)
        {
         ObjectCreate(ChartID(), high_line_name, OBJ_HLINE, 0, 0, periodHigh);
         ObjectSetInteger(ChartID(), high_line_name, OBJPROP_COLOR, clrBlue);
         ObjectSetInteger(ChartID(), high_line_name, OBJPROP_STYLE, STYLE_DASHDOT);
         ObjectSetInteger(ChartID(), high_line_name, OBJPROP_WIDTH, 1);
         ObjectSetInteger(ChartID(), high_line_name, OBJPROP_BACK, true);
        }
      else
        {
         ObjectSetDouble(ChartID(), high_line_name, OBJPROP_PRICE, periodHigh);
        }

      //--- Low Line
      if(ObjectFind(ChartID(), low_line_name) < 0)
        {
         ObjectCreate(ChartID(), low_line_name, OBJ_HLINE, 0, 0, periodLow);
         ObjectSetInteger(ChartID(), low_line_name, OBJPROP_COLOR, clrBlue);
         ObjectSetInteger(ChartID(), low_line_name, OBJPROP_STYLE, STYLE_DASHDOT);
         ObjectSetInteger(ChartID(), low_line_name, OBJPROP_WIDTH, 1);
         ObjectSetInteger(ChartID(), low_line_name, OBJPROP_BACK, true);
        }
      else
        {
         ObjectSetDouble(ChartID(), low_line_name, OBJPROP_PRICE, periodLow);
        }
     }

//--- return value of prev_calculated for next call
   return(rates_total);
  }
//+------------------------------------------------------------------+
//| Indicator deinitialization function                              |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   string high_line_name = "PeriodHighLine_" + IntegerToString(ChartID());
   string low_line_name = "PeriodLowLine_" + IntegerToString(ChartID());
   ObjectDelete(ChartID(), high_line_name);
   ObjectDelete(ChartID(), low_line_name);
  }
//+------------------------------------------------------------------+
