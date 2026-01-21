//+------------------------------------------------------------------+
//|                                     MultiTimeframeHighLow.mq5 |
//|                      Copyright 2023, Your Name (Jules)        |
//|                                      https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, Your Name (Jules)"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property indicator_chart_window
#property indicator_plots 0

//--- Inputs for Daily High/Low
input group "Daily"
input bool ShowDaily = true;
input color DailyColor = clrBlue;
input bool DailyAlerts = true;

//--- Inputs for Weekly High/Low
input group "Weekly"
input bool ShowWeekly = true;
input color WeeklyColor = clrOrange;
input bool WeeklyAlerts = true;

//--- Inputs for Monthly High/Low
input group "Monthly"
input bool ShowMonthly = true;
input color MonthlyColor = clrGreen;
input bool MonthlyAlerts = true;

//--- Inputs for Yearly High/Low
input group "Yearly"
input bool ShowYearly = true;
input color YearlyColor = clrRed;
input bool YearlyAlerts = true;

//--- Global variables to store high and low values
double dailyHigh, dailyLow;
double weeklyHigh, weeklyLow;
double monthlyHigh, monthlyLow;
double yearlyHigh, yearlyLow;

//--- Global variables to track alerted levels
double lastAlertedDailyHigh    = 0;
double lastAlertedDailyLow     = DBL_MAX;
double lastAlertedWeeklyHigh   = 0;
double lastAlertedWeeklyLow    = DBL_MAX;
double lastAlertedMonthlyHigh  = 0;
double lastAlertedMonthlyLow   = DBL_MAX;
double lastAlertedYearlyHigh   = 0;
double lastAlertedYearlyLow    = DBL_MAX;

//--- Global variables to track the bar index of highs/lows
int dailyHighBar, dailyLowBar;
int weeklyHighBar, weeklyLowBar;
int monthlyHighBar, monthlyLowBar;
int yearlyHighBar, yearlyLowBar;


//--- Variables to track the current period
int currentDay = -1;
int currentMonth = -1;
int lastDayOfWeek = 7;
int currentYear = -1;

//--- Forward declarations for helper functions
void PerformInitialScan(const datetime &time[], const double &high[], const double &low[], int rates_total);
void DrawLines(const datetime &time[], int rates_total);
void DrawShortLine(string name, double price, color clr, bool show, const datetime &time[], int rates_total);
void DrawAllMarkers(const datetime &time[]);
void DrawHighMarkerAndLabel(string name, int barIndex, double price, color clr, string text, bool show, const datetime &time[]);
void DrawLowMarkerAndLabel(string name, int barIndex, double price, color clr, string text, bool show, const datetime &time[]);

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- indicator buffers mapping

//---
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
                const long &volume[],
                const int &spread[])
  {
   //--- On the first run, perform a full historical scan. On subsequent runs, process only new bars.
   if(prev_calculated == 0)
     {
      PerformInitialScan(time, high, low, rates_total);
     }
   else
     {
      //--- Process only new bars
      for(int i = prev_calculated - 1; i < rates_total; i++)
        {
         //--- Get time details for the current bar
         MqlDateTime dt;
         TimeToStruct(time[i], dt);

         //--- Check for new day
      if(dt.day_of_year != currentDay || dt.year != currentYear)
        {
         currentDay = dt.day_of_year;
         dailyHigh = high[i];
         dailyLow = low[i];
            dailyHighBar = i;
            dailyLowBar = i;
         lastAlertedDailyHigh = high[i];
         lastAlertedDailyLow = low[i];
        }

      //--- Check for new week (when day of week resets, e.g., Sat -> Sun)
      if(dt.day_of_week < lastDayOfWeek || dt.year != currentYear)
        {
         weeklyHigh = high[i];
         weeklyLow = low[i];
            weeklyHighBar = i;
            weeklyLowBar = i;
         lastAlertedWeeklyHigh = high[i];
         lastAlertedWeeklyLow = low[i];
        }

      //--- Check for new month
      if(dt.mon != currentMonth || dt.year != currentYear)
        {
         currentMonth = dt.mon;
         monthlyHigh = high[i];
         monthlyLow = low[i];
            monthlyHighBar = i;
            monthlyLowBar = i;
         lastAlertedMonthlyHigh = high[i];
         lastAlertedMonthlyLow = low[i];
        }

      //--- Check for new year
      if(dt.year != currentYear)
        {
         currentYear = dt.year;
         yearlyHigh = high[i];
         yearlyLow = low[i];
            yearlyHighBar = i;
            yearlyLowBar = i;
         lastAlertedYearlyHigh = high[i];
         lastAlertedYearlyLow = low[i];
        }

      //--- Update Highs and Lows
      if (high[i] > dailyHigh) { dailyHigh = high[i]; dailyHighBar = i; }
      if (low[i] < dailyLow) { dailyLow = low[i]; dailyLowBar = i; }

      if (high[i] > weeklyHigh) { weeklyHigh = high[i]; weeklyHighBar = i; }
      if (low[i] < weeklyLow) { weeklyLow = low[i]; weeklyLowBar = i; }

      if (high[i] > monthlyHigh) { monthlyHigh = high[i]; monthlyHighBar = i; }
      if (low[i] < monthlyLow) { monthlyLow = low[i]; monthlyLowBar = i; }

      if (high[i] > yearlyHigh) { yearlyHigh = high[i]; yearlyHighBar = i; }
      if (low[i] < yearlyLow) { yearlyLow = low[i]; yearlyLowBar = i; }

      //--- Check for alerts only on the most recent bar
      if(i == rates_total - 1)
        {
         if(DailyAlerts && dailyHigh > lastAlertedDailyHigh) { Alert("New Daily High: " + DoubleToString(dailyHigh, _Digits)); lastAlertedDailyHigh = dailyHigh; }
         if(DailyAlerts && dailyLow < lastAlertedDailyLow) { Alert("New Daily Low: " + DoubleToString(dailyLow, _Digits)); lastAlertedDailyLow = dailyLow; }

         if(WeeklyAlerts && weeklyHigh > lastAlertedWeeklyHigh) { Alert("New Weekly High: " + DoubleToString(weeklyHigh, _Digits)); lastAlertedWeeklyHigh = weeklyHigh; }
         if(WeeklyAlerts && weeklyLow < lastAlertedWeeklyLow) { Alert("New Weekly Low: " + DoubleToString(weeklyLow, _Digits)); lastAlertedWeeklyLow = weeklyLow; }

         if(MonthlyAlerts && monthlyHigh > lastAlertedMonthlyHigh) { Alert("New Monthly High: " + DoubleToString(monthlyHigh, _Digits)); lastAlertedMonthlyHigh = monthlyHigh; }
         if(MonthlyAlerts && monthlyLow < lastAlertedMonthlyLow) { Alert("New Monthly Low: " + DoubleToString(monthlyLow, _Digits)); lastAlertedMonthlyLow = monthlyLow; }

         if(YearlyAlerts && yearlyHigh > lastAlertedYearlyHigh) { Alert("New Yearly High: " + DoubleToString(yearlyHigh, _Digits)); lastAlertedYearlyHigh = yearlyHigh; }
         if(YearlyAlerts && yearlyLow < lastAlertedYearlyLow) { Alert("New Yearly Low: " + DoubleToString(yearlyLow, _Digits)); lastAlertedYearlyLow = yearlyLow; }
        }

      //--- Update the last day of the week for the next iteration
      lastDayOfWeek = dt.day_of_week;
        }
     }
//---

//--- return value of prev_calculated for next call
   //--- Draw the lines on the last bar
   if(rates_total > 0)
     {
      DrawLines(time, rates_total);
      DrawAllMarkers(time);
     }
   return(rates_total);
  }
//+------------------------------------------------------------------+
//| Performs a one-time scan of recent history to find H/L           |
//+------------------------------------------------------------------+
void PerformInitialScan(const datetime &time[], const double &high[], const double &low[], int rates_total)
  {
   //--- Find the first bar of the current year
   MqlDateTime current_dt;
   TimeToStruct(time[rates_total - 1], current_dt);
   int year_start_index = 0;
   for(int i = rates_total - 1; i >= 0; i--)
     {
      MqlDateTime bar_dt;
      TimeToStruct(time[i], bar_dt);
      if(bar_dt.year < current_dt.year)
        {
         year_start_index = i + 1;
         break;
        }
     }

   //--- Initialize states before scanning
   currentDay = -1;
   currentMonth = -1;
   currentYear = -1;
   lastDayOfWeek = 7;

   //--- Scan forward from the start of the year
   for(int i = year_start_index; i < rates_total; i++)
     {
      //--- Get time details for the current bar
      MqlDateTime dt;
      TimeToStruct(time[i], dt);

      //--- Check for new day
      if(dt.day_of_year != currentDay || dt.year != currentYear)
        {
         currentDay = dt.day_of_year;
         dailyHigh = high[i];
         dailyLow = low[i];
         dailyHighBar = i;
         dailyLowBar = i;
        }

      //--- Check for new week (when day of week resets, e.g., Sat -> Sun)
      if(dt.day_of_week < lastDayOfWeek || dt.year != currentYear)
        {
         weeklyHigh = high[i];
         weeklyLow = low[i];
         weeklyHighBar = i;
         weeklyLowBar = i;
        }

      //--- Check for new month
      if(dt.mon != currentMonth || dt.year != currentYear)
        {
         currentMonth = dt.mon;
         monthlyHigh = high[i];
         monthlyLow = low[i];
         monthlyHighBar = i;
         monthlyLowBar = i;
        }

      //--- Check for new year
      if(dt.year != currentYear)
        {
         currentYear = dt.year;
         yearlyHigh = high[i];
         yearlyLow = low[i];
         yearlyHighBar = i;
         yearlyLowBar = i;
        }

      //--- Update Highs and Lows
      if (high[i] > dailyHigh) { dailyHigh = high[i]; dailyHighBar = i; }
      if (low[i] < dailyLow) { dailyLow = low[i]; dailyLowBar = i; }

      if (high[i] > weeklyHigh) { weeklyHigh = high[i]; weeklyHighBar = i; }
      if (low[i] < weeklyLow) { weeklyLow = low[i]; weeklyLowBar = i; }

      if (high[i] > monthlyHigh) { monthlyHigh = high[i]; monthlyHighBar = i; }
      if (low[i] < monthlyLow) { monthlyLow = low[i]; monthlyLowBar = i; }

      if (high[i] > yearlyHigh) { yearlyHigh = high[i]; yearlyHighBar = i; }
      if (low[i] < yearlyLow) { yearlyLow = low[i]; yearlyLowBar = i; }

      //--- Update the last day of the week for the next iteration
      lastDayOfWeek = dt.day_of_week;
     }
  }
//+------------------------------------------------------------------+
//| Helper function to draw short trend lines ("cross style")        |
//+------------------------------------------------------------------+
void DrawShortLine(string name, double price, color clr, bool show, const datetime &time[], int rates_total)
  {
   if(!show)
     {
      ObjectDelete(0, name);
      return;
     }

   // Draw a short line from 10 bars ago to the current bar
   int startIndex = (rates_total > 10) ? rates_total - 10 : 0;
   datetime startTime = time[startIndex];
   datetime endTime = time[rates_total - 1];


   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_TREND, 0, startTime, price, endTime, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
     }
   else
     {
      ObjectMove(0, name, 0, startTime, price);
      ObjectMove(0, name, 1, endTime, price);
     }
  }
//+------------------------------------------------------------------+
//| Function to draw all lines based on settings                     |
//+------------------------------------------------------------------+
void DrawLines(const datetime &time[], int rates_total)
  {
   string chartID = IntegerToString(ChartID());
   DrawShortLine("DH_"+chartID, dailyHigh, DailyColor, ShowDaily, time, rates_total);
   DrawShortLine("DL_"+chartID, dailyLow, DailyColor, ShowDaily, time, rates_total);

   DrawShortLine("WH_"+chartID, weeklyHigh, WeeklyColor, ShowWeekly, time, rates_total);
   DrawShortLine("WL_"+chartID, weeklyLow, WeeklyColor, ShowWeekly, time, rates_total);

   DrawShortLine("MH_"+chartID, monthlyHigh, MonthlyColor, ShowMonthly, time, rates_total);
   DrawShortLine("ML_"+chartID, monthlyLow, MonthlyColor, ShowMonthly, time, rates_total);

   DrawShortLine("YH_"+chartID, yearlyHigh, YearlyColor, ShowYearly, time, rates_total);
   DrawShortLine("YL_"+chartID, yearlyLow, YearlyColor, ShowYearly, time, rates_total);
  }
//+------------------------------------------------------------------+
//| Function to draw all markers based on settings                   |
//+------------------------------------------------------------------+
void DrawHighMarkerAndLabel(string name, int barIndex, double price, color clr, string text, bool show, const datetime &time[])
  {
   if(!show || barIndex < 0)
     {
      ObjectDelete(0, name + "_marker");
      ObjectDelete(0, name + "_label");
      return;
     }

   // Draw the cross marker
   if(ObjectFind(0, name + "_marker") < 0)
     {
      ObjectCreate(0, name + "_marker", OBJ_ARROW, 0, time[barIndex], price);
      ObjectSetInteger(0, name + "_marker", OBJPROP_ARROWCODE, SYMBOL_CROSS);
      ObjectSetInteger(0, name + "_marker", OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name + "_marker", OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name + "_marker", OBJPROP_ANCHOR, ANCHOR_BOTTOM);
     }
   else
     {
      ObjectMove(0, name + "_marker", 0, time[barIndex], price);
     }

   // Draw the text label
   if(ObjectFind(0, name + "_label") < 0)
     {
      ObjectCreate(0, name + "_label", OBJ_TEXT, 0, time[barIndex], price);
      ObjectSetString(0, name + "_label", OBJPROP_TEXT, text + " " + DoubleToString(price, _Digits));
      ObjectSetInteger(0, name + "_label", OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name + "_label", OBJPROP_ANCHOR, ANCHOR_BOTTOM); // Correct anchor for text
      ObjectSetInteger(0, name + "_label", OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, name + "_label", OBJPROP_YDISTANCE, 5); // Shift label up
     }
   else
     {
      ObjectMove(0, name + "_label", 0, time[barIndex], price);
      ObjectSetString(0, name + "_label", OBJPROP_TEXT, text + " " + DoubleToString(price, _Digits));
      ObjectSetInteger(0, name + "_label", OBJPROP_ANCHOR, ANCHOR_BOTTOM);
     }
  }
//+------------------------------------------------------------------+
void DrawLowMarkerAndLabel(string name, int barIndex, double price, color clr, string text, bool show, const datetime &time[])
  {
   if(!show || barIndex < 0)
     {
      ObjectDelete(0, name + "_marker");
      ObjectDelete(0, name + "_label");
      return;
     }

   // Draw the cross marker
   if(ObjectFind(0, name + "_marker") < 0)
     {
      ObjectCreate(0, name + "_marker", OBJ_ARROW, 0, time[barIndex], price);
      ObjectSetInteger(0, name + "_marker", OBJPROP_ARROWCODE, SYMBOL_CROSS);
      ObjectSetInteger(0, name + "_marker", OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name + "_marker", OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name + "_marker", OBJPROP_ANCHOR, ANCHOR_TOP);
     }
   else
     {
      ObjectMove(0, name + "_marker", 0, time[barIndex], price);
     }

   // Draw the text label
   if(ObjectFind(0, name + "_label") < 0)
     {
      ObjectCreate(0, name + "_label", OBJ_TEXT, 0, time[barIndex], price);
      ObjectSetString(0, name + "_label", OBJPROP_TEXT, text + " " + DoubleToString(price, _Digits));
      ObjectSetInteger(0, name + "_label", OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name + "_label", OBJPROP_ANCHOR, ANCHOR_TOP); // Correct anchor for text
      ObjectSetInteger(0, name + "_label", OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, name + "_label", OBJPROP_YDISTANCE, -5); // Shift label down
     }
   else
     {
      ObjectMove(0, name + "_label", 0, time[barIndex], price);
      ObjectSetString(0, name + "_label", OBJPROP_TEXT, text + " " + DoubleToString(price, _Digits));
      ObjectSetInteger(0, name + "_label", OBJPROP_ANCHOR, ANCHOR_TOP);
     }
  }
//+------------------------------------------------------------------+
void DrawAllMarkers(const datetime &time[])
  {
   string chartID = IntegerToString(ChartID());

   // Daily
   DrawHighMarkerAndLabel("DH_"+chartID, dailyHighBar, dailyHigh, DailyColor, "DH:", ShowDaily, time);
   DrawLowMarkerAndLabel("DL_"+chartID, dailyLowBar, dailyLow, DailyColor, "DL:", ShowDaily, time);

   // Weekly
   DrawHighMarkerAndLabel("WH_"+chartID, weeklyHighBar, weeklyHigh, WeeklyColor, "WH:", ShowWeekly, time);
   DrawLowMarkerAndLabel("WL_"+chartID, weeklyLowBar, weeklyLow, WeeklyColor, "WL:", ShowWeekly, time);

   // Monthly
   DrawHighMarkerAndLabel("MH_"+chartID, monthlyHighBar, monthlyHigh, MonthlyColor, "MH:", ShowMonthly, time);
   DrawLowMarkerAndLabel("ML_"+chartID, monthlyLowBar, monthlyLow, MonthlyColor, "ML:", ShowMonthly, time);

   // Yearly
   DrawHighMarkerAndLabel("YH_"+chartID, yearlyHighBar, yearlyHigh, YearlyColor, "YH:", ShowYearly, time);
   DrawLowMarkerAndLabel("YL_"+chartID, yearlyLowBar, yearlyLow, YearlyColor, "YL:", ShowYearly, time);
  }
//+------------------------------------------------------------------+
//| Indicator deinitialization function                              |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   string chartID = IntegerToString(ChartID());
   string prefixes[] = {"DH_", "DL_", "WH_", "WL_", "MH_", "ML_", "YH_", "YL_"};

   for(int i = 0; i < ArraySize(prefixes); i++)
     {
      ObjectDelete(0, prefixes[i] + chartID);
      ObjectDelete(0, prefixes[i] + chartID + "_marker");
      ObjectDelete(0, prefixes[i] + chartID + "_label");
     }
  }
//+------------------------------------------------------------------+
