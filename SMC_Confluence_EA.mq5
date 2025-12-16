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

//--- Risk Management Settings
input double Risk_Percent_Per_Trade = 0.5;      // Risk % of account balance per trade
input double Take_Profit_1_RR = 2.0;            // Risk:Reward for TP1
input double Take_Profit_2_RR = 3.0;            // Risk:Reward for TP2
input int    Partial_Close_Percent = 50;        // Percentage of position to close at TP1
input double Breakeven_Buffer_Pips = 1.0;       // Pips to add to breakeven SL

//--- Trade Settings
input ulong  MagicNumber = 12345;
input uint   Slippage = 10;

//--- Global variables
CTrade trade;
int    ZigZagHandle;
int    ZoneZigZagHandle;

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

//--- Struct and array for managing active trades statefully
struct S_TradeInfo
  {
   long   ticket;
   double tp1_price;
   double tp2_price;
   bool   is_partial_closed;
  };
S_TradeInfo         ActiveTrades[];


//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- Initialize trading object
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetSlippage(Slippage);
   trade.SetTypeFillingBySymbol(Symbol());

//--- Reconstruct state of active trades on startup
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i))
        {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == Symbol())
           {
            S_TradeInfo info;
            info.ticket = PositionGetInteger(POSITION_TICKET);

            string comment = PositionGetString(POSITION_COMMENT);
            string parts[];
            StringSplit(comment, '|', parts);
            if(ArraySize(parts) >= 3)
              {
               info.tp1_price = StringToDouble(StringSubstr(parts[0], 4));
               info.tp2_price = StringToDouble(StringSubstr(parts[1], 4));
               info.is_partial_closed = (StringToInteger(StringSubstr(parts[2], 3)) == 1);

               ArrayResize(ActiveTrades, ArraySize(ActiveTrades)+1);
               ActiveTrades[ArraySize(ActiveTrades)-1] = info;
              }
           }
        }
     }

//--- Get ZigZag indicator handle for HTF trend analysis
   ZigZagHandle = iCustom(Symbol(), HTF_Timeframe, "ZigZag", ZigZag_Depth, ZigZag_Deviation, ZigZag_Backstep);
   if(ZigZagHandle == INVALID_HANDLE)
     {
      printf("Error creating HTF ZigZag indicator handle - error %d", GetLastError());
      return(INIT_FAILED);
     }

//--- Get ZigZag indicator handle for Zone_Timeframe analysis
   ZoneZigZagHandle = iCustom(Symbol(), Zone_Timeframe, "ZigZag", ZigZag_Depth, ZigZag_Deviation, ZigZag_Backstep);
   if(ZoneZigZagHandle == INVALID_HANDLE)
     {
      printf("Error creating Zone ZigZag indicator handle - error %d", GetLastError());
      return(INIT_FAILED);
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
   IndicatorRelease(ZigZagHandle);
   IndicatorRelease(ZoneZigZagHandle);
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // New bar detection timers
   static datetime last_htf_bar_time = 0;
   static datetime last_zone_bar_time = 0;
   static datetime last_entry_bar_time = 0;

   // Check for new HTF bar
   datetime current_htf_bar_time = (datetime)SeriesInfoInteger(Symbol(), HTF_Timeframe, SERIES_LASTBAR_DATE);
   if(current_htf_bar_time > last_htf_bar_time)
     {
      last_htf_bar_time = current_htf_bar_time;
      htf_trend = GetMarketTrend(); // Update trend only on new HTF bar
     }

   // Check for new Zone Timeframe bar
   datetime current_zone_bar_time = (datetime)SeriesInfoInteger(Symbol(), Zone_Timeframe, SERIES_LASTBAR_DATE);
   if(current_zone_bar_time > last_zone_bar_time)
     {
      last_zone_bar_time = current_zone_bar_time;
      // Update zones and volume profile on new Zone bar
      FindOrderBlocks();
      FindFairValueGaps();
      CalculateVolumeProfile();
     }

   // Check for new Entry Timeframe bar
   datetime current_entry_bar_time = (datetime)SeriesInfoInteger(Symbol(), Entry_Timeframe, SERIES_LASTBAR_DATE);
   if(current_entry_bar_time > last_entry_bar_time)
     {
      last_entry_bar_time = current_entry_bar_time;
      // Check for entries only on a new entry bar
      CheckForTradeEntry(htf_trend);
     }

//--- These functions need to run on every tick to be responsive
   ManageOpenTrades();
   DrawVisuals();
  }
//+------------------------------------------------------------------+
//| Deletes all created graphical objects                            |
//+------------------------------------------------------------------+
void DeleteAllObjects()
  {
   ObjectsDeleteAll(0, "smc_"); // Deletes all objects with the "smc_" prefix
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
//| Helper to create a styled rectangle object on the right of the chart |
//+------------------------------------------------------------------+
void DrawPriceZone(string name, double top_price, double bottom_price, color clr)
  {
   // Draw the zone for the last 50 bars on the chart for visibility
   datetime time2 = TimeCurrent();
   datetime time1 = time2 - (_Period * 60 * 50); // 50 bars back from now

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
   if(trend == TREND_NONE) return; // Do not trade in ranging markets

   // Get latest price data for checks
   MqlTick latest_tick;
   if(!SymbolInfoTick(Symbol(), latest_tick)) return;

   // Get Fibonacci levels for confluence check
   double fib_50, fib_61_8;
   GetFibonacciRetracementLevels(fib_50, fib_61_8);

   // --- CHECK FOR BULLISH ENTRY ---
   if(trend == TREND_BULLISH)
     {
      // Loop through Bullish OrderBlocks
      for(int i=0; i < ArraySize(OrderBlocks); i++)
        {
         if(!OrderBlocks[i].is_bullish) continue;

         // Confluence Check
         int confluence_score = 0;
         // 1. Is the OB overlapping with the HVN?
         if(OrderBlocks[i].bottom_price < HVN_Zone.top_price && OrderBlocks[i].top_price > HVN_Zone.bottom_price)
            confluence_score++;
         // 2. Is the OB near a Fibonacci level?
         if(MathAbs(OrderBlocks[i].bottom_price - fib_50) < (SymbolInfoDouble(Symbol(), SYMBOL_SPREAD) * 5) ||
            MathAbs(OrderBlocks[i].bottom_price - fib_61_8) < (SymbolInfoDouble(Symbol(), SYMBOL_SPREAD) * 5))
            confluence_score++;

         // Check for FVG confluence with the OB
         for(int j=0; j < ArraySize(FairValueGaps); j++)
           {
            if(FairValueGaps[j].is_bullish && FairValueGaps[j].bottom_price < OrderBlocks[i].top_price && FairValueGaps[j].top_price > OrderBlocks[i].bottom_price)
              {
               confluence_score++;
               break;
              }
           }

         // If we have at least 2 confluence factors and the current price is within the OB zone...
         if(confluence_score >= 2 && latest_tick.ask <= OrderBlocks[i].top_price && latest_tick.ask >= OrderBlocks[i].bottom_price)
           {
            // Final check: Look for a bullish engulfing pattern on the entry timeframe
            if(CheckForEngulfingPattern(TREND_BULLISH))
              {
               // All conditions met, calculate SL/TP and execute the trade
               double entry_price = latest_tick.ask;
               double sl_price = OrderBlocks[i].bottom_price - (SymbolInfoDouble(Symbol(), SYMBOL_SPREAD) * 2); // SL below the OB
               double sl_pips = (entry_price - sl_price) / SymbolInfoDouble(Symbol(), SYMBOL_POINT);
               double tp1_price = entry_price + (sl_pips * Take_Profit_1_RR * SymbolInfoDouble(Symbol(), SYMBOL_POINT));
               double tp2_price = entry_price + (sl_pips * Take_Profit_2_RR * SymbolInfoDouble(Symbol(), SYMBOL_POINT));

               ExecuteTrade(TREND_BULLISH, entry_price, sl_price, tp1_price, tp2_price);
               return; // Exit after finding one valid trade to avoid multiple trades on the same signal
              }
           }
        }
     }
   // --- CHECK FOR BEARISH ENTRY ---
   else if(trend == TREND_BEARISH)
     {
      // Loop through Bearish OrderBlocks
      for(int i=0; i < ArraySize(OrderBlocks); i++)
        {
         if(OrderBlocks[i].is_bullish) continue;

         int confluence_score = 0;
         if(OrderBlocks[i].bottom_price < HVN_Zone.top_price && OrderBlocks[i].top_price > HVN_Zone.bottom_price)
            confluence_score++;
         if(MathAbs(OrderBlocks[i].top_price - fib_50) < (SymbolInfoDouble(Symbol(), SYMBOL_SPREAD) * 5) ||
            MathAbs(OrderBlocks[i].top_price - fib_61_8) < (SymbolInfoDouble(Symbol(), SYMBOL_SPREAD) * 5))
            confluence_score++;

         for(int j=0; j < ArraySize(FairValueGaps); j++)
           {
            if(!FairValueGaps[j].is_bullish && FairValueGaps[j].bottom_price < OrderBlocks[i].top_price && FairValueGaps[j].top_price > OrderBlocks[i].bottom_price)
              {
               confluence_score++;
               break;
              }
           }

         if(confluence_score >= 2 && latest_tick.bid >= OrderBlocks[i].bottom_price && latest_tick.bid <= OrderBlocks[i].top_price)
           {
            if(CheckForEngulfingPattern(TREND_BEARISH))
              {
               double entry_price = latest_tick.bid;
               double sl_price = OrderBlocks[i].top_price + (SymbolInfoDouble(Symbol(), SYMBOL_SPREAD) * 2); // SL above the OB
               double sl_pips = (sl_price - entry_price) / SymbolInfoDouble(Symbol(), SYMBOL_POINT);
               double tp1_price = entry_price - (sl_pips * Take_Profit_1_RR * SymbolInfoDouble(Symbol(), SYMBOL_POINT));
               double tp2_price = entry_price - (sl_pips * Take_Profit_2_RR * SymbolInfoDouble(Symbol(), SYMBOL_POINT));

               ExecuteTrade(TREND_BEARISH, entry_price, sl_price, tp1_price, tp2_price);
               return; // Exit after finding one valid trade
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

   // We check the last two *closed* candles (index 1 and 2)
   ArraySetAsSeries(rates, true);
   MqlRates trigger_candle = rates[1];
   MqlRates prev_candle = rates[2];

   if(trend == TREND_BULLISH)
     {
      // Must be a bullish engulfing: trigger is up, previous is down, trigger engulfs previous
      if(trigger_candle.close > trigger_candle.open &&
         prev_candle.close < prev_candle.open &&
         trigger_candle.close > prev_candle.open &&
         trigger_candle.open < prev_candle.close)
         return true;
     }
   else // Bearish
     {
      // Must be a bearish engulfing: trigger is down, previous is up, trigger engulfs previous
      if(trigger_candle.close < trigger_candle.open &&
         prev_candle.close > prev_candle.open &&
         trigger_candle.close < prev_candle.open &&
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
   // --- Calculate Lot Size based on Risk ---
   double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_amount = account_balance * (Risk_Percent_Per_Trade / 100.0);
   double sl_pips = MathAbs(entry_price - sl_price) / SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   double tick_value = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
   double lot_size = (risk_amount / (sl_pips * tick_value));

   // Normalize and check against min/max lot size
   lot_size = NormalizeDouble(lot_size, 2);
   double min_lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
   if(lot_size < min_lot) lot_size = min_lot;
   if(lot_size > max_lot) lot_size = max_lot;

   // --- Execute Trade ---
   MqlTradeRequest request={0};
   MqlTradeResult  result={0};
   request.action = TRADE_ACTION_DEAL;
   request.symbol = Symbol();
   request.volume = lot_size;
   request.magic  = MagicNumber;
   request.deviation = Slippage;
   request.sl = sl_price;
   request.tp = tp1_price; // Set initial TP to TP1
   // Embed TP1/TP2 info into the comment. Format: "TP1:price|TP2:price|PC:0" (PC=Partial Closed)
   request.comment = "TP1:" + DoubleToString(tp1_price, _Digits) + "|TP2:" + DoubleToString(tp2_price, _Digits) + "|PC:0";


   if(trend == TREND_BULLISH)
     {
      request.type = ORDER_TYPE_BUY;
      request.price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
     }
   else
     {
      request.type = ORDER_TYPE_SELL;
      request.price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
     }

   if(OrderSend(request,result))
     {
      if(result.retcode == TRADE_RETCODE_DONE)
        {
         // After sending the order, we need to get the POSITION ticket, not the deal ticket
         if(PositionSelect(Symbol()))
           {
            S_TradeInfo info;
            info.ticket = PositionGetInteger(POSITION_TICKET);
            info.tp1_price = tp1_price;
            info.tp2_price = tp2_price;
         info.is_partial_closed = false;
         ArrayResize(ActiveTrades, ArraySize(ActiveTrades)+1);
         ActiveTrades[ArraySize(ActiveTrades)-1] = info;
        }
     }
   else
     {
      printf("OrderSend error %d", GetLastError());
     }
  }
//+------------------------------------------------------------------+
//| Manages open trades for partial close and SL to BE               |
//+------------------------------------------------------------------+
void ManageOpenTrades()
  {
   for(int i = ArraySize(ActiveTrades)-1; i >= 0; i--)
     {
      if(PositionSelectByTicket(ActiveTrades[i].ticket))
        {
         if(!ActiveTrades[i].is_partial_closed)
           {
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double current_price = SymbolInfoDouble(Symbol(), (type == POSITION_TYPE_BUY) ? SYMBOL_BID : SYMBOL_ASK);

            bool tp1_hit = false;
            if(type == POSITION_TYPE_BUY && current_price >= ActiveTrades[i].tp1_price) tp1_hit = true;
            if(type == POSITION_TYPE_SELL && current_price <= ActiveTrades[i].tp1_price) tp1_hit = true;

            if(tp1_hit)
              {
               double volume = PositionGetDouble(POSITION_VOLUME);
               double close_volume = NormalizeDouble(volume * (Partial_Close_Percent / 100.0), 2);

               if(trade.PositionClose(ActiveTrades[i].ticket, close_volume))
                 {
                  double be_level = PositionGetDouble(POSITION_OPEN_PRICE);
                  if(type == POSITION_TYPE_BUY) be_level += Breakeven_Buffer_Pips * SymbolInfoDouble(Symbol(), SYMBOL_POINT);
                  else be_level -= Breakeven_Buffer_Pips * SymbolInfoDouble(Symbol(), SYMBOL_POINT);

                  if(trade.PositionModify(ActiveTrades[i].ticket, be_level, ActiveTrades[i].tp2_price))
                    {
                     ActiveTrades[i].is_partial_closed = true;
                     // Persist the state change in the comment
                     string new_comment = "TP1:" + DoubleToString(ActiveTrades[i].tp1_price, _Digits) + "|TP2:" + DoubleToString(ActiveTrades[i].tp2_price, _Digits) + "|PC:1";
                     MqlTradeRequest request={0};
                     MqlTradeResult result={0};
                     request.action = TRADE_ACTION_MODIFY;
                     request.position = ActiveTrades[i].ticket;
                     request.comment = new_comment;
                     OrderSend(request, result);
                    }
                 }
              }
           }
        }
      else
        {
         ArrayRemove(ActiveTrades, i, 1);
        }
     }
  }
//+------------------------------------------------------------------+
//| Calculates the Volume Profile and identifies the HVN zone        |
//+------------------------------------------------------------------+
void CalculateVolumeProfile()
  {
   // Get historical data from the Zone_Timeframe
   MqlRates rates[];
   if(CopyRates(Symbol(), Zone_Timeframe, 0, CalculationBars, rates) < CalculationBars)
     {
      printf("Not enough data for Volume Profile calculation");
      return;
     }

   // Find the min and max price over the period
   double min_price = rates[ArrayMinimum(rates, WHOLE_ARRAY, 0)].low;
   double max_price = rates[ArrayMaximum(rates, WHOLE_ARRAY, 0)].high;

   // Create price bins
   double bin_size = (max_price - min_price) / VolumeProfile_Bins;
   long   volume_per_bin[];
   ArrayResize(volume_per_bin, VolumeProfile_Bins);
   ArrayInitialize(volume_per_bin, 0);

   // Distribute volume into bins
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

   // Find the Point of Control (POC) - bin with the highest volume
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

   // Identify HVN cluster based on threshold
   int hvn_start_index = poc_index;
   int hvn_end_index = poc_index;

   // Expand downwards from POC
   for(int i = poc_index - 1; i >= 0; i--)
     {
      if(volume_per_bin[i] >= max_volume * (HVN_Threshold_Percent / 100.0))
         hvn_start_index = i;
      else
         break;
     }

   // Expand upwards from POC
   for(int i = poc_index + 1; i < VolumeProfile_Bins; i++)
     {
      if(volume_per_bin[i] >= max_volume * (HVN_Threshold_Percent / 100.0))
         hvn_end_index = i;
      else
         break;
     }

   // Store the HVN zone
   HVN_Zone.bottom_price = min_price + (hvn_start_index * bin_size);
   HVN_Zone.top_price = min_price + ((hvn_end_index + 1) * bin_size);
  }
//+------------------------------------------------------------------+
//| Calculates key Fibonacci retracement levels for a given range    |
//+------------------------------------------------------------------+
bool GetFibonacciRetracementLevels(double &level_50, double &level_61_8)
  {
   double zigzag_buffer[];
   if(CopyBuffer(ZoneZigZagHandle, 0, 0, Fibo_Lookback_Bars, zigzag_buffer) <= 0)
     return false;

   ArraySetAsSeries(zigzag_buffer, true);

   // Find the last two swing points (one high, one low)
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

   // Direction of the range determines if we're looking for retracement up or down
   if(p1 > p2) // Downtrend swing (High to Low)
     {
      level_50 = high - (range * 0.5);
      level_61_8 = high - (range * 0.618);
     }
   else // Uptrend swing (Low to High)
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
   // Clear the array on each run to find fresh zones
   ArrayFree(OrderBlocks);

   MqlRates rates[];
   if(CopyRates(Symbol(), Zone_Timeframe, 0, OB_Lookback_Bars, rates) < OB_Lookback_Bars)
     {
      printf("Error copying rates for OB detection - error %d", GetLastError());
      return;
     }
   ArraySetAsSeries(rates, true);

   // To confirm BOS, we need ZigZag data on the Zone_Timeframe
   double zigzag_buffer[];
   if(CopyBuffer(ZoneZigZagHandle, 0, 0, OB_Lookback_Bars, zigzag_buffer) <= 0)
     {
       return; // Not enough data
     }
   ArraySetAsSeries(zigzag_buffer, true);

   // Loop through recent bars to find potential OBs
   for(int i=5; i < OB_Lookback_Bars - 2; i++) // Start a few bars in to have room for BOS check
     {
      // --- Look for Bullish OB (last down candle before up move)
      if(rates[i].open > rates[i].close && rates[i-1].open < rates[i-1].close)
        {
         // Potential Bullish OB found (candle at index 'i')
         // Now, check if a Break of Structure (BOS) occurred after this candle
         // A BOS is a new high after the OB
         double ob_high = rates[i].high;
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

         // Find the last major swing high before the OB
         double prior_swing_high = 0;
         for(int k=i+1; k < OB_Lookback_Bars; k++)
           {
            if(zigzag_buffer[k] == rates[k].high) // A ZigZag high point is exactly on the candle's high
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

              // Check for mitigation
              for(int k=subsequent_high_index; k>=0; k--)
                {
                 if(rates[k].low <= ob.top_price)
                   {
                    ob.is_mitigated = true;
                    break;
                   }
                }

              if(!ob.is_mitigated)
                {
                  ArrayResize(OrderBlocks, ArraySize(OrderBlocks)+1);
                  OrderBlocks[ArraySize(OrderBlocks)-1] = ob;
                }
           }
        }
      // --- Look for Bearish OB (last up candle before down move)
      else if(rates[i].open < rates[i].close && rates[i-1].open > rates[i-1].close)
        {
         // Potential Bearish OB found (candle at index 'i')
         double ob_low = rates[i].low;
         double subsequent_low = rates[0].low;
         int subsequent_low_index = 0;

         for(int j=i-1; j>=0; j--)
           {
            if(rates[j].low < subsequent_low)
              {
               subsequent_low = rates[j].low;
               subsequent_low_index = j;
              }
           }

         // Find the last major swing low before the OB
         double prior_swing_low = 0;
         for(int k=i+1; k < OB_Lookback_Bars; k++)
           {
            if(zigzag_buffer[k] == rates[k].low) // A ZigZag low point is exactly on the candle's low
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

              // Check for mitigation
              for(int k=subsequent_low_index; k>=0; k--)
                {
                 if(rates[k].high >= ob.bottom_price)
                   {
                    ob.is_mitigated = true;
                    break;
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
   // Clear the array on each run to find fresh zones
   ArrayFree(FairValueGaps);

   MqlRates rates[];
   if(CopyRates(Symbol(), Zone_Timeframe, 0, FVG_Lookback_Bars, rates) < FVG_Lookback_Bars)
     {
      printf("Error copying rates for FVG detection - error %d", GetLastError());
      return;
     }
   ArraySetAsSeries(rates, true);

   // Loop through the candles to find 3-bar patterns (from oldest to newest)
   for(int i = FVG_Lookback_Bars - 1; i >= 2; i--)
     {
      MqlRates c1 = rates[i];      // Oldest candle
      MqlRates c2 = rates[i - 1];  // Middle candle
      MqlRates c3 = rates[i - 2];  // Newest candle

      // Check for Bullish FVG (gap between c1 high and c3 low)
      if(c1.high < c3.low)
        {
         S_FairValueGap fvg;
         fvg.top_price = c3.low;
         fvg.bottom_price = c1.high;
         fvg.is_bullish = true;
         fvg.is_mitigated = false; // Initially, all found FVGs are unmitigated

         // Check if price has already filled this gap since it formed
         for(int k=i-3; k>=0; k--)
           {
            if(rates[k].low <= fvg.bottom_price)
              {
               fvg.is_mitigated = true;
               break;
              }
           }

         if(!fvg.is_mitigated)
           {
            bool exists = false;
            for(int j=0; j<ArraySize(FairValueGaps); j++)
              {
               if(FairValueGaps[j].top_price == fvg.top_price && FairValueGaps[j].bottom_price == fvg.bottom_price)
                 {
                  exists = true;
                  break;
                 }
              }
            if(!exists)
              {
               ArrayResize(FairValueGaps, ArraySize(FairValueGaps) + 1);
               FairValueGaps[ArraySize(FairValueGaps) - 1] = fvg;
              }
           }
        }
      // Check for Bearish FVG (gap between c1 low and c3 high)
      else if(c1.low > c3.high)
        {
         S_FairValueGap fvg;
         fvg.top_price = c1.low;
         fvg.bottom_price = c3.high;
         fvg.is_bullish = false;
         fvg.is_mitigated = false;

         // Check if price has already filled this gap since it formed
         for(int k=i-3; k>=0; k--)
           {
            if(rates[k].high >= fvg.top_price)
              {
               fvg.is_mitigated = true;
               break;
              }
           }

         if(!fvg.is_mitigated)
           {
            bool exists = false;
            for(int j=0; j<ArraySize(FairValueGaps); j++)
              {
               if(FairValueGaps[j].top_price == fvg.top_price && FairValueGaps[j].bottom_price == fvg.bottom_price)
                 {
                  exists = true;
                  break;
                 }
              }
            if(!exists)
              {
               ArrayResize(FairValueGaps, ArraySize(FairValueGaps) + 1);
               FairValueGaps[ArraySize(FairValueGaps) - 1] = fvg;
              }
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
   // Look at the last 500 bars of the HTF to find swings
   if(CopyBuffer(ZigZagHandle, 0, 0, 500, zigzag_buffer) <= 0)
     {
      printf("Error copying ZigZag buffer data - error %d", GetLastError());
      return TREND_NONE;
     }

   // Find the last 4 swing points
   double swing_points[4];
   int swing_count = 0;
   // Reverse array to search from the most recent bar
   ArraySetAsSeries(zigzag_buffer, true);

   for(int i = 0; i < 500; i++)
     {
      if(zigzag_buffer[i] > 0)
        {
         if(swing_count < 4)
           {
            swing_points[swing_count] = zigzag_buffer[i];
           }
         swing_count++;
        }
      if(swing_count >= 4)
         break;
     }

   // Need at least 4 points to determine structure (2 highs and 2 lows)
   if(swing_count < 4)
      return TREND_NONE;

   // Assuming the latest point (swing_points[0]) is a high, the sequence is H, L, H, L
   if(swing_points[0] > swing_points[1]) // Latest swing is a High
     {
      double last_high = swing_points[0];
      double last_low = swing_points[1];
      double prev_high = swing_points[2];
      double prev_low = swing_points[3];

      if(last_high > prev_high && last_low > prev_low)
         return TREND_BULLISH;
     }
   // Assuming the latest point (swing_points[0]) is a low, the sequence is L, H, L, H
   else // Latest swing is a Low
     {
      double last_low = swing_points[0];
      double last_high = swing_points[1];
      double prev_low = swing_points[2];
      double prev_high = swing_points[3];

      if(last_low < prev_low && last_high < prev_high)
         return TREND_BEARISH;
     }

   return TREND_NONE;
  }
//+------------------------------------------------------------------+
