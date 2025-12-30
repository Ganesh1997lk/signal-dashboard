//+------------------------------------------------------------------+
//|                                                        EA.mq5 |
//|                        Copyright 2024, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>
CTrade trade;

//--- Input Parameters
input double LotSize = 0.01;
input int StopLoss = 50; // In points
input int TakeProfit = 100; // In points
input bool UseBreakeven = true;
input int BreakevenLevel = 10; // In points
input bool UseTrailingStop = true;
input int TrailingStop = 20; // In points

//--- Risk Management
input int MaxSpread = 20; // In points
input int MaxOpenTrades = 10;
input int TradingHourStart = 0; // 24-hour format
input int TradingHourEnd = 23;   // 24-hour format

//--- Event handling functions

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---

  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//--- Check for a new bar
   if(!IsNewBar())
      return;

//--- Gather Market Data
   MqlRates rates[];
   if(CopyRates(_Symbol, _Period, 1, 2, rates) < 2)
      return;

   double prev_high = rates[0].high;
   double prev_low = rates[0].low;

   MqlTick last_tick;
   SymbolInfoTick(_Symbol, last_tick);
   double ask = last_tick.ask;
   double bid = last_tick.bid;

//--- Check for trading signals
   bool buy_signal = CheckBuySignal(prev_high, prev_low, ask);
   bool sell_signal = CheckSellSignal(prev_high, prev_low, bid);

   if(buy_signal)
     {
      if(IsTradeAllowed())
        {
         CloseAllSellPositions();
         OpenBuyTrade(ask);
        }
     }

   if(sell_signal)
     {
      if(IsTradeAllowed())
        {
         CloseAllBuyPositions();
         OpenSellTrade(bid);
        }
     }

//--- Manage open trades
   ManageOpenTrades(bid, ask);
  }
//+------------------------------------------------------------------+
//| Check for a new bar                                              |
//+------------------------------------------------------------------+
bool IsNewBar()
  {
   static datetime last_bar_time = 0;
   datetime current_bar_time = iTime(_Symbol, _Period, 0);

   if(last_bar_time != current_bar_time)
     {
      last_bar_time = current_bar_time;
      return(true);
     }
   return(false);
  }
//+------------------------------------------------------------------+
//| Check if trading is allowed                                      |
//+------------------------------------------------------------------+
bool IsTradeAllowed()
  {
//--- Spread filter
   if((SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > MaxSpread) && (MaxSpread > 0))
     {
      Print("Spread is too high. Current spread: ", SymbolInfoInteger(_Symbol, SYMBOL_SPREAD));
      return(false);
     }

//--- Max open trades filter
   if(PositionsTotal() >= MaxOpenTrades)
     {
      Print("Maximum number of trades reached.");
      return(false);
     }

//--- Time filter
   MqlDateTime time;
   TimeCurrent(time);
   if(time.hour < TradingHourStart || time.hour >= TradingHourEnd)
     {
      Print("Trading is not allowed at this time.");
      return(false);
     }

   return(true);
  }
//+------------------------------------------------------------------+
//| Close all buy positions                                          |
//+------------------------------------------------------------------+
void CloseAllBuyPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelect(ticket))
        {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
           {
            trade.PositionClose(ticket);
           }
        }
     }
  }
//+------------------------------------------------------------------+
//| Close all sell positions                                         |
//+------------------------------------------------------------------+
void CloseAllSellPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelect(ticket))
        {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
           {
            trade.PositionClose(ticket);
           }
        }
     }
  }
//+------------------------------------------------------------------+
//| Manage open trades                                               |
//+------------------------------------------------------------------+
void ManageOpenTrades(double bid, double ask)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelect(ticket))
        {
         if(PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;

         long type = PositionGetInteger(POSITION_TYPE);
         double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl = PositionGetDouble(POSITION_SL);

         if(type == POSITION_TYPE_BUY)
           {
            //--- Breakeven
            if(UseBreakeven && bid > open_price + BreakevenLevel * _Point && sl < open_price)
              {
               trade.PositionModify(ticket, open_price, PositionGetDouble(POSITION_TP));
              }
            //--- Trailing Stop
            if(UseTrailingStop && (sl == 0 || sl < bid - TrailingStop * _Point))
              {
               trade.PositionModify(ticket, bid - TrailingStop * _Point, PositionGetDouble(POSITION_TP));
              }
           }
         else if(type == POSITION_TYPE_SELL)
           {
            //--- Breakeven
            if(UseBreakeven && ask < open_price - BreakevenLevel * _Point && sl > open_price)
              {
               trade.PositionModify(ticket, open_price, PositionGetDouble(POSITION_TP));
              }
            //--- Trailing Stop
            if(UseTrailingStop && (sl == 0 || sl > ask + TrailingStop * _Point))
              {
               trade.PositionModify(ticket, ask + TrailingStop * _Point, PositionGetDouble(POSITION_TP));
              }
           }
        }
     }
  }
//+------------------------------------------------------------------+
//| Open a buy trade                                                 |
//+------------------------------------------------------------------+
void OpenBuyTrade(double price)
  {
   double sl = price - StopLoss * _Point;
   double tp = price + TakeProfit * _Point;
   trade.Buy(LotSize, _Symbol, price, sl, tp);
  }
//+------------------------------------------------------------------+
//| Open a sell trade                                                |
//+------------------------------------------------------------------+
void OpenSellTrade(double price)
  {
   double sl = price + StopLoss * _Point;
   double tp = price - TakeProfit * _Point;
   trade.Sell(LotSize, _Symbol, price, sl, tp);
  }
//+------------------------------------------------------------------+
//| Check for buy signal                                             |
//+------------------------------------------------------------------+
bool CheckBuySignal(double prev_high, double prev_low, double current_ask)
  {
   if(current_ask > prev_high)
      return(true);
   return(false);
  }
//+------------------------------------------------------------------+
//| Check for sell signal                                            |
//+------------------------------------------------------------------+
bool CheckSellSignal(double prev_high, double prev_low, double current_bid)
  {
   if(current_bid < prev_low)
      return(true);
   return(false);
  }
//+------------------------------------------------------------------+
