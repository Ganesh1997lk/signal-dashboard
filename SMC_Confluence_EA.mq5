//+------------------------------------------------------------------+
//|                                           SMC_Confluence_EA.mq5 |
//|                                  Copyright 2023, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

//--- Include libraries
#include <Trade/Trade.mqh>

//--- EA Inputs

//--- Timeframe Settings
input ENUM_TIMEFRAMES HTF_Timeframe = PERIOD_D1;    // Trend timeframe
input ENUM_TIMEFRAMES Zone_Timeframe = PERIOD_H4;   // OB/FVG detection
input ENUM_TIMEFRAMES Entry_Timeframe = PERIOD_M15; // Confirmation candle

//--- Volume Profile Settings
input int  CalculationBars = 1000;       // Bars to analyze for Volume Profile
input int  HVN_Threshold_Percent = 70;   // Threshold for High Volume Node (%)
input int  VolumeProfile_Bins = 100;     // Number of price bins for profile

//--- Fibonacci / ZigZag Settings
input int  ZigZag_Depth = 12;
input int  ZigZag_Deviation = 5;
input int  ZigZag_Backstep = 3;

//--- Lookback Periods
input int OB_Lookback_Bars = 200;       // Bars to scan for Order Blocks
input int FVG_Lookback_Bars = 100;      // Bars to scan for FVGs
input int Fibo_Lookback_Bars = 500;     // Bars to scan for Fibo swings

//--- Strategy Settings
input int Min_Confluence_Score = 2;       // Minimum number of confluence factors for entry

//--- Risk Management Settings
input double Risk_Percent_Per_Trade = 0.5;      // Risk % of account balance per trade
input double Take_Profit_1_RR = 2.0;            // Risk:Reward for TP1
input double Take_Profit_2_RR = 3.0;            // Risk:Reward for TP2
input int    Partial_Close_Percent = 50;        // Percentage of position to close at TP1
input double Breakeven_Buffer_Pips = 1.0;       // Pips to add to breakeven SL

//--- Trade Settings
input ulong  Magic_Number = 12345;
input uint   Slippage = 10;

//--- Global variables
CTrade trade;

//--- Enums
enum ENUM_MARKET_TREND
  {
   TREND_BULLISH,
   TREND_BEARISH,
   TREND_NONE
  };

//--- Structs for Zones
struct S_OrderBlock
  {
   double top_price;
   double bottom_price;
   bool   is_bullish;
   bool   is_mitigated;
   // TBD: Add bar index/time for tracking
  };

struct S_FairValueGap
  {
   double top_price;
   double bottom_price;
   bool   is_bullish; // A bullish FVG is created by a strong up-move, creating a potential support zone.
   bool   is_mitigated;
   // TBD: Add bar index/time for tracking
  };

struct S_VolumeProfileZone
  {
   double top_price;
   double bottom_price;
  };

//--- Dynamic arrays to store zones
S_OrderBlock        OrderBlocks[];
S_FairValueGap      FairValueGaps[];
S_VolumeProfileZone HVN_Zone; // We will only store the primary HVN zone

//--- Global variables for analysis results
ENUM_MARKET_TREND   htf_trend = TREND_NONE;

//--- Global variables for indicator handles
int h_zigzag_htf = INVALID_HANDLE;
int h_zigzag_zone = INVALID_HANDLE;

// --- Struct to manage the state of our trades ---
// This allows the EA to remember TP levels and if TP1 was hit, even after a restart.
struct ManagedTradeState
{
    ulong position_ticket;
    double tp1_price;
    bool tp1_hit;
};
ManagedTradeState ManagedTrades[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- create timer
   EventSetTimer(1); // Set a 1-second timer for ManageOpenTrades
   ArrayResize(ManagedTrades, 0); // Initialize the array
   trade.SetExpertMagicNumber(Magic_Number); // Set the magic number for the trade object

   // --- INITIALIZE INDICATOR HANDLES ---
   h_zigzag_htf = iZigzag(Symbol(), HTF_Timeframe, ZigZag_Depth, ZigZag_Deviation, ZigZag_Backstep);
   if(h_zigzag_htf == INVALID_HANDLE)
     {
      Print("Error creating ZigZag HTF indicator handle - ", GetLastError());
      return(INIT_FAILED);
     }

   h_zigzag_zone = iZigzag(Symbol(), Zone_Timeframe, ZigZag_Depth, ZigZag_Deviation, ZigZag_Backstep);
   if(h_zigzag_zone == INVALID_HANDLE)
     {
      Print("Error creating ZigZag Zone indicator handle - ", GetLastError());
      return(INIT_FAILED);
     }

   // --- RECONSTRUCT STATE OF MANAGED TRADES ---
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong position_ticket = PositionGetTicket(i);
      if(position_ticket > 0 && PositionGetString(POSITION_SYMBOL) == Symbol() && PositionGetInteger(POSITION_MAGIC) == Magic_Number)
        {
         string comment = PositionGetString(POSITION_COMMENT);
         string parts[];
         if(StringSplit(comment, ',', parts) == 4) // Example: "SMC_EA,TICKET,TP1_PRICE,STATUS"
           {
            ManagedTradeState trade_state;
            trade_state.position_ticket = position_ticket;
            trade_state.tp1_price = StringToDouble(parts[2]);
            trade_state.tp1_hit = (parts[3] == "TP1_HIT");
            ArrayAdd(ManagedTrades, trade_state);
            Print("Reconstructed state for ticket #", position_ticket, ". TP1 Price: ", trade_state.tp1_price, ", TP1 Hit: ", trade_state.tp1_hit);
           }
        }
     }

//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- Release indicator handles
   IndicatorRelease(h_zigzag_htf);
   IndicatorRelease(h_zigzag_zone);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   CheckForNewBar();
  }

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
  {
   ManageOpenTrades();
   // Optional: Redraw visuals on a timer if needed, but can be resource-intensive
   // DrawVisuals();
  }

//+------------------------------------------------------------------+
//| Check for new bars on different timeframes                       |
//+------------------------------------------------------------------+
void CheckForNewBar()
  {
   static datetime last_bar_time_htf = 0;
   static datetime last_bar_time_zone = 0;
   static datetime last_bar_time_entry = 0;

   datetime current_bar_time_htf = (datetime)SeriesInfoInteger(Symbol(), HTF_Timeframe, SERIES_LASTBAR_DATE);
   datetime current_bar_time_zone = (datetime)SeriesInfoInteger(Symbol(), Zone_Timeframe, SERIES_LASTBAR_DATE);
   datetime current_bar_time_entry = (datetime)SeriesInfoInteger(Symbol(), Entry_Timeframe, SERIES_LASTBAR_DATE);

   bool is_new_htf_bar = false;
   bool is_new_zone_bar = false;
   bool is_new_entry_bar = false;

   if(current_bar_time_htf > last_bar_time_htf)
     {
      last_bar_time_htf = current_bar_time_htf;
      is_new_htf_bar = true;
      htf_trend = GetMarketTrend(); // Update trend on new HTF bar
     }
   if(current_bar_time_zone > last_bar_time_zone)
     {
      last_bar_time_zone = current_bar_time_zone;
      is_new_zone_bar = true;
      // Update zones and volume profile on new Zone bar
      FindOrderBlocks();
      FindFairValueGaps();
      CalculateVolumeProfile();
      DrawVisuals(); // Redraw visuals only when zones change
     }
   if(current_bar_time_entry > last_bar_time_entry)
     {
       last_bar_time_entry = current_bar_time_entry;
       is_new_entry_bar = true;
     }

   // --- CORE LOGIC EXECUTION ---
   // Check for entries on a new entry bar, but only if zones have been analyzed at least once
   if(is_new_entry_bar && ArraySize(OrderBlocks) > 0)
     {
      CheckForTradeEntry(htf_trend);
     }
  }

//+------------------------------------------------------------------+
//| Deletes all created graphical objects                            |
//+------------------------------------------------------------------+
void DeleteAllObjects()
  {
   ObjectsDeleteAll(0, "smc_");
  }
//+------------------------------------------------------------------+
//| Draws all visual elements on the chart                           |
//+------------------------------------------------------------------+
void DrawVisuals()
  {
   DeleteAllObjects();
   DrawOrderBlocks();
   DrawFairValueGaps();
   DrawVolumeProfile();
  }
//+------------------------------------------------------------------+
//| Helper to create a styled rectangle object                       |
//+------------------------------------------------------------------+
void DrawPriceZone(string name, double top_price, double bottom_price, color clr)
  {
   datetime time2 = TimeCurrent();
   datetime time1 = time2 - (PeriodSeconds(ChartPeriod()) * 100); // Draw for 100 bars

   ObjectCreate(0, name, OBJ_RECTANGLE, 0, time1, top_price, time2, bottom_price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }
//+------------------------------------------------------------------+
//| Draws the detected Order Block zones                             |
//+------------------------------------------------------------------+
void DrawOrderBlocks()
  {
   for(int i=0; i<ArraySize(OrderBlocks); i++)
     {
      string name = "smc_ob_" + (string)i;
      color ob_color = OrderBlocks[i].is_bullish ? clrCornflowerBlue : clrIndianRed;
      DrawPriceZone(name, OrderBlocks[i].top_price, OrderBlocks[i].bottom_price, ob_color);
     }
  }
//+------------------------------------------------------------------+
//| Draws the detected Fair Value Gap zones                          |
//+------------------------------------------------------------------+
void DrawFairValueGaps()
  {
   for(int i=0; i<ArraySize(FairValueGaps); i++)
     {
      string name = "smc_fvg_" + (string)i;
      DrawPriceZone(name, FairValueGaps[i].top_price, FairValueGaps[i].bottom_price, clrGray);
     }
  }
//+------------------------------------------------------------------+
//| Draws the detected HVN zone                                      |
//+------------------------------------------------------------------+
void DrawVolumeProfile()
  {
   if(HVN_Zone.top_price > 0)
     {
      string name = "smc_hvn";
      DrawPriceZone(name, HVN_Zone.top_price, HVN_Zone.bottom_price, clrGold);
     }
  }

//+------------------------------------------------------------------+
//| Checks for confluence and entry signals to place a trade         |
//+------------------------------------------------------------------+
void CheckForTradeEntry(ENUM_MARKET_TREND trend)
  {
   if(PositionsTotal() > 0)
     {
      // A trade managed by this EA instance already exists
      if(ArraySize(ManagedTrades) > 0) return;
     }

   if(trend == TREND_NONE) return;

   MqlTick latest_tick;
   if(!SymbolInfoTick(Symbol(), latest_tick)) return;

   double fib_50 = 0, fib_61_8 = 0;
   bool fib_ok = GetFibonacciRetracementLevels(fib_50, fib_61_8);

   if(trend == TREND_BULLISH)
     {
      for(int i=0; i < ArraySize(OrderBlocks); i++)
        {
         if(!OrderBlocks[i].is_bullish) continue;

         int confluence_score = 0;
         if(OrderBlocks[i].bottom_price < HVN_Zone.top_price && OrderBlocks[i].top_price > HVN_Zone.bottom_price)
            confluence_score++;
         if(fib_ok && (MathAbs(OrderBlocks[i].bottom_price - fib_50) < (SymbolInfoInteger(Symbol(), SYMBOL_SPREAD) * _Point * 5) ||
            MathAbs(OrderBlocks[i].bottom_price - fib_61_8) < (SymbolInfoInteger(Symbol(), SYMBOL_SPREAD) * _Point * 5)))
            confluence_score++;

         for(int j=0; j < ArraySize(FairValueGaps); j++)
           {
            if(FairValueGaps[j].is_bullish && FairValueGaps[j].bottom_price < OrderBlocks[i].top_price && FairValueGaps[j].top_price > OrderBlocks[i].bottom_price)
              {
               confluence_score++;
               break;
              }
           }

         if(confluence_score >= Min_Confluence_Score && latest_tick.ask <= OrderBlocks[i].top_price && latest_tick.ask >= OrderBlocks[i].bottom_price)
           {
            if(CheckForEngulfingPattern(TREND_BULLISH))
              {
               double entry_price = latest_tick.ask;
               double sl_price = OrderBlocks[i].bottom_price - (SymbolInfoInteger(Symbol(), SYMBOL_SPREAD) * _Point * 2);
               double sl_pips = (entry_price - sl_price) / _Point;
               double tp1_price = entry_price + (sl_pips * Take_Profit_1_RR * _Point);
               double tp2_price = entry_price + (sl_pips * Take_Profit_2_RR * _Point);

               ExecuteTrade(TREND_BULLISH, entry_price, sl_price, tp1_price, tp2_price);
               return;
              }
           }
        }
     }
   else if(trend == TREND_BEARISH)
     {
      for(int i=0; i < ArraySize(OrderBlocks); i++)
        {
         if(OrderBlocks[i].is_bullish) continue;

         int confluence_score = 0;
         if(OrderBlocks[i].bottom_price < HVN_Zone.top_price && OrderBlocks[i].top_price > HVN_Zone.bottom_price)
            confluence_score++;
         if(fib_ok && (MathAbs(OrderBlocks[i].top_price - fib_50) < (SymbolInfoInteger(Symbol(), SYMBOL_SPREAD) * _Point * 5) ||
            MathAbs(OrderBlocks[i].top_price - fib_61_8) < (SymbolInfoInteger(Symbol(), SYMBOL_SPREAD) * _Point * 5)))
            confluence_score++;

         for(int j=0; j < ArraySize(FairValueGaps); j++)
           {
            if(!FairValueGaps[j].is_bullish && FairValueGaps[j].bottom_price < OrderBlocks[i].top_price && FairValueGaps[j].top_price > OrderBlocks[i].bottom_price)
              {
               confluence_score++;
               break;
              }
           }

         if(confluence_score >= Min_Confluence_Score && latest_tick.bid >= OrderBlocks[i].bottom_price && latest_tick.bid <= OrderBlocks[i].top_price)
           {
            if(CheckForEngulfingPattern(TREND_BEARISH))
              {
               double entry_price = latest_tick.bid;
               double sl_price = OrderBlocks[i].top_price + (SymbolInfoInteger(Symbol(), SYMBOL_SPREAD) * _Point * 2);
               double sl_pips = (sl_price - entry_price) / _Point;
               double tp1_price = entry_price - (sl_pips * Take_Profit_1_RR * _Point);
               double tp2_price = entry_price - (sl_pips * Take_Profit_2_RR * _Point);

               ExecuteTrade(TREND_BEARISH, entry_price, sl_price, tp1_price, tp2_price);
               return;
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Checks for a valid engulfing pattern on the entry timeframe      |
//+------------------------------------------------------------------+
bool CheckForEngulfingPattern(ENUM_MARKET_TREND trend)
  {
   MqlRates rates[];
   if(CopyRates(Symbol(), Entry_Timeframe, 0, 3, rates) < 3)
      return false;

   ArraySetAsSeries(rates, true);
   MqlRates trigger_candle = rates[1];
   MqlRates prev_candle = rates[2];

   if(trend == TREND_BULLISH)
     {
      if(trigger_candle.close > trigger_candle.open &&
         prev_candle.close < prev_candle.open &&
         trigger_candle.close > prev_candle.open &&
         trigger_candle.open < prev_candle.close)
         return true;
     }
   else
     {
      if(trigger_candle.close < trigger_candle.open &&
         prev_candle.close > prev_candle.open &&
         trigger_candle.close < prev_candle.open && // Corrected logic: close < open for bearish
         trigger_candle.open > prev_candle.close)
         return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Executes a trade with proper risk management                     |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_MARKET_TREND trend, double entry_price, double sl_price, double tp1_price, double tp2_price)
  {
   double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_amount = account_balance * (Risk_Percent_Per_Trade / 100.0);
   double sl_pips = MathAbs(entry_price - sl_price) / _Point;
   double tick_value = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
   if(sl_pips <= 0 || tick_value <=0)
     {
       Print("Invalid SL pips or Tick Value for lot calculation. SL Pips: ", sl_pips, ", Tick Value: ", tick_value);
       return;
     }
   double lot_size = (risk_amount / (sl_pips * tick_value));

   lot_size = NormalizeDouble(lot_size, 2);
   double min_lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
   double vol_step = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);

   lot_size = fmax(min_lot, floor(lot_size / vol_step) * vol_step);
   lot_size = fmin(max_lot, lot_size);

   if(lot_size < min_lot)
     {
      Print("Calculated lot size ", lot_size, " is less than minimum ", min_lot);
      return;
     }

   string trade_type = (trend == TREND_BULLISH) ? "BUY" : "SELL";

   // --- Set initial TP to TP1 ---
   // The final TP (TP2) will be set after TP1 is hit and position is partially closed.
   if(trade.PositionOpen(Symbol(), (trend == TREND_BULLISH) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, lot_size, (trend == TREND_BULLISH) ? SymbolInfoDouble(Symbol(), SYMBOL_ASK) : SymbolInfoDouble(Symbol(), SYMBOL_BID), sl_price, tp1_price))
     {
        // After opening, get the position ticket to manage its state
        if(PositionSelect(Symbol()))
          {
             ulong ticket = PositionGetInteger(POSITION_TICKET);

             // Create a new state object for our managed trade
             ManagedTradeState new_trade;
             new_trade.position_ticket = ticket;
             new_trade.tp1_price = tp1_price;
             new_trade.tp1_hit = false;
             ArrayAdd(ManagedTrades, new_trade);

             // IMPORTANT: Update the comment of the just-opened position to store its state
             // Format: "SMC_EA,TICKET,TP1_PRICE,STATUS"
             string comment = "SMC_EA," + (string)ticket + "," + DoubleToString(tp1_price, _Digits) + ",TP1_PENDING";
             if(!trade.PositionModify(ticket, PositionGetDouble(POSITION_SL), PositionGetDouble(POSITION_TP)))
                {
                   Print("Could not modify position to set initial comment. Error: ", GetLastError());
                }
             else
                {
                   // CTrade doesn't have a direct comment modify, we need to do it via request
                    MqlTradeRequest request;
                    MqlTradeResult result;
                    request.action = TRADE_ACTION_MODIFY;
                    request.position = ticket;
                    request.comment = comment;
                    if(!OrderSend(request, result))
                    {
                        Print("Failed to set comment on position #", ticket, " Error: ", GetLastError());
                    }
                }
          }
        else
          {
             Print("Failed to select position after opening trade. Cannot manage state.");
          }
     }
   else
     {
      Print("PositionOpen failed for ", trade_type, ". Error: ", GetLastError());
     }
  }

//+------------------------------------------------------------------+
//| Manage Open Trades                                               |
//+------------------------------------------------------------------+
void ManageOpenTrades()
  {
   MqlTick latest_tick;
   SymbolInfoTick(Symbol(), latest_tick);

   for(int i = ArraySize(ManagedTrades) - 1; i >= 0; i--)
     {
      if(!PositionSelectByTicket(ManagedTrades[i].position_ticket))
        {
         ArrayRemove(ManagedTrades, i, 1);
         continue;
        }

      if(!ManagedTrades[i].tp1_hit)
        {
         long pos_type = PositionGetInteger(POSITION_TYPE);
         double current_price = (pos_type == POSITION_TYPE_BUY) ? latest_tick.bid : latest_tick.ask;
         double open_price = PositionGetDouble(POSITION_PRICE_OPEN);

         bool tp1_triggered = false;
         if(pos_type == POSITION_TYPE_BUY && current_price >= ManagedTrades[i].tp1_price)
           {
            tp1_triggered = true;
           }
         else if(pos_type == POSITION_TYPE_SELL && current_price <= ManagedTrades[i].tp1_price)
           {
            tp1_triggered = true;
           }
         if(tp1_triggered)
           {
            double initial_volume = PositionGetDouble(POSITION_VOLUME);
            double volume_to_close = initial_volume * (Partial_Close_Percent / 100.0);
            double vol_step = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
            volume_to_close = floor(volume_to_close / vol_step) * vol_step;

            if(volume_to_close > 0)
              {
                if(trade.PositionClose(ManagedTrades[i].position_ticket, (ulong)round(volume_to_close * 100)))
                 {
                  Print("Successfully closed partial position for ticket #", ManagedTrades[i].position_ticket);

                  // Move SL to breakeven + buffer
                  double be_price = open_price;
                  if(pos_type == POSITION_TYPE_BUY) be_price += Breakeven_Buffer_Pips * _Point;
                  else be_price -= Breakeven_Buffer_Pips * _Point;

                  // Calculate TP2 based on original SL
                  double original_sl = PositionGetDouble(POSITION_SL);
                  double sl_pips = MathAbs(open_price - original_sl) / _Point;
                  double tp2_price = 0;
                  if(pos_type == POSITION_TYPE_BUY) tp2_price = open_price + (sl_pips * Take_Profit_2_RR * _Point);
                  else tp2_price = open_price - (sl_pips * Take_Profit_2_RR * _Point);

                  if(trade.PositionModify(ManagedTrades[i].position_ticket, be_price, tp2_price))
                    {
                      Print("Successfully moved SL to breakeven and set TP2 for ticket #", ManagedTrades[i].position_ticket);
                      ManagedTrades[i].tp1_hit = true;

                      // Update comment to reflect state change
                      string comment = "SMC_EA," + (string)ManagedTrades[i].position_ticket + "," + DoubleToString(ManagedTrades[i].tp1_price, _Digits) + ",TP1_HIT";
                      MqlTradeRequest request;
                      MqlTradeResult result;
                      request.action = TRADE_ACTION_MODIFY;
                      request.position = ManagedTrades[i].position_ticket;
                      request.comment = comment;
                      if(!OrderSend(request, result))
                      {
                          Print("Failed to update comment on position #", ManagedTrades[i].position_ticket, " Error: ", GetLastError());
                      }
                    }
                  else
                    {
                      Print("Error modifying position for BE/TP2 on ticket #", ManagedTrades[i].position_ticket, ". Error: ", GetLastError());
                    }
                 }
                else
                 {
                  Print("Error closing partial position for ticket #", ManagedTrades[i].position_ticket, ". Error: ", GetLastError());
                 }
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Calculates the Volume Profile and identifies the HVN zone        |
//+------------------------------------------------------------------+
void CalculateVolumeProfile()
  {
   MqlRates rates[];
   if(CopyRates(Symbol(), Zone_Timeframe, 0, CalculationBars, rates) < CalculationBars)
     {
      Print("Not enough data for Volume Profile calculation");
      return;
     }

   double min_price, max_price;
   int min_pos, max_pos;
   ArrayGetMax(rates,0,CalculationBars,max_pos);
   ArrayGetMin(rates,0,CalculationBars,min_pos);
   min_price = rates[min_pos].low;
   max_price = rates[max_pos].high;

   if(VolumeProfile_Bins <= 0) return;
   double bin_size = (max_price - min_price) / VolumeProfile_Bins;
   if(bin_size <= 0) return;

   long   volume_per_bin[];
   ArrayResize(volume_per_bin, VolumeProfile_Bins);
   ArrayInitialize(volume_per_bin, 0);

   for(int i=0; i<CalculationBars; i++)
     {
      int start_bin = (int)((rates[i].low - min_price) / bin_size);
      int end_bin = (int)((rates[i].high - min_price) / bin_size);

      for(int j=start_bin; j<=end_bin; j++)
        {
         if(j >= 0 && j < VolumeProfile_Bins)
            volume_per_bin[j] += rates[i].tick_volume;
        }
     }

   long max_volume = 0;
   int poc_index = -1;
   for(int i=0; i<VolumeProfile_Bins; i++)
     {
      if(volume_per_bin[i] > max_volume)
        {
         max_volume = volume_per_bin[i];
         poc_index = i;
        }
     }

   if(poc_index == -1) return;

   int hvn_start_index = poc_index;
   int hvn_end_index = poc_index;

   for(int i = poc_index - 1; i >= 0; i--)
     {
      if(volume_per_bin[i] >= max_volume * (HVN_Threshold_Percent / 100.0))
         hvn_start_index = i;
      else
         break;
     }

   for(int i = poc_index + 1; i < VolumeProfile_Bins; i++)
     {
      if(volume_per_bin[i] >= max_volume * (HVN_Threshold_Percent / 100.0))
         hvn_end_index = i;
      else
         break;
     }

   HVN_Zone.bottom_price = min_price + (hvn_start_index * bin_size);
   HVN_Zone.top_price = min_price + ((hvn_end_index + 1) * bin_size);
  }
//+------------------------------------------------------------------+
//| Calculates key Fibonacci retracement levels for a given range    |
//+------------------------------------------------------------------+
bool GetFibonacciRetracementLevels(double &level_50, double &level_61_8)
  {
   double zigzag_buffer[];
   if(CopyBuffer(h_zigzag_zone, 0, 0, Fibo_Lookback_Bars, zigzag_buffer) <= 0)
     return false;

   ArraySetAsSeries(zigzag_buffer, true);

   double p1=0, p2=0;
   int swings_found=0;
   for(int i=0; i<Fibo_Lookback_Bars; i++)
     {
      if(zigzag_buffer[i]>0)
        {
         if(swings_found==0) p1 = zigzag_buffer[i];
         if(swings_found==1) p2 = zigzag_buffer[i];
         swings_found++;
         if(swings_found>=2) break;
        }
     }

   if(swings_found<2) return false;

   double high = MathMax(p1,p2);
   double low = MathMin(p1,p2);
   double range = high - low;

   if(p1 > p2)
     {
      level_50 = high - (range * 0.5);
      level_61_8 = high - (range * 0.618);
     }
   else
     {
      level_50 = low + (range * 0.5);
      level_61_8 = low + (range * 0.618);
     }

   return true;
  }
//+------------------------------------------------------------------+
//| Finds and stores valid Order Blocks                              |
//+------------------------------------------------------------------+
void FindOrderBlocks()
  {
   ArrayFree(OrderBlocks);

   MqlRates rates[];
   if(CopyRates(Symbol(), Zone_Timeframe, 0, OB_Lookback_Bars, rates) < OB_Lookback_Bars)
     {
      Print("Error copying rates for OB detection - error ", GetLastError());
      return;
     }
   ArraySetAsSeries(rates, true);

   double zigzag_buffer[];
   if(CopyBuffer(h_zigzag_zone, 0, 0, OB_Lookback_Bars, zigzag_buffer) <= 0)
     {
       return;
     }
   ArraySetAsSeries(zigzag_buffer, true);

   for(int i=5; i < OB_Lookback_Bars - 2; i++)
     {
      if(rates[i].open > rates[i].close && rates[i-1].open < rates[i-1].close)
        {
         double subsequent_high = 0;
         int subsequent_high_index = -1;

         for(int j=i-1; j>=0; j--)
           {
            if(rates[j].high > subsequent_high)
              {
               subsequent_high = rates[j].high;
               subsequent_high_index = j;
              }
           }

         double prior_swing_high = 0;
         for(int k=i+1; k < OB_Lookback_Bars; k++)
           {
            if(zigzag_buffer[k] > 0 && zigzag_buffer[k] == rates[k].high)
              {
               prior_swing_high = zigzag_buffer[k];
               break;
              }
           }

         if(subsequent_high > prior_swing_high && prior_swing_high > 0)
           {
              S_OrderBlock ob;
              ob.top_price = rates[i].high;
              ob.bottom_price = rates[i].low;
              ob.is_bullish = true;
              ob.is_mitigated = false;

              if(subsequent_high_index > 0)
              {
                for(int k=subsequent_high_index; k>=0; k--)
                  {
                   if(rates[k].low <= ob.top_price)
                     {
                      ob.is_mitigated = true;
                      break;
                     }
                  }
              }

              if(!ob.is_mitigated)
                {
                  ArrayResize(OrderBlocks, ArraySize(OrderBlocks)+1);
                  OrderBlocks[ArraySize(OrderBlocks)-1] = ob;
                }
           }
        }
      else if(rates[i].open < rates[i].close && rates[i-1].open > rates[i-1].close)
        {
         double subsequent_low = 999999;
         int subsequent_low_index = -1;

         for(int j=i-1; j>=0; j--)
           {
            if(rates[j].low < subsequent_low)
              {
               subsequent_low = rates[j].low;
               subsequent_low_index = j;
              }
           }

         double prior_swing_low = 0;
         for(int k=i+1; k < OB_Lookback_Bars; k++)
           {
            if(zigzag_buffer[k] > 0 && zigzag_buffer[k] == rates[k].low)
              {
               prior_swing_low = zigzag_buffer[k];
               break;
              }
           }

         if(subsequent_low < prior_swing_low && prior_swing_low > 0)
           {
              S_OrderBlock ob;
              ob.top_price = rates[i].high;
              ob.bottom_price = rates[i].low;
              ob.is_bullish = false;
              ob.is_mitigated = false;

              if(subsequent_low_index > 0)
              {
                for(int k=subsequent_low_index; k>=0; k--)
                  {
                   if(rates[k].high >= ob.bottom_price)
                     {
                      ob.is_mitigated = true;
                      break;
                     }
                  }
              }

              if(!ob.is_mitigated)
                {
                  ArrayResize(OrderBlocks, ArraySize(OrderBlocks)+1);
                  OrderBlocks[ArraySize(OrderBlocks)-1] = ob;
                }
           }
        }
     }
  }
//+------------------------------------------------------------------+
//| Finds and stores valid Fair Value Gaps                           |
//+------------------------------------------------------------------+
void FindFairValueGaps()
  {
   ArrayFree(FairValueGaps);

   MqlRates rates[];
   if(CopyRates(Symbol(), Zone_Timeframe, 0, FVG_Lookback_Bars, rates) < FVG_Lookback_Bars)
     {
      Print("Error copying rates for FVG detection - error ", GetLastError());
      return;
     }
   ArraySetAsSeries(rates, true);

   for(int i = FVG_Lookback_Bars - 3; i >= 0; i--)
     {
      MqlRates c1 = rates[i+2];
      MqlRates c2 = rates[i+1];
      MqlRates c3 = rates[i];

      if(c1.high < c3.low)
        {
         S_FairValueGap fvg;
         fvg.top_price = c3.low;
         fvg.bottom_price = c1.high;
         fvg.is_bullish = true;
         fvg.is_mitigated = false;

         for(int k=i-1; k>=0; k--)
           {
            if(rates[k].low <= fvg.bottom_price)
              {
               fvg.is_mitigated = true;
               break;
              }
           }

         if(!fvg.is_mitigated)
           {
            ArrayAdd(FairValueGaps, fvg);
           }
        }
      else if(c1.low > c3.high)
        {
         S_FairValueGap fvg;
         fvg.top_price = c1.low;
         fvg.bottom_price = c3.high;
         fvg.is_bullish = false;
         fvg.is_mitigated = false;

         for(int k=i-1; k>=0; k--)
           {
            if(rates[k].high >= fvg.top_price)
              {
               fvg.is_mitigated = true;
               break;
              }
           }

         if(!fvg.is_mitigated)
           {
            ArrayAdd(FairValueGaps, fvg);
           }
        }
     }
  }
//+------------------------------------------------------------------+
//| Determines market trend based on HTF ZigZag swings               |
//+------------------------------------------------------------------+
ENUM_MARKET_TREND GetMarketTrend()
  {
    double zigzag_buffer[];
    MqlRates rates[];

    if(CopyRates(Symbol(), HTF_Timeframe, 0, 500, rates) < 500 || CopyBuffer(h_zigzag_htf, 0, 0, 500, zigzag_buffer) <= 0)
    {
        Print("Error copying data for trend analysis");
        return TREND_NONE;
    }

    ArraySetAsSeries(rates, true);
    ArraySetAsSeries(zigzag_buffer, true);

    double highs[2] = {0, 0};
    double lows[2] = {0, 0};
    int high_count = 0;
    int low_count = 0;

    for(int i = 0; i < 500; i++)
    {
        if(zigzag_buffer[i] > 0)
        {
            if(zigzag_buffer[i] == rates[i].high)
            {
                if(high_count < 2) highs[high_count] = zigzag_buffer[i];
                high_count++;
            }
            else if(zigzag_buffer[i] == rates[i].low)
            {
                if(low_count < 2) lows[low_count] = zigzag_buffer[i];
                low_count++;
            }
        }
        if(high_count >= 2 && low_count >= 2)
            break;
    }

    if(high_count < 2 || low_count < 2)
        return TREND_NONE;

    if(highs[0] > highs[1] && lows[0] > lows[1])
        return TREND_BULLISH;

    if(highs[0] < highs[1] && lows[0] < lows[1])
        return TREND_BEARISH;

    return TREND_NONE;
}
//+------------------------------------------------------------------+
