//+------------------------------------------------------------------+
//|                                                 MACDTraderEA.mq5 |
//|                        Copyright 2023, Your Name, All Rights Reserved |
//|                                      https://www.yourwebsite.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, Your Name, All Rights Reserved"
#property link      "https://www.yourwebsite.com"
#property version   "1.00"
#property description "An EA based on a smoothed MACD system with alerts and auto-trading."

#include <Trade\Trade.mqh>

//--- Enums for User Input Options
enum ENUM_LOT_SIZE_METHOD
{
   LOT_SIZE_FIXED,      // Fixed Lot Size
   LOT_SIZE_PERCENTAGE  // Percentage of Account Balance
};

enum ENUM_SL_BUFFER_METHOD
{
   FIXED_POINTS,    // Fixed points for SL buffer
   ATR_MULTIPLIER   // ATR multiplier for SL buffer
};

enum ENUM_VOLATILITY_FILTER_METHOD
{
   VOL_NONE,                // No volatility filter
   ATR_MIN_THRESHOLD,       // Minimum ATR value in points
   ATR_ABOVE_ATR_MA         // ATR must be above its MA
};

//--- EA Input Parameters
//--- MACD Settings
sgroup "MACD Indicator Settings"
input int InpFastEMA = 12;            // Fast EMA Period
input int InpSlowEMA = 26;            // Slow EMA Period
input int InpSignalEMA = 9;           // Signal EMA Period

//--- Trading Settings
sgroup "Trade Management"
input bool                InpAutoTradingEnabled = true;     // Enable/Disable Auto Trading
input ENUM_LOT_SIZE_METHOD InpLotSizingMethod = LOT_SIZE_PERCENTAGE; // Lot Sizing Method
input double              InpFixedLotSize = 0.01;           // Fixed Lot Size
input double              InpRiskPercent = 1.0;             // Risk Percentage per Trade
input double              InpRiskRewardRatio = 2.0;         // Take Profit to Stop Loss Ratio
input int                 InpSwingLookback = 10;            // Bars for Swing High/Low
input bool                InpExitOnOppositeSignal = true;   // Close trades on opposite signal
input bool                InpIgnoreTPOnCrossExit = false;   // Optional: Ignore TP, exit only on cross

//--- Stop Loss Settings
sgroup "Stop Loss Configuration"
input ENUM_SL_BUFFER_METHOD InpSLBufferMethod = ATR_MULTIPLIER; // SL Buffer Calculation Method
input double              InpSLFixedPoints = 100;           // SL Buffer in Points
input double              InpSLATRMultiplier = 0.2;         // SL Buffer ATR Multiplier
input int                 InpATRPeriod_SL = 14;             // ATR Period for SL Buffer

//--- Alert Settings
sgroup "Alert Configuration"
input bool InpEnableAlerts = true;       // Enable Alerts
input bool InpAlertPopup = true;         // Enable Pop-up Alerts
input bool InpAlertSound = true;         // Enable Sound Alerts
input bool InpAlertPush = false;        // Enable Push Notifications

//--- Optional Filters
sgroup "Trade Filters"
// Higher Timeframe Filter
input bool                        InpEnableHTFFilter = false;   // Enable Higher Timeframe Filter
input ENUM_TIMEFRAMES             InpHTFTimeframe = PERIOD_H4;  // Higher Timeframe
input int                         InpHTF_EMAPeriod = 200;       // HTF EMA Period
// Zero Line Filter
input bool                        InpEnableZeroLineFilter = false; // Enable Zero Line Filter
// Volatility Filter
input ENUM_VOLATILITY_FILTER_METHOD InpVolatilityFilter = VOL_NONE; // Volatility Filter Method
input int                         InpATRPeriod_Vol = 14;        // ATR Period for Volatility
input double                      InpMinATRPoints = 100;        // Minimum ATR in Points
input int                         InpATR_MAPeriod = 20;         // MA Period for ATR

//--- Global Variables
CTrade trade;
string indicator_path;
int    indicator_handle;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Set indicator path
   indicator_path = "Indicators\\SmoothedMACD";

   //--- Initialize Indicator Handle
   indicator_handle = iCustom(_Symbol, _Period, indicator_path, InpFastEMA, InpSlowEMA, InpSignalEMA, 5); // Correct MQL5 iCustom call

   if(indicator_handle == INVALID_HANDLE)
   {
      Print("Failed to create indicator handle for SmoothedMACD. Error: ", GetLastError());
      return(INIT_FAILED);
   }

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release indicator handle
   if(indicator_handle != INVALID_HANDLE)
      IndicatorRelease(indicator_handle);
}

//--- Global variable for new bar detection
datetime G_last_bar_time;

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Check for a new bar
   if(IsNewBar())
   {
      //--- Get latest indicator values
      double macd_line[3], signal_line[3], histogram[3];
      if(!GetIndicatorValues(macd_line, signal_line, histogram))
         return;

      //--- Define signals based on the latest closed bar (index 1)
      bool is_bullish_cross = macd_line[1] > signal_line[1] && macd_line[2] <= signal_line[2];
      bool is_bearish_cross = macd_line[1] < signal_line[1] && macd_line[2] >= signal_line[2];

      bool is_bullish_slope = macd_line[1] > macd_line[2];
      bool is_bearish_slope = macd_line[1] < macd_line[2];

      //--- Alert Logic
      if(InpEnableAlerts)
      {
         if(is_bullish_cross)
            SendAlert("BUY Signal");
         if(is_bearish_cross)
            SendAlert("SELL Signal");
      }

      //--- Auto Trading Logic
      if(InpAutoTradingEnabled)
      {
         //--- Exit Logic (check before entry)
         if(IsTradeOpen(POSITION_TYPE_BUY) && is_bearish_cross)
         {
            ClosePosition(POSITION_TYPE_BUY);
         }
         if(IsTradeOpen(POSITION_TYPE_SELL) && is_bullish_cross)
         {
            ClosePosition(POSITION_TYPE_SELL);
         }

         //--- Entry Logic
         // Check for BUY signal
         if(is_bullish_cross && histogram[1] > 0 && is_bullish_slope)
         {
            if(IsTradeOpen(OP_SELL) && InpExitOnOppositeSignal) ClosePosition(OP_SELL);
            if(!IsTradeOpen(OP_BUY) && AllFiltersPassed(OP_BUY))
            {
               //--- Execute Buy Trade
               double entry_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
               double sl_price = CalculateStopLoss(ORDER_TYPE_BUY);
               double tp_price = InpIgnoreTPOnCrossExit ? 0.0 : CalculateTakeProfit(ORDER_TYPE_BUY, entry_price, sl_price);
               double lots = CalculateLotSize(ORDER_TYPE_BUY, sl_price);

               if(lots > 0)
                  trade.Buy(lots, _Symbol, entry_price, sl_price, tp_price, "MACD EA Buy");
            }
         }

         // Check for SELL signal
         if(is_bearish_cross && histogram[1] < 0 && is_bearish_slope)
         {
            if(IsTradeOpen(OP_BUY) && InpExitOnOppositeSignal) ClosePosition(OP_BUY);
            if(!IsTradeOpen(OP_SELL) && AllFiltersPassed(OP_SELL))
            {
               //--- Execute Sell Trade
               double entry_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
               double sl_price = CalculateStopLoss(ORDER_TYPE_SELL);
               double tp_price = InpIgnoreTPOnCrossExit ? 0.0 : CalculateTakeProfit(ORDER_TYPE_SELL, entry_price, sl_price);
               double lots = CalculateLotSize(ORDER_TYPE_SELL, sl_price);

               if(lots > 0)
                  trade.Sell(lots, _Symbol, entry_price, sl_price, tp_price, "MACD EA Sell");
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check for a new bar                                              |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   MqlRates rates[1];
   if(CopyRates(_Symbol, _Period, 0, 1, rates) < 1)
      return(false);

   if(rates[0].time != G_last_bar_time)
   {
      G_last_bar_time = rates[0].time;
      return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| Get indicator values from the custom indicator                   |
//+------------------------------------------------------------------+
bool GetIndicatorValues(double &macd[], double &signal[], double &histo[])
{
   if(CopyBuffer(indicator_handle, 0, 0, 3, macd) < 3 ||
      CopyBuffer(indicator_handle, 1, 0, 3, signal) < 3 ||
      CopyBuffer(indicator_handle, 3, 0, 3, histo) < 3) // Corrected buffer index to 3 for Histogram
   {
      Print("Error copying indicator buffers. Error: ", GetLastError());
      return(false);
   }
   return(true);
}

//+------------------------------------------------------------------+
//| Send Alerts                                                      |
//+------------------------------------------------------------------+
void SendAlert(string message)
{
   string alert_msg = _Symbol + ", " + EnumToString(_Period) + ": " + message;
   if(InpAlertPopup) Alert(alert_msg);
   if(InpAlertSound) PlaySound("alert.wav");
   if(InpAlertPush) SendNotification(alert_msg);
}

//+------------------------------------------------------------------+
//| Check if a trade of a certain type is already open               |
//+------------------------------------------------------------------+
bool IsTradeOpen(ENUM_POSITION_TYPE type)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol)
      {
         if(PositionGetInteger(POSITION_TYPE) == type)
            return(true);
      }
   }
   return(false);
}

//+------------------------------------------------------------------+
//| Close an existing position of a certain type                     |
//+------------------------------------------------------------------+
void ClosePosition(ENUM_POSITION_TYPE type)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol)
      {
         if(PositionGetInteger(POSITION_TYPE) == type)
         {
            if(trade.PositionClose(PositionGetTicket(i)))
               break; // Exit after closing one position
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check all enabled filters                                        |
//+------------------------------------------------------------------+
bool AllFiltersPassed(ENUM_POSITION_TYPE type)
{
   if(InpEnableHTFFilter && !CheckHTFFilter(type)) return(false);
   if(InpEnableZeroLineFilter && !CheckZeroLineFilter(type)) return(false);
   if(InpVolatilityFilter != VOL_NONE && !CheckVolatilityFilter()) return(false);

   return(true);
}

//--- FILTER FUNCTIONS ---
bool CheckHTFFilter(ENUM_POSITION_TYPE type)
{
   double htf_ema_buffer[2]; // Need 2 bars for index 1
   if(CopyBuffer(iMA(_Symbol, InpHTFTimeframe, InpHTF_EMAPeriod, 0, MODE_EMA, PRICE_CLOSE), 0, 0, 2, htf_ema_buffer) < 2)
   {
      Print("Error copying HTF EMA buffer.");
      return(false); // Fail safe
   }

   MqlRates htf_rates[2]; // Need 2 bars for index 1
   if(CopyRates(_Symbol, InpHTFTimeframe, 0, 2, htf_rates) < 2)
   {
      Print("Error copying HTF rates.");
      return(false); // Fail safe
   }

   if(type == ORDER_TYPE_BUY && htf_rates[1].close < htf_ema_buffer[1]) return(false);
   if(type == ORDER_TYPE_SELL && htf_rates[1].close > htf_ema_buffer[1]) return(false);

   return(true);
}

bool CheckZeroLineFilter(ENUM_POSITION_TYPE type)
{
   double macd_line[1];
   if(CopyBuffer(indicator_handle, 0, 1, 1, macd_line) < 1)
   {
      Print("Error copying MACD buffer for Zero Line Filter.");
      return(false);
   }

   if(type == ORDER_TYPE_BUY && macd_line[0] < 0) return(false);
   if(type == ORDER_TYPE_SELL && macd_line[0] > 0) return(false);

   return(true);
}

bool CheckVolatilityFilter()
{
   //--- Get ATR history
   int data_to_copy = InpATR_MAPeriod + 1;
   double atr_history[];
   ArrayResize(atr_history, data_to_copy);
   int atr_handle = iATR(_Symbol, _Period, InpATRPeriod_Vol);
   if(CopyBuffer(atr_handle, 0, 1, data_to_copy, atr_history) < data_to_copy)
   {
      Print("Error copying ATR history for Volatility Filter. Copied: ", ArraySize(atr_history));
      return(false);
   }
   double current_atr = atr_history[0];

   //--- Check against selected method
   switch(InpVolatilityFilter)
   {
      case ATR_MIN_THRESHOLD:
         if(current_atr < InpMinATRPoints * _Point) return(false);
         break;

      case ATR_ABOVE_ATR_MA:
         double atr_ma_value;
         if(SimpleMAOnBuffer(atr_history, InpATR_MAPeriod, 0, atr_ma_value) != InpATR_MAPeriod)
         {
             Print("Error calculating ATR MA for Volatility Filter.");
             return(false);
         }
         if(current_atr < atr_ma_value) return(false);
         break;

      default: // VOL_NONE
         break;
   }

   return(true);
}
//+------------------------------------------------------------------+
//|  Calculates the SMA on a given buffer                            |
//+------------------------------------------------------------------+
int SimpleMAOnBuffer(const double &buffer[], int period, int start_pos, double &result)
{
   if(ArraySize(buffer) < period + start_pos) return(0);

   double sum = 0;
   for(int i = start_pos; i < start_pos + period; i++)
   {
      sum += buffer[i];
   }
   result = sum / period;

   return(period);
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Risk Management Functions                                        |
//+------------------------------------------------------------------+
double CalculateLotSize(ENUM_ORDER_TYPE type, double sl_price)
{
   if(InpLotSizingMethod == LOT_SIZE_FIXED)
      return(InpFixedLotSize);

   //--- Percentage-based lot size
   double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_amount = account_balance * (InpRiskPercent / 100.0);

   double current_price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl_distance_pips = MathAbs(current_price - sl_price) / _Point;
   if(sl_distance_pips == 0) return(0.01); // Avoid division by zero

   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lot_size = risk_amount / (sl_distance_pips * tick_value);

   //--- Normalize and check against limits
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lot_size = MathFloor(lot_size / step_lot) * step_lot;

   if(lot_size < min_lot) lot_size = min_lot;
   if(lot_size > max_lot) lot_size = max_lot;

   return(lot_size);
}

double CalculateStopLoss(ENUM_ORDER_TYPE type)
{
   //--- Get Swing High/Low from historical bars (signal is on bar 1, lookback starts from bar 2)
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, _Period, 2, InpSwingLookback, rates) < InpSwingLookback)
   {
      Print("Not enough bars for SL calculation.");
      return(0.0); // Not enough history
   }

   double swing_high = rates[ArrayMaximum(rates, 0, InpSwingLookback)].high;
   double swing_low = rates[ArrayMinimum(rates, 0, InpSwingLookback)].low;

   //--- Calculate Buffer
   double buffer = 0;
   if(InpSLBufferMethod == FIXED_POINTS)
   {
      buffer = InpSLFixedPoints * _Point;
   }
   else // ATR_MULTIPLIER
   {
      double atr_buffer[1];
      int atr_handle = iATR(_Symbol, _Period, InpATRPeriod_SL);
      CopyBuffer(atr_handle, 0, 1, 1, atr_buffer);
      buffer = atr_buffer[0] * InpSLATRMultiplier;
   }

   //--- Calculate Final SL
   if(type == ORDER_TYPE_BUY)
      return(swing_low - buffer);
   else
      return(swing_high + buffer);
}

double CalculateTakeProfit(ENUM_ORDER_TYPE type, double entry_price, double sl_price)
{
   double sl_distance = MathAbs(entry_price - sl_price);
   if(type == ORDER_TYPE_BUY)
      return(entry_price + (sl_distance * InpRiskRewardRatio));
   else
      return(entry_price - (sl_distance * InpRiskRewardRatio));
}
//+------------------------------------------------------------------+
