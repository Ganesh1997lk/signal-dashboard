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
double lastAlertedDailyLow     = 1000000;
double lastAlertedWeeklyHigh   = 0;
double lastAlertedWeeklyLow    = 1000000;
double lastAlertedMonthlyHigh  = 0;
double lastAlertedMonthlyLow   = 1000000;
double lastAlertedYearlyHigh   = 0;
double lastAlertedYearlyLow    = 1000000;


//--- Variables to track the current period
int currentDay = -1;
int currentMonth = -1;
int lastDayOfWeek = 7;
int currentYear = -1;

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
   //--- Determine the starting bar for calculation
   int start = prev_calculated > 1 ? prev_calculated - 1 : 0;

//--- Loop through each bar that needs calculation
   for(int i = start; i < rates_total; i++)
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
         lastAlertedDailyHigh = high[i];
         lastAlertedDailyLow = low[i];
        }

      //--- Check for new week (when day of week resets, e.g., Sat -> Sun)
      if(dt.day_of_week < lastDayOfWeek || dt.year != currentYear)
        {
         weeklyHigh = high[i];
         weeklyLow = low[i];
         lastAlertedWeeklyHigh = high[i];
         lastAlertedWeeklyLow = low[i];
        }

      //--- Check for new month
      if(dt.mon != currentMonth || dt.year != currentYear)
        {
         currentMonth = dt.mon;
         monthlyHigh = high[i];
         monthlyLow = low[i];
         lastAlertedMonthlyHigh = high[i];
         lastAlertedMonthlyLow = low[i];
        }

      //--- Check for new year
      if(dt.year != currentYear)
        {
         currentYear = dt.year;
         yearlyHigh = high[i];
         yearlyLow = low[i];
         lastAlertedYearlyHigh = high[i];
         lastAlertedYearlyLow = low[i];
        }

      //--- Update Highs and Lows
      if (high[i] > dailyHigh) dailyHigh = high[i];
      if (low[i] < dailyLow) dailyLow = low[i];

      if (high[i] > weeklyHigh) weeklyHigh = high[i];
      if (low[i] < weeklyLow) weeklyLow = low[i];

      if (high[i] > monthlyHigh) monthlyHigh = high[i];
      if (low[i] < monthlyLow) monthlyLow = low[i];

      if (high[i] > yearlyHigh) yearlyHigh = high[i];
      if (low[i] < yearlyLow) yearlyLow = low[i];

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
//---

//--- return value of prev_calculated for next call
   //--- Draw the lines on the last bar
   if(rates_total > 0)
     {
      DrawLines();
     }
   return(rates_total);
  }
//+------------------------------------------------------------------+
//| Helper function to draw horizontal lines                         |
//+------------------------------------------------------------------+
void DrawLine(string name, double price, color clr, bool show)
  {
   if(!show)
     {
      ObjectDelete(0, name);
      return;
     }

   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
     }
   else
     {
      ObjectMove(0, name, 0, 0, price);
     }
  }
//+------------------------------------------------------------------+
//| Function to draw all lines based on settings                     |
//+------------------------------------------------------------------+
void DrawLines()
  {
   string chartID = IntegerToString(ChartID());
   DrawLine("DH_"+chartID, dailyHigh, DailyColor, ShowDaily);
   DrawLine("DL_"+chartID, dailyLow, DailyColor, ShowDaily);

   DrawLine("WH_"+chartID, weeklyHigh, WeeklyColor, ShowWeekly);
   DrawLine("WL_"+chartID, weeklyLow, WeeklyColor, ShowWeekly);

   DrawLine("MH_"+chartID, monthlyHigh, MonthlyColor, ShowMonthly);
   DrawLine("ML_"+chartID, monthlyLow, MonthlyColor, ShowMonthly);

   DrawLine("YH_"+chartID, yearlyHigh, YearlyColor, ShowYearly);
   DrawLine("YL_"+chartID, yearlyLow, YearlyColor, ShowYearly);
  }
//+------------------------------------------------------------------+
//| Indicator deinitialization function                              |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   string chartID = IntegerToString(ChartID());
   ObjectDelete(0, "DH_"+chartID);
   ObjectDelete(0, "DL_"+chartID);
   ObjectDelete(0, "WH_"+chartID);
   ObjectDelete(0, "WL_"+chartID);
   ObjectDelete(0, "MH_"+chartID);
   ObjectDelete(0, "ML_"+chartID);
   ObjectDelete(0, "YH_"+chartID);
   ObjectDelete(0, "YL_"+chartID);
  }
//+------------------------------------------------------------------+
