//+------------------------------------------------------------------+
//|                                                  BreakoutEA.mq5|
//|                                  Copyright 2023, MetaQuotes Ltd.|
//|                                             https://www.mql5.com|
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|                                                  BreakoutEA.mq5  |
//|                 Trades the breakout of the previous candle's high/low.|
//|                                  Copyright 2023, MetaQuotes Ltd. |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property description "This EA trades breakouts of the previous candle's high or low."

#include <Trade/Trade.mqh>

//--- EA Inputs ---
// Group: Basic Trade Settings
input group           "Basic Trade Settings"
input ulong           InpMagicNumber = 12345;     // Magic Number
input double          InpLotSize = 0.01;            // Lot Size
input double          InpRiskRewardRatio = 2.0;     // Take Profit / Stop Loss Ratio

// Group: Trade Management
input group           "Trade Management"
input int             InpBreakevenPips = 20;        // Pips to trigger breakeven (0=disable)
input int             InpTrailingStopPips = 20;     // Trailing stop pips (0=disable)
input bool            InpCloseOnOpposite = true;    // Close trades on opposite signal

// Group: Risk Filters
input group           "Risk Filters"
input int             InpMaxSpreadPips = 2;         // Max allowed spread in pips
input int             InpMaxOpenTrades = 10;        // Max number of open trades

// Group: Time Filter
input group           "Time Filter"
input int             InpTradingStartTime = 0;      // EA start time (hour, 0-23)
input int             InpTradingEndTime = 23;       // EA end time (hour, 0-23)


//--- Global variables ---
CTrade trade; // Trading object

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//| Called once when the EA is first loaded.                         |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- Initialize the trading object with the magic number
   trade.SetExpertMagicNumber(InpMagicNumber);
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//| Called once when the EA is being removed.                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- Clean up resources if needed
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//| This is the main function, called on every new price tick.       |
//+------------------------------------------------------------------+
void OnTick()
  {
//--- First, manage any currently open trades (trailing stops, etc.)
   ManageTrades();

//--- From here, logic is for opening NEW trades, so we only run it once per bar.
   static datetime lastBarTime=0;
   MqlRates rates[1];
//--- Copy the latest bar data
   if(CopyRates(_Symbol,_Period,0,1,rates))
     {
      //--- If the current bar's time is the same as the last, do nothing.
      if(lastBarTime==rates[0].time)
         return;
      //--- Otherwise, update the time and proceed.
      lastBarTime=rates[0].time;
     }

//--- Get the high and low of the PREVIOUS completed candle (index 1)
   MqlRates prevCandle[1];
   if(!CopyRates(_Symbol, _Period, 1, 1, prevCandle))
     {
      Print("Error copying previous candle rates: ", GetLastError());
      return;
     }
   double prevHigh = prevCandle[0].high;
   double prevLow = prevCandle[0].low;

//--- Get the latest market prices (Ask for buy, Bid for sell)
   MqlTick currentTick;
   if(!SymbolInfoTick(_Symbol, currentTick))
     {
      Print("Error getting current tick: ", GetLastError());
      return;
     }
   double ask = currentTick.ask;
   double bid = currentTick.bid;

//--- Signal Generation: Check for breakout
   bool buySignal = (ask > prevHigh);
   bool sellSignal = (bid < prevLow);

//--- === ENTRY LOGIC === ---

//--- If a Buy Signal occurs...
   if(buySignal)
     {
      //--- If user wants to close opposite trades, do so now.
      if(InpCloseOnOpposite)
         CloseAllSellTrades();
      //--- Check all risk filters before placing the trade.
      if(CheckRiskFilters())
        {
         OpenBuyTrade(prevLow, ask); // SL is the previous low
        }
     }

//--- If a Sell Signal occurs...
   if(sellSignal)
     {
      //--- If user wants to close opposite trades, do so now.
      if(InpCloseOnOpposite)
         CloseAllBuyTrades();
      //--- Check all risk filters before placing the trade.
      if(CheckRiskFilters())
        {
         OpenSellTrade(prevHigh, bid); // SL is the previous high
        }
     }
  }
//+------------------------------------------------------------------+
//| Check Risk Filters                                               |
//| Verifies that all risk conditions are met before opening a trade.|
//+------------------------------------------------------------------+
bool CheckRiskFilters()
  {
//--- 1. Spread Check ---
   double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   //--- Adjust for 3/5 digit brokers by multiplying pips by 10
   double point_multiplier = (_Digits == 3 || _Digits == 5) ? 10 : 1;
   double maxSpreadInPoints = InpMaxSpreadPips * point_multiplier;

   if(spread > maxSpreadInPoints)
     {
      Print("Spread filter failed. Current spread ", spread, " > ", maxSpreadInPoints);
      return(false);
     }

//--- 2. Max Open Trades Check ---
   if(PositionsTotal() >= InpMaxOpenTrades)
     {
      Print("Max open trades limit reached: ", PositionsTotal());
      return(false);
     }

//--- 3. Time Filter Check ---
   MqlDateTime currentTime;
   TimeCurrent(currentTime);
   int currentHour = currentTime.hour;

   //--- Logic to handle overnight sessions correctly (e.g., start 22:00, end 04:00)
   if(InpTradingStartTime > InpTradingEndTime)
     {
      if(currentHour >= InpTradingEndTime && currentHour < InpTradingStartTime)
        {
         Print("Time filter failed. Current hour ", currentHour, " is outside of ", InpTradingStartTime, "-", InpTradingEndTime);
         return(false);
        }
     }
   else //--- Logic for normal day sessions (e.g., start 08:00, end 16:00)
     {
      if(currentHour < InpTradingStartTime || currentHour >= InpTradingEndTime)
        {
         Print("Time filter failed. Current hour ", currentHour, " is outside of ", InpTradingStartTime, "-", InpTradingEndTime);
         return(false);
        }
     }

//--- If all checks pass, return true
   return(true);
  }
//+------------------------------------------------------------------+
//| Open Buy Trade                                                   |
//| Executes a buy order with calculated SL and TP.                  |
//+------------------------------------------------------------------+
void OpenBuyTrade(double sl_price, double ask_price)
  {
//--- Calculate Stop Loss distance in points
   double sl_points = (ask_price - sl_price) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
//--- Calculate Take Profit price based on SL and Risk/Reward ratio
   double tp_price = ask_price + (sl_points * InpRiskRewardRatio * SymbolInfoDouble(_Symbol, SYMBOL_POINT));

   Print("Opening BUY: SL=", sl_price, " TP=", tp_price);
   trade.Buy(InpLotSize, _Symbol, ask_price, sl_price, tp_price, "Buy Breakout");
  }
//+------------------------------------------------------------------+
//| Open Sell Trade                                                  |
//| Executes a sell order with calculated SL and TP.                 |
//+------------------------------------------------------------------+
void OpenSellTrade(double sl_price, double bid_price)
  {
//--- Calculate Stop Loss distance in points
   double sl_points = (sl_price - bid_price) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
//--- Calculate Take Profit price based on SL and Risk/Reward ratio
   double tp_price = bid_price - (sl_points * InpRiskRewardRatio * SymbolInfoDouble(_Symbol, SYMBOL_POINT));

   Print("Opening SELL: SL=", sl_price, " TP=", tp_price);
   trade.Sell(InpLotSize, _Symbol, bid_price, sl_price, tp_price, "Sell Breakout");
  }
//+------------------------------------------------------------------+
//| Manage All Open Trades                                           |
//| Loops through all positions and applies management functions.    |
//+------------------------------------------------------------------+
void ManageTrades()
  {
//--- Loop backwards as we may be closing trades
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         //--- Make sure the position belongs to this EA and this symbol
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
           {
            //--- Apply breakeven and trailing stop logic
            ManageBreakeven(ticket);
            ManageTrailingStop(ticket);
           }
        }
     }
  }
//+------------------------------------------------------------------+
//| Manage Breakeven                                                 |
//| Moves the SL to entry price if profit reaches a certain level.   |
//+------------------------------------------------------------------+
void ManageBreakeven(ulong ticket)
  {
//--- Check if breakeven is enabled by the user
   if(InpBreakevenPips <= 0) return;

   double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
   double current_price;
   double sl = PositionGetDouble(POSITION_SL);
   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

   //--- Determine point multiplier for pip calculation based on broker digits
   double point_multiplier = (_Digits == 3 || _Digits == 5) ? 10 : 1;

   if(type == POSITION_TYPE_BUY)
     {
      current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      //--- Calculate profit in pips
      double pips_in_profit = (current_price - open_price) / (SymbolInfoDouble(_Symbol, SYMBOL_POINT) * point_multiplier);
      //--- If profit is sufficient and SL is not already at breakeven
      if(pips_in_profit >= InpBreakevenPips && sl != open_price)
        {
         Print("Breakeven triggered for BUY #", ticket);
         trade.PositionModify(ticket, open_price, PositionGetDouble(POSITION_TP));
        }
     }
   else if(type == POSITION_TYPE_SELL)
     {
      current_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      //--- Calculate profit in pips
      double pips_in_profit = (open_price - current_price) / (SymbolInfoDouble(_Symbol, SYMBOL_POINT) * point_multiplier);
      //--- If profit is sufficient and SL is not already at breakeven
      if(pips_in_profit >= InpBreakevenPips && sl != open_price)
        {
         Print("Breakeven triggered for SELL #", ticket);
         trade.PositionModify(ticket, open_price, PositionGetDouble(POSITION_TP));
        }
     }
  }
//+------------------------------------------------------------------+
//| Manage Trailing Stop                                             |
//| Adjusts the SL to lock in profits as the price moves favorably.  |
//+------------------------------------------------------------------+
void ManageTrailingStop(ulong ticket)
  {
//--- Check if trailing stop is enabled by the user
   if(InpTrailingStopPips <= 0) return;

   double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
   double current_price;
   double sl = PositionGetDouble(POSITION_SL);
   double tp = PositionGetDouble(POSITION_TP);
   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

   //--- Convert trailing stop pips to points
   double point_multiplier = (_Digits == 3 || _Digits == 5) ? 10 : 1;
   double trailing_stop_points = InpTrailingStopPips * point_multiplier * SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(type == POSITION_TYPE_BUY)
     {
      current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double new_sl = current_price - trailing_stop_points;
      //--- Ensure the new SL is higher than the old one and also above the entry price
      if(new_sl > sl && new_sl > open_price)
        {
         Print("Trailing stop updated for BUY #", ticket, " to ", new_sl);
         trade.PositionModify(ticket, new_sl, tp);
        }
     }
   else if(type == POSITION_TYPE_SELL)
     {
      current_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double new_sl = current_price + trailing_stop_points;
      //--- Ensure the new SL is lower than the old one and also below the entry price
      if(new_sl < sl && new_sl < open_price)
        {
         Print("Trailing stop updated for SELL #", ticket, " to ", new_sl);
         trade.PositionModify(ticket, new_sl, tp);
        }
     }
  }
//+------------------------------------------------------------------+
//| Close All Buy Trades                                             |
//| Closes all open BUY positions managed by this EA.                |
//+------------------------------------------------------------------+
void CloseAllBuyTrades()
  {
   int total = PositionsTotal();
   Print("Closing all BUY trades (", total, " total positions).");
   for(int i = total - 1; i >= 0; i--)
     {
      if(PositionSelect(i))
        {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
           {
            Print("Closing BUY #", PositionGetTicket(i));
            trade.PositionClose(PositionGetTicket(i));
           }
        }
     }
  }
//+------------------------------------------------------------------+
//| Close All Sell Trades                                            |
//| Closes all open SELL positions managed by this EA.               |
//+------------------------------------------------------------------+
void CloseAllSellTrades()
  {
   int total = PositionsTotal();
   Print("Closing all SELL trades (", total, " total positions).");
   for(int i = total - 1; i >= 0; i--)
     {
      if(PositionSelect(i))
        {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
           {
            Print("Closing SELL #", PositionGetTicket(i));
            trade.PositionClose(PositionGetTicket(i));
           }
        }
     }
  }
//+------------------------------------------------------------------+
