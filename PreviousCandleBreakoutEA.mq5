//+------------------------------------------------------------------+
//|                                     PreviousCandileBreakoutEA.mq5|
//|                                  Copyright 2024, MetaQuotes Ltd.|
//|                                              https://www.mql5.com|
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade/Trade.mqh>

//--- EA Inputs
input ulong InpMagicNumber = 12345; // Magic Number
input double InpLots = 0.01; // Lot Size
input int InpTakeProfitPips = 100; // Take Profit in Pips
input int InpBreakevenPips = 20; // Pips in profit to trigger breakeven
input int InpBreakevenBufferPips = 2; // Breakeven SL buffer in pips
input int InpTrailingStopPips = 50; // Trailing Stop in Pips
input int InpTrailingStopStepPips = 5; // Trailing Stop Step in Pips
input int InpMaxSpreadPips = 5; // Maximum allowed spread in pips
input int InpMaxOpenTrades = 10; // Maximum open trades
input bool InpCloseOnOppositeSignal = true; // Close trades on opposite signal
input int InpTradeStartTime = 8; // Trading start hour (24-hour format)
input int InpTradeEndTime = 20; // Trading end hour (24-hour format)

//--- Global Variables
CTrade trade;
double g_pip_value; // The value of a single pip in price terms

//--- Forward declarations for functions to be implemented later
void ManageOpenTrades();
void CheckForNewSignal();

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   //--- Initialize CTrade and set the magic number
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetMarginMode(); // Use the current symbol's margin mode

   //--- Calculate pip value for pip-based calculations
   g_pip_value = _Point;
   if(_Digits == 3 || _Digits == 5)
     {
      g_pip_value *= 10;
     }

   //--- Initialization successful
   Print("EA Initialized. Magic Number: ", InpMagicNumber, ". Pip Value: ", g_pip_value);
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   //--- Perform any necessary cleanup
   Print("EA Deinitialized. Reason code: ", reason);
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // --- Manage open trades on every tick for responsive SL/TP adjustments
   ManageOpenTrades();

   //--- Use a static variable to track the time of the last processed bar for signals
   static datetime last_bar_time = 0;

   //--- Get the time of the current bar
   MqlRates rates[1];
   if(CopyRates(_Symbol, _Period, 0, 1, rates) < 1)
     {
      Print("Error copying rates, can't continue.");
      return;
     }

   //--- If the current bar's time is the same as the last one, do not check for a new signal
   if(rates[0].time == last_bar_time)
     {
      return;
     }

   //--- A new bar has started, update the time and check for a new trade signal
   last_bar_time = rates[0].time;
   CheckForNewSignal();
  }
//+------------------------------------------------------------------+
//| Trade Management Logic                                           |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
   //--- Iterate through all open positions to manage them
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      //--- Select the position to work with
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         //--- Check if the position belongs to this EA
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
           {
            ManageBreakeven(ticket);
            ManageTrailingStop(ticket);
           }
        }
     }
}
//+------------------------------------------------------------------+
void ManageBreakeven(ulong ticket)
{
    //--- Ensure breakeven is enabled
    if(InpBreakevenPips <= 0) return;

    //--- Get position properties
    double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
    double current_sl = PositionGetDouble(POSITION_SL);
    double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
    ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

    //--- Calculate profit in pips
    double profit_pips = 0;
    if(type == POSITION_TYPE_BUY)
    {
        profit_pips = (current_price - open_price) / g_pip_value;
    }
    else // SELL
    {
        profit_pips = (open_price - current_price) / g_pip_value;
    }

    //--- Check if profit exceeds the breakeven trigger
    if(profit_pips >= InpBreakevenPips)
    {
        double new_sl = 0;
        if(type == POSITION_TYPE_BUY)
        {
            new_sl = open_price + (InpBreakevenBufferPips * g_pip_value);
            //--- Move SL only if it's not already at breakeven or better
            if(current_sl < new_sl)
            {
                trade.PositionModify(ticket, new_sl, PositionGetDouble(POSITION_TP));
            }
        }
        else // SELL
        {
            new_sl = open_price - (InpBreakevenBufferPips * g_pip_value);
            //--- Move SL only if it's not already at breakeven or better
            if(current_sl > new_sl || current_sl == 0)
            {
                trade.PositionModify(ticket, new_sl, PositionGetDouble(POSITION_TP));
            }
        }
    }
}
//+------------------------------------------------------------------+
void ManageTrailingStop(ulong ticket)
{
    //--- Ensure trailing stop is enabled
    if(InpTrailingStopPips <= 0) return;

    //--- Get position properties
    double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
    double current_sl = PositionGetDouble(POSITION_SL);
    double current_tp = PositionGetDouble(POSITION_TP);
    ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

    //--- Get current market prices
    MqlTick current_tick;
    if(!SymbolInfoTick(_Symbol, current_tick)) return;

    //--- Logic for BUY positions
    if(type == POSITION_TYPE_BUY)
    {
        //--- Check if the position is profitable enough to trail (use Bid price for SL)
        if(current_tick.bid > open_price + (InpTrailingStopPips * g_pip_value))
        {
            double new_sl = current_tick.bid - (InpTrailingStopPips * g_pip_value);
            //--- Move the stop only if the new level is better and meets the step requirement
            if(current_sl < new_sl)
            {
                // Check if the difference is greater than the step
                if(InpTrailingStopStepPips <= 0 || (new_sl - current_sl) / g_pip_value >= InpTrailingStopStepPips)
                {
                    trade.PositionModify(ticket, new_sl, current_tp);
                }
            }
        }
    }
    //--- Logic for SELL positions
    else
    {
        //--- Check if the position is profitable enough to trail (use Ask price for SL)
        if(current_tick.ask < open_price - (InpTrailingStopPips * g_pip_value))
        {
            double new_sl = current_tick.ask + (InpTrailingStopPips * g_pip_value);
            //--- Move the stop only if the new level is better and meets the step requirement
            if(current_sl > new_sl || current_sl == 0)
            {
                // Check if the difference is greater than the step
                if(InpTrailingStopStepPips <= 0 || (current_sl - new_sl) / g_pip_value >= InpTrailingStopStepPips)
                {
                    trade.PositionModify(ticket, new_sl, current_tp);
                }
            }
        }
    }
}
//+------------------------------------------------------------------+
//| Signal Logic                                                     |
//+------------------------------------------------------------------+
void CheckForNewSignal()
{
    //--- Get the previous candle data
    MqlRates prev_rates[1];
    if(CopyRates(_Symbol, _Period, 1, 1, prev_rates) < 1)
    {
        Print("Error copying previous rates, can't check for signal.");
        return;
    }
    double prev_high = prev_rates[0].high;
    double prev_low = prev_rates[0].low;

    //--- Get current market prices
    MqlTick current_tick;
    if(!SymbolInfoTick(_Symbol, current_tick))
    {
        Print("Error getting current tick, can't check for signal.");
        return;
    }
    double ask_price = current_tick.ask;
    double bid_price = current_tick.bid;

    //--- Initialize signal flags
    bool buy_signal = false;
    bool sell_signal = false;

    //--- Check for breakout signals
    if(ask_price > prev_high)
    {
        buy_signal = true;
    }
    if(bid_price < prev_low)
    {
        sell_signal = true;
    }

    //--- Handle closing trades on opposite signal
    if(InpCloseOnOppositeSignal)
    {
        if(buy_signal && PositionsTotal() > 0)
        {
            CloseAllSellTrades();
        }
        if(sell_signal && PositionsTotal() > 0)
        {
            CloseAllBuyTrades();
        }
    }

    //--- Risk Filters & Trade Execution
    if(IsSpreadOk() && !IsMaxTradesExceeded() && IsTradingTime())
    {
        if(buy_signal)
        {
            double sl = prev_low;
            double tp = ask_price + (InpTakeProfitPips * g_pip_value);
            trade.Buy(InpLots, _Symbol, ask_price, sl, tp, "Buy Signal");
        }
        else if(sell_signal)
        {
            double sl = prev_high;
            double tp = bid_price - (InpTakeProfitPips * g_pip_value);
            trade.Sell(InpLots, _Symbol, bid_price, sl, tp, "Sell Signal");
        }
    }
}
//+------------------------------------------------------------------+
//| Helper Functions                                                 |
//+------------------------------------------------------------------+
void CloseAllBuyTrades()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
            {
                if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                {
                    trade.PositionClose(ticket);
                }
            }
        }
    }
}
//+------------------------------------------------------------------+
void CloseAllSellTrades()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
            {
                if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
                {
                    trade.PositionClose(ticket);
                }
            }
        }
    }
}
//+------------------------------------------------------------------+
bool IsSpreadOk()
{
    long spread_points = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
    if(spread_points > InpMaxSpreadPips * (g_pip_value / _Point))
    {
        Print("Spread is too high: ", spread_points, " points.");
        return false;
    }
    return true;
}
//+------------------------------------------------------------------+
bool IsMaxTradesExceeded()
{
    int open_trades_count = 0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            // Count only positions opened by this EA instance on the current symbol
            if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
            {
                open_trades_count++;
            }
        }
    }

    if(open_trades_count >= InpMaxOpenTrades)
    {
        Print("Maximum number of trades (", InpMaxOpenTrades, ") for this EA reached.");
        return true; // Return TRUE because the limit is exceeded
    }

    return false; // Return FALSE because it's okay to open a new trade
}
//+------------------------------------------------------------------+
bool IsTradingTime()
{
    MqlDateTime current_time;
    TimeCurrent(current_time);
    int current_hour = current_time.hour;

    // Handle overnight sessions
    if(InpTradeStartTime > InpTradeEndTime)
    {
        if(current_hour >= InpTradeStartTime || current_hour < InpTradeEndTime)
            return true;
    }
    // Handle normal daytime sessions
    else
    {
        if(current_hour >= InpTradeStartTime && current_hour < InpTradeEndTime)
            return true;
    }

    Print("Outside of trading hours.");
    return false;
}
//+------------------------------------------------------------------+
