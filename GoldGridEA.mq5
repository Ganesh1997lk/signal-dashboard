//+------------------------------------------------------------------+
//|                                                   GoldGridEA.mq5 |
//|                                  Copyright 2023, Your Name Here |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, Your Name Here"
#property link      "https://www.mql5.com"
#property version   "1.20" // Version updated after panel removal

// --- EA Input Parameters ---
sgroup "Grid Settings"
input int      GridDistance      = 500;    // Grid Distance in Points
input double   TakeProfit        = 500;    // Take Profit in Points

sgroup "Lot Sizing Settings"
input double   BalanceForLotStep = 10000;  // Balance required for each 0.01 lot step

sgroup "Risk Management"
input double   GlobalSL_Percent  = 30.0;   // Equity Drawdown % to Close All Positions

sgroup "EA Identification"
input int      MagicNumber       = 140425; // EA's Unique Magic Number
input string   OrderComment      = "GoldGridEA"; // Comment for trades

sgroup "Filters"
input bool     UseNewsFilter     = true;   // Enable/Disable News Filter
input int      MinutesBeforeNews = 120;    // Minutes to stop trading before High-Impact News
input int      MinutesAfterNews  = 120;    // Minutes to resume trading after High-Impact News
input bool     UseHolidayFilter  = true;   // Avoid trading during Holiday period
input int      HolidayStartMonth = 12;     // Month to start holiday filter
input int      HolidayStartDay   = 24;     // Day to start holiday filter
input int      HolidayEndMonth   = 1;      // Month to end holiday filter
input int      HolidayEndDay     = 5;      // Day to end holiday filter

// --- Include necessary libraries ---
#include <Trade\Trade.mqh>

// --- Global Variables ---
CTrade trade; // Trade object for executing orders
double g_last_buy_price = 0; // Global variable for last buy price
double g_last_sell_price = 0; // Global variable for last sell price
bool   g_is_news_time = false; // Global flag for news events

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("EA Initializing...");
   InitializeGridState();
   EventSetTimer(60); // Set a timer for once per minute
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Print("EA Deinitializing...");
   EventKillTimer();
  }

//+------------------------------------------------------------------+
//| Timer event function                                             |
//+------------------------------------------------------------------+
void OnTimer()
  {
   // This function is called once per minute
   CheckNewsEvents();
  }

//+------------------------------------------------------------------+
//| Scans for existing positions to initialize the grid state        |
//+------------------------------------------------------------------+
void InitializeGridState()
  {
   long lastBuyTime = 0;
   long lastSellTime = 0;

   // Find the most recent buy and sell trades to set initial state
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
         long current_pos_time = PositionGetInteger(POSITION_TIME);
         if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
           {
            if(current_pos_time > lastBuyTime)
              {
               g_last_buy_price = PositionGetDouble(POSITION_PRICE_OPEN);
               lastBuyTime = current_pos_time;
              }
           }
         else // SELL
           {
            if(current_pos_time > lastSellTime)
              {
               g_last_sell_price = PositionGetDouble(POSITION_PRICE_OPEN);
               lastSellTime = current_pos_time;
              }
           }
        }
     }
   PrintFormat("Initialized Grid State: Last Buy @ %.5f, Last Sell @ %.5f", g_last_buy_price, g_last_sell_price);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // --- 1. Risk Management Check ---
   CheckGlobalStopLoss();

   // --- 2. Filter Checks ---
   if(!IsTradingAllowed())
     {
      return; // Stop further execution if trading is not allowed
     }

   // --- 3. Get Symbol Information ---
   MqlTick latest_tick;
   SymbolInfoTick(_Symbol, latest_tick);
   double ask_price = NormalizeDouble(latest_tick.ask, _Digits);
   double bid_price = NormalizeDouble(latest_tick.bid, _Digits);

   // --- 4. Core Grid Logic ---
   if(PositionsTotal() == 0)
     {
      // --- No positions, start the initial grid ---
      double lot = CalculateLotSize();
      if(trade.Buy(lot, _Symbol, ask_price, 0, ask_price + TakeProfit * _Point, OrderComment))
        g_last_buy_price = ask_price;
      if(trade.Sell(lot, _Symbol, bid_price, 0, bid_price - TakeProfit * _Point, OrderComment))
        g_last_sell_price = bid_price;
     }
   else
     {
      // --- Positions exist, manage the grid ---
      double lot = CalculateLotSize();

      // Buy Condition: Price dropped below the last buy by GridDistance
      if(g_last_buy_price > 0 && ask_price < g_last_buy_price - (GridDistance * _Point))
        {
         if(trade.Buy(lot, _Symbol, ask_price, 0, ask_price + TakeProfit * _Point, OrderComment))
            g_last_buy_price = ask_price;
        }

      // Sell Condition: Price rose above the last sell by GridDistance
      if(g_last_sell_price > 0 && bid_price > g_last_sell_price + (GridDistance * _Point))
        {
         if(trade.Sell(lot, _Symbol, bid_price, 0, bid_price - TakeProfit * _Point, OrderComment))
            g_last_sell_price = bid_price;
        }
     }
  }

//+------------------------------------------------------------------+
//| Checks if trading is allowed based on filters (News, Holidays)   |
//+------------------------------------------------------------------+
bool IsTradingAllowed()
  {
   // --- Holiday Filter ---
   if(UseHolidayFilter)
     {
      MqlDateTime current_time;
      TimeCurrent(current_time);
      // Check for user-defined holiday period
      if((current_time.mon == HolidayStartMonth && current_time.day >= HolidayStartDay) ||
         (current_time.mon == HolidayEndMonth && current_time.day <= HolidayEndDay))
        {
         return false;
        }
     }

   // --- News Filter ---
   if(UseNewsFilter && g_is_news_time)
     {
      return false;
     }

   return true; // Trading is allowed
  }

//+------------------------------------------------------------------+
//| Checks for upcoming news events (called by OnTimer)              |
//+------------------------------------------------------------------+
void CheckNewsEvents()
  {
   if(!UseNewsFilter)
     {
      g_is_news_time = false;
      return;
     }

   datetime from = TimeCurrent();
   datetime to = from + (MinutesAfterNews * 60);

   string symbol_currency_base = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
   string symbol_currency_profit = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);

   MqlCalendarValue values[];
   if(CalendarValueHistory(values, from, to))
     {
      for(int i = 0; i < ArraySize(values); i++)
        {
         if(values[i].importance == CALENDAR_IMPORTANCE_HIGH)
           {
            if(StringFind(values[i].currency, symbol_currency_base) != -1 || StringFind(values[i].currency, symbol_currency_profit) != -1)
              {
               datetime event_time = values[i].time;
               if(TimeCurrent() >= event_time - (MinutesBeforeNews * 60) && TimeCurrent() <= event_time + (MinutesAfterNews * 60))
                 {
                  if(!g_is_news_time)
                     PrintFormat("News filter activated: Pausing trading due to high-impact event (%s) at %s.", values[i].event, TimeToString(event_time));
                  g_is_news_time = true;
                  return;
                 }
              }
           }
        }
     }

   if(g_is_news_time)
      Print("News filter deactivated: Resuming trading.");
   g_is_news_time = false;
  }

//+------------------------------------------------------------------+
//| Check and manage the global equity stop loss                     |
//+------------------------------------------------------------------+
void CheckGlobalStopLoss()
  {
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   if(balance <= 0) return;

   double drawdown_percent = (balance - equity) / balance * 100.0;

   if(drawdown_percent >= GlobalSL_Percent)
     {
      PrintFormat("Global Stop Loss triggered! Drawdown: %.2f%%. Closing all positions.", drawdown_percent);
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
           {
            trade.PositionClose(PositionGetTicket(i));
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Calculate Lot Size based on Account Balance                      |
//+------------------------------------------------------------------+
double CalculateLotSize()
  {
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double calculated_lot = NormalizeDouble(balance / BalanceForLotStep, 2);

   double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lot_step > 0)
     {
      calculated_lot = floor(calculated_lot / lot_step) * lot_step;
     }

   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(calculated_lot < min_lot)
     {
      calculated_lot = min_lot;
     }

   return calculated_lot;
  }
//+------------------------------------------------------------------+
