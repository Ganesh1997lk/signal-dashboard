//+------------------------------------------------------------------+
//|                                     PreviousCandleBreakEA.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade/Trade.mqh>

//--- Input parameters
input double InpLots          = 0.1;  // Lot Size
input int    InpStopLoss      = 0;   // Stop Loss (in points) - 0 means use previous candle
input int    InpTakeProfit    = 0;   // Take Profit (in points) - 0 means use 1:2 ratio
input int    InpBreakeven     = 10;   // Breakeven (in points)
input int    InpTrailingStop  = 0;   // Trailing Stop (in points) - 0 means disabled
input int    InpMaxSpread     = 20;  // Max Spread (in points)
input int    InpMaxTrades     = 5;   // Max Open Trades
input int    InpTradingHourStart = 0;   // Trading Hour Start
input int    InpTradingHourEnd   = 23;  // Trading Hour End
input int    InpMagicNumber   = 12345; // Magic Number

//--- Global variables
CTrade trade;
bool   isNewBar     = false;
double g_prevHigh   = 0;
double g_prevLow    = 0;
double g_currentAsk = 0;
double g_currentBid = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetMarginMode();
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
//--- Fetch latest market data on every tick
   FetchMarketData();

//--- Manage open trades on every tick
   ManageOpenTrades();

//--- Check for a new bar for entry/exit signals
   CheckForNewBar();
   if(!isNewBar)
     {
      return;
     }

//--- Main logic for new bars
   HandleOppositeSignals();
   CheckForNewTrades();
  }

//+------------------------------------------------------------------+
//| Fetch Market Data                                                |
//+------------------------------------------------------------------+
void FetchMarketData()
  {
//--- Get previous candle data
   MqlRates rates[];
   if(CopyRates(_Symbol, _Period, 1, 1, rates) > 0)
     {
      g_prevHigh = rates[0].high;
      g_prevLow = rates[0].low;
     }

//--- Get current prices
   MqlTick last_tick;
   SymbolInfoTick(_Symbol, last_tick);
   g_currentAsk = last_tick.ask;
   g_currentBid = last_tick.bid;
  }

//+------------------------------------------------------------------+
//| Manage Open Trades                                               |
//+------------------------------------------------------------------+
void ManageOpenTrades()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
        {
         //--- Breakeven
         if(InpBreakeven > 0)
           {
            HandleBreakeven(i);
           }
         //--- Trailing Stop
         if(InpTrailingStop > 0)
           {
            HandleTrailingStop(i);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Handle Breakeven                                                 |
//+------------------------------------------------------------------+
void HandleBreakeven(int index)
  {
   long ticket = PositionGetTicket(index);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl = PositionGetDouble(POSITION_SL);
   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

   MqlTick last_tick;
   SymbolInfoTick(_Symbol, last_tick);

   if(type == POSITION_TYPE_BUY)
     {
      if(last_tick.bid > openPrice + (InpBreakeven * _Point) && sl < openPrice)
        {
         trade.PositionModify(ticket, openPrice, PositionGetDouble(POSITION_TP));
        }
     }
   else if(type == POSITION_TYPE_SELL)
     {
      if(last_tick.ask < openPrice - (InpBreakeven * _Point) && (sl > openPrice || sl == 0))
        {
         trade.PositionModify(ticket, openPrice, PositionGetDouble(POSITION_TP));
        }
     }
  }

//+------------------------------------------------------------------+
//| Handle Trailing Stop                                             |
//+------------------------------------------------------------------+
void HandleTrailingStop(int index)
  {
   long ticket = PositionGetTicket(index);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSL = PositionGetDouble(POSITION_SL);
   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

   MqlTick last_tick;
   SymbolInfoTick(_Symbol, last_tick);

   if(type == POSITION_TYPE_BUY)
     {
      double newSL = last_tick.bid - (InpTrailingStop * _Point);
      if(newSL > openPrice && newSL > currentSL)
        {
         trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
        }
     }
   else if(type == POSITION_TYPE_SELL)
     {
      double newSL = last_tick.ask + (InpTrailingStop * _Point);
      if(newSL < openPrice && (newSL < currentSL || currentSL == 0))
        {
         trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
        }
     }
  }
//+------------------------------------------------------------------+
//| Check for new trades                                             |
//+------------------------------------------------------------------+
void CheckForNewTrades()
  {
//--- Risk Filters
// Spread Check
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpread)
     {
      return;
     }

// Max Trades Check
   if(CountOpenTrades() >= InpMaxTrades)
     {
      return;
     }

// Time Filter Check
   MqlDateTime time;
   TimeCurrent(time);
   if(time.hour < InpTradingHourStart || time.hour > InpTradingHourEnd)
     {
      return;
     }

//--- Check for buy signal
   if(g_currentAsk > g_prevHigh)
     {
      //--- Open buy trade
      ExecuteBuyTrade(g_prevLow);
     }
//--- Check for sell signal
   else if(g_currentBid < g_prevLow)
     {
      //--- Open sell trade
      ExecuteSellTrade(g_prevHigh);
     }
  }

//+------------------------------------------------------------------+
//| Count Open Trades                                                |
//+------------------------------------------------------------------+
int CountOpenTrades()
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
        {
         count++;
        }
     }
   return count;
  }

//+------------------------------------------------------------------+
//| Execute Buy Trade                                                |
//+------------------------------------------------------------------+
void ExecuteBuyTrade(double stopLossPrice)
  {
   MqlTick last_tick;
   SymbolInfoTick(_Symbol, last_tick);
   double currentAsk = last_tick.ask;

   double sl = stopLossPrice;
   double risk = currentAsk - sl;
   double tp = currentAsk + (risk * 2);

   if(InpStopLoss > 0)
     {
      sl = currentAsk - (InpStopLoss * _Point);
     }
   if(InpTakeProfit > 0)
     {
      tp = currentAsk + (InpTakeProfit * _Point);
     }

   trade.Buy(InpLots, _Symbol, currentAsk, sl, tp, "Buy Trade");
  }

//+------------------------------------------------------------------+
//| Execute Sell Trade                                               |
//+------------------------------------------------------------------+
void ExecuteSellTrade(double stopLossPrice)
  {
   MqlTick last_tick;
   SymbolInfoTick(_Symbol, last_tick);
   double currentBid = last_tick.bid;

   double sl = stopLossPrice;
   double risk = sl - currentBid;
   double tp = currentBid - (risk * 2);

   if(InpStopLoss > 0)
     {
      sl = currentBid + (InpStopLoss * _Point);
     }
   if(InpTakeProfit > 0)
     {
      tp = currentBid - (InpTakeProfit * _Point);
     }

   trade.Sell(InpLots, _Symbol, currentBid, sl, tp, "Sell Trade");
  }
//| Handle Opposite Signals                                          |
//+------------------------------------------------------------------+
void HandleOppositeSignals()
  {
//--- Define signals
   bool buySignal = (g_currentAsk > g_prevHigh);
   bool sellSignal = (g_currentBid < g_prevLow);

//--- Close opposite trades
   if(buySignal)
     {
      CloseAllSellTrades();
     }

   if(sellSignal)
     {
      CloseAllBuyTrades();
     }
  }

//+------------------------------------------------------------------+
//| Close all buy trades                                             |
//+------------------------------------------------------------------+
void CloseAllBuyTrades()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
        {
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
           {
            trade.PositionClose(PositionGetTicket(i));
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Close all sell trades                                            |
//+------------------------------------------------------------------+
void CloseAllSellTrades()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
        {
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
           {
            trade.PositionClose(PositionGetTicket(i));
           }
        }
     }
  }
//+------------------------------------------------------------------+
//| Check for a new bar                                              |
//+------------------------------------------------------------------+
void CheckForNewBar()
  {
   static datetime lastBarTime = 0;
   datetime currentBarTime = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);

   if(lastBarTime != currentBarTime)
     {
      isNewBar = true;
      lastBarTime = currentBarTime;
     }
   else
     {
      isNewBar = false;
     }
  }
//+------------------------------------------------------------------+
