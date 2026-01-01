//+------------------------------------------------------------------+
//|                                                 SmoothedMACD.mq5 |
//|                        Copyright 2023, Your Name, All Rights Reserved |
//|                                      https://www.yourwebsite.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, Your Name, All Rights Reserved"
#property link      "https://www.yourwebsite.com"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots   4

//--- Indicator Buffers
double MACD_Line_Buffer[];
double Signal_Line_Buffer[];
double Smooth_Signal_Line_Buffer[];
double Histogram_Buffer[];
double Color_Buffer[];

//--- Indicator Plots
#property indicator_label1  "MACD Line"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

#property indicator_label2  "Signal Line"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrRed
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1

#property indicator_label3  "Smooth Signal"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrRed
#property indicator_style3  STYLE_DASH
#property indicator_width3  1

#property indicator_label4  "Histogram"
#property indicator_type4   DRAW_COLOR_HISTOGRAM
#property indicator_color4  clrGreen,clrRed
#property indicator_style4  STYLE_SOLID
#property indicator_width4  2

//--- Input Parameters
input int InpFastEMA = 12;           // Fast EMA Period
input int InpSlowEMA = 26;           // Slow EMA Period
input int InpSignalEMA = 9;            // Signal EMA Period
input int InpSmoothSignalEMA = 5;    // Smooth Signal EMA Period (Visual Only)

//--- Handles
int h_FastEMA;
int h_SlowEMA;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- indicator buffers mapping
   SetIndexBuffer(0, MACD_Line_Buffer, INDICATOR_DATA);
   SetIndexBuffer(1, Signal_Line_Buffer, INDICATOR_DATA);
   SetIndexBuffer(2, Smooth_Signal_Line_Buffer, INDICATOR_DATA);
   SetIndexBuffer(3, Histogram_Buffer, INDICATOR_DATA);
   SetIndexBuffer(4, Color_Buffer, INDICATOR_COLOR_INDEX);

//--- Set plot empty values
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);

//--- Set plot labels
   PlotIndexSetString(0, PLOT_LABEL, "MACD(" + string(InpFastEMA) + "," + string(InpSlowEMA) + ")");
   PlotIndexSetString(1, PLOT_LABEL, "Signal(" + string(InpSignalEMA) + ")");
   PlotIndexSetString(2, PLOT_LABEL, "Smooth(" + string(InpSmoothSignalEMA) + ")");
   PlotIndexSetString(3, PLOT_LABEL, "Histogram");

//--- Set plot draw begin
   int drawBegin = InpSlowEMA + InpSignalEMA;
   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, drawBegin);
   PlotIndexSetInteger(1, PLOT_DRAW_BEGIN, drawBegin);
   PlotIndexSetInteger(2, PLOT_DRAW_BEGIN, drawBegin + InpSmoothSignalEMA);
   PlotIndexSetInteger(3, PLOT_DRAW_BEGIN, drawBegin);

//--- Get indicator handles
   h_FastEMA = iMA(_Symbol, _Period, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   h_SlowEMA = iMA(_Symbol, _Period, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);

   if(h_FastEMA == INVALID_HANDLE || h_SlowEMA == INVALID_HANDLE)
     {
      Print("Failed to create indicator handles. Error: ", GetLastError());
      return(INIT_FAILED);
     }

//--- We are drawing on the main chart window
   IndicatorSetString(INDICATOR_SHORTNAME, "SmoothedMACD");
   return(INIT_SUCCEEDED);
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
                const long &real_volume[],
                const int &spread[])
  {
//--- Check for minimal rates
   if(rates_total < InpSlowEMA)
      return(0);

//--- Buffers for EMA values
   double fast_ema_buffer[];
   double slow_ema_buffer[];

   ArrayResize(fast_ema_buffer, rates_total);
   ArrayResize(slow_ema_buffer, rates_total);

//--- Copy EMA values from handles
   if(CopyBuffer(h_FastEMA, 0, 0, rates_total, fast_ema_buffer) <= 0)
     {
      Print("Failed to copy Fast EMA buffer. Error: ", GetLastError());
      return(0);
     }
   if(CopyBuffer(h_SlowEMA, 0, 0, rates_total, slow_ema_buffer) <= 0)
     {
      Print("Failed to copy Slow EMA buffer. Error: ", GetLastError());
      return(0);
     }

//--- Determine the start bar for calculation
   int limit;
   if(prev_calculated == 0)
      limit = 0;
   else
      limit = prev_calculated - 1;

//--- EMA calculation multipliers
   double signal_pr = 2.0 / (InpSignalEMA + 1);
   double smooth_pr = 2.0 / (InpSmoothSignalEMA + 1);

//--- Main calculation loop
   for(int i = limit; i < rates_total; i++)
     {
      // Calculate MACD Line
      MACD_Line_Buffer[i] = fast_ema_buffer[i] - slow_ema_buffer[i];
     }

   //--- Calculate Signal Line and Smooth Signal Line using iMAOnArray for cleaner code
   SimpleMAOnBuffer(0, rates_total, InpSignalEMA, MODE_EMA, MACD_Line_Buffer, Signal_Line_Buffer);
   SimpleMAOnBuffer(0, rates_total, InpSmoothSignalEMA, MODE_EMA, Signal_Line_Buffer, Smooth_Signal_Line_Buffer);

   //--- Calculate Histogram and set colors
   for(int i = limit; i < rates_total; i++)
     {
      Histogram_Buffer[i] = MACD_Line_Buffer[i] - Signal_Line_Buffer[i];
      Color_Buffer[i] = (Histogram_Buffer[i] > 0) ? 0 : 1;
     }

   return(rates_total);
  }
//+------------------------------------------------------------------+
//|  Calculates a Moving Average on a given buffer                   |
//+------------------------------------------------------------------+
void SimpleMAOnBuffer(int start_pos, int rates_total, int period, ENUM_MA_METHOD method, const double &source[], double &dest[])
  {
   if(rates_total < period) return;

   int handle = iMAOnArray(source, rates_total, period, 0, method, 0);
   if(handle != INVALID_HANDLE)
     {
      CopyBuffer(handle, 0, start_pos, rates_total, dest);
      IndicatorRelease(handle);
     }
  }
//+------------------------------------------------------------------+
