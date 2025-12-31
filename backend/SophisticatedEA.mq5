//+------------------------------------------------------------------+
//|                                          SophisticatedEA.mq5 |
//|                        Copyright 2023, Your Name/Company |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, Your Name/Company"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property description "A sophisticated Expert Advisor based on a detailed flowchart."

//--- Include Trade library
#include <Trade/Trade.mqh>

//--- EA Inputs
input double InpLots          = 0.01;    // Lot Size
input int    InpStopLoss      = 50;      // Stop Loss (in pips)
input int    InpTakeProfit    = 100;     // Take Profit (in pips)
input int    InpBreakeven     = 30;      // Breakeven activation (in pips)
input int    InpTrailingStop  = 20;      // Trailing Stop (in pips)
input int    InpMaxSpread     = 20;      // Maximum allowed spread (in points)
input int    InpMaxTrades     = 10;      // Maximum open trades
input string InpStartTime     = "00:00"; // Trading Start Time
input string InpEndTime       = "23:59"; // Trading End Time
input double InpBasketTakeProfit = 200.0;   // Basket Take Profit in deposit currency
input long   InpMagicNumber   = 12345;   // Magic Number

//--- Global variables
CTrade trade;
bool isNewBar = false;
double pointMultiplier = 1.0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- Initialize trade object
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetMarginMode();
   trade.SetTypeFillingBySymbol(_Symbol);

//--- Determine the point multiplier for pip calculations
   if(_Digits == 5 || _Digits == 3)
     {
      pointMultiplier = 10;
     }

   Print("EA Initialized. Parameters:");
   Print("Lot Size: ", InpLots);
   Print("Stop Loss: ", InpStopLoss, " pips");
   Print("Take Profit: ", InpTakeProfit, " pips");
   Print("Breakeven: ", InpBreakeven, " pips");
   Print("Trailing Stop: ", InpTrailingStop, " pips");

   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Print("EA Deinitialized. Reason code: ", reason);
  }
//+------------------------------------------------------------------+
//| Manage Open Trades                                               |
//+------------------------------------------------------------------+
void ManageOpenTrades()
  {
   // Basket TP Check
   if(InpBasketTakeProfit > 0 && CheckBasketTP())
     {
      CloseAllTrades();
      return; // Exit after closing all trades
     }

   if(InpBreakeven <= 0 && InpTrailingStop <= 0) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
           {
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
            double sl = PositionGetDouble(POSITION_SL);
            long positionType = PositionGetInteger(POSITION_TYPE);

            //--- Breakeven Logic
            if(InpBreakeven > 0)
              {
               if(positionType == POSITION_TYPE_BUY)
                 {
                  if(currentPrice > openPrice + InpBreakeven * _Point * pointMultiplier && sl < openPrice)
                    {
                     trade.PositionModify(ticket, openPrice, PositionGetDouble(POSITION_TP));
                    }
                 }
               else if(positionType == POSITION_TYPE_SELL)
                 {
                  if(currentPrice < openPrice - InpBreakeven * _Point * pointMultiplier && sl > openPrice)
                    {
                     trade.PositionModify(ticket, openPrice, PositionGetDouble(POSITION_TP));
                    }
                 }
              }

            //--- Trailing Stop Logic
            if(InpTrailingStop > 0)
              {
               if(positionType == POSITION_TYPE_BUY)
                 {
                  double newSL = SymbolInfoDouble(_Symbol, SYMBOL_BID) - InpTrailingStop * _Point * pointMultiplier;
                  if(sl < newSL && (newSL > openPrice || sl==0))
                    {
                     trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
                    }
                 }
               else if(positionType == POSITION_TYPE_SELL)
                 {
                  double newSL = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + InpTrailingStop * _Point * pointMultiplier;
                  if(sl > newSL && (newSL < openPrice || sl==0))
                    {
                     trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
                    }
                 }
              }
           }
        }
     }
  }
//+------------------------------------------------------------------+
//| Close All Trades                                                 |
//+------------------------------------------------------------------+
void CloseAllTrades()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
           {
            trade.PositionClose(ticket);
           }
        }
     }
  }
//+------------------------------------------------------------------+
//| Check Basket Take Profit                                         |
//+------------------------------------------------------------------+
bool CheckBasketTP()
  {
   double totalProfit = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
           {
            totalProfit += PositionGetDouble(POSITION_PROFIT);
           }
        }
     }

   return totalProfit >= InpBasketTakeProfit;
  }
//+------------------------------------------------------------------+
//| Close All Buy Trades                                             |
//+------------------------------------------------------------------+
void CloseAllBuyTrades()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
           {
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
              {
               trade.PositionClose(ticket);
              }
           }
        }
     }
  }
//+------------------------------------------------------------------+
//| Close All Sell Trades                                            |
//+------------------------------------------------------------------+
void CloseAllSellTrades()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
           {
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
              {
               trade.PositionClose(ticket);
              }
           }
        }
     }
  }
//+------------------------------------------------------------------+
//| Forward declarations                                             |
//+------------------------------------------------------------------+
void CollectMarketData();
bool CheckBuyCondition();
bool CheckSellCondition();
void OpenBuyTrade();
void OpenSellTrade();
void ManageOpenTrades();
void CloseAllBuyTrades();
void CloseAllSellTrades();
void CloseAllTrades();
bool CheckBasketTP();

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//--- New bar detection
   static datetime lastBarTime=0;
   datetime currentBarTime=(datetime)SeriesInfoInteger(_Symbol,_Period,SERIES_LAST_BAR_TIME);
   isNewBar=false;
   if(lastBarTime<currentBarTime)
     {
      isNewBar=true;
      lastBarTime=currentBarTime;
     }

//--- Manage open trades on every tick
   ManageOpenTrades();

//--- Only execute trading logic on a new bar
   if(!isNewBar)
     {
      return;
     }

//--- Trading Logic on New Bar ---
// 1. Collect market data
   CollectMarketData();

// 2. Check for trading signals
   bool buySignal=CheckBuyCondition();
   bool sellSignal=CheckSellCondition();

// 3. Execute trades based on signals
   if(buySignal && sellSignal) return; // Ignore conflicting signals for now

   if(buySignal)
     {
      // As per requirement 12, close all sell trades before opening a buy trade
      CloseAllSellTrades();
      OpenBuyTrade();
     }
   else if(sellSignal)
     {
      // As per requirement 12, close all buy trades before opening a sell trade
      CloseAllBuyTrades();
      OpenSellTrade();
     }
  }
//+------------------------------------------------------------------+
//| Market Data Collection                                           |
//+------------------------------------------------------------------+
void CollectMarketData()
  {
   // To be implemented: Logic for collecting prices, indicator values, etc.
   Print("Collecting market data...");
  }
//+------------------------------------------------------------------+
//| Buy Condition Check                                              |
//+------------------------------------------------------------------+
bool CheckBuyCondition()
  {
   // To be implemented: Replace with actual buy signal logic
   // For now, let's use a placeholder (e.g., price crossing above a moving average)
   MqlRates rates[];
   if(CopyRates(_Symbol, _Period, 1, 2, rates) < 2) return false;
   // Previous candle closed above its open (bullish)
   if(rates[0].close > rates[0].open)
     {
      Print("Buy Signal Detected.");
      return true;
     }
   return false;
  }
//+------------------------------------------------------------------+
//| Sell Condition Check                                             |
//+------------------------------------------------------------------+
bool CheckSellCondition()
  {
   // To be implemented: Replace with actual sell signal logic
   // For now, let's use a placeholder (e.g., price crossing below a moving average)
   MqlRates rates[];
   if(CopyRates(_Symbol, _Period, 1, 2, rates) < 2) return false;
   // Previous candle closed below its open (bearish)
   if(rates[0].close < rates[0].open)
     {
      Print("Sell Signal Detected.");
      return true;
     }
   return false;
  }
//+------------------------------------------------------------------+
//| Risk Filter Checks                                               |
//+------------------------------------------------------------------+
bool CheckRiskFilters()
  {
//--- Spread check
   if(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > InpMaxSpread)
     {
      Print("Spread is too high: ", SymbolInfoInteger(_Symbol, SYMBOL_SPREAD));
      return false;
     }
//--- Max trades check
   if(PositionsTotal() >= InpMaxTrades)
     {
      Print("Maximum number of trades reached: ", PositionsTotal());
      return false;
     }
//--- Time filter check
   MqlDateTime currentTime;
   TimeCurrent(currentTime);
   int startTime = StringToInteger(StringSubstr(InpStartTime, 0, 2)) * 60 + StringToInteger(StringSubstr(InpStartTime, 3, 2));
   int endTime = StringToInteger(StringSubstr(InpEndTime, 0, 2)) * 60 + StringToInteger(StringSubstr(InpEndTime, 3, 2));
   int nowTime = currentTime.hour * 60 + currentTime.min;

   if(startTime < endTime) // Normal day
     {
      if(nowTime < startTime || nowTime > endTime)
        {
         Print("Outside of trading hours.");
         return false;
        }
     }
   else // Overnight session
     {
      if(nowTime > endTime && nowTime < startTime)
        {
         Print("Outside of trading hours (overnight session).");
         return false;
        }
     }

   return true;
  }
//+------------------------------------------------------------------+
//| Open Buy Trade                                                   |
//+------------------------------------------------------------------+
void OpenBuyTrade()
  {
   if(!CheckRiskFilters()) return;

   double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl = price - InpStopLoss * _Point * pointMultiplier;
   double tp = price + InpTakeProfit * _Point * pointMultiplier;

   if(InpStopLoss == 0) sl = 0;
   if(InpTakeProfit == 0) tp = 0;

   MqlTradeResult result;
   if(!trade.Buy(InpLots, _Symbol, price, sl, tp, "Buy Trade"))
     {
      Print("Error opening buy order: ", GetLastError());
     }
   else
     {
      Print("Buy order opened successfully. Ticket: ", trade.ResultOrder());
     }
  }
//+------------------------------------------------------------------+
//| Open Sell Trade                                                  |
//+------------------------------------------------------------------+
void OpenSellTrade()
  {
   if(!CheckRiskFilters()) return;

   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = price + InpStopLoss * _Point * pointMultiplier;
   double tp = price - InpTakeProfit * _Point * pointMultiplier;

   if(InpStopLoss == 0) sl = 0;
   if(InpTakeProfit == 0) tp = 0;

   MqlTradeResult result;
   if(!trade.Sell(InpLots, _Symbol, price, sl, tp, "Sell Trade"))
     {
      Print("Error opening sell order: ", GetLastError());
     }
   else
     {
      Print("Sell order opened successfully. Ticket: ", trade.ResultOrder());
     }
  }
//+------------------------------------------------------------------+
