//+------------------------------------------------------------------+
//|                                     PreviousCandleBreakout.mq5 |
//|                        Copyright 2023, YOUR_NAME_HERE |
//|                                      https://www.example.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, YOUR_NAME_HERE"
#property link      "https.www.example.com"
#property version   "1.00"

//--- Include libraries
#include <Trade/Trade.mqh>

//--- EA Inputs
input double InpLotSize = 0.01;
input double InpRiskRewardRatio = 2.0;
input int    InpBreakevenPips = 20;
input int    InpTrailingStopPips = 20;
input int    InpMaxSpreadPips = 2;
input int    InpMaxOpenTrades = 5;
input string InpTradingStartTime = "00:00";
input string InpTradingEndTime = "23:59";
input int    InpMagicNumber = 12345;

//--- Global variables
CTrade trade;
double g_point_multiplier = 1.0;
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    //--- Initialize trade object
    trade.SetExpertMagicNumber(InpMagicNumber);
    trade.SetMarginMode(ACCOUNT_MARGIN_MODE_RETAIL_NETTING);
    trade.SetTypeFilling(ORDER_FILLING_FOK);

    //--- Initialize point multiplier for pip calculations
    if(_Digits == 5 || _Digits == 3)
    {
        g_point_multiplier = 10.0;
    }
    else
    {
        g_point_multiplier = 1.0;
    }

    //--- Initialization successful
    return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    //--- Cleanup if needed
}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    //--- New bar detection
    static datetime last_bar_time = 0;
    datetime current_bar_time = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LAST_BAR_TIME);
    if(last_bar_time >= current_bar_time)
    {
        return; //--- Not a new bar, exit
    }
    last_bar_time = current_bar_time;

    //--- Fetch market data
    MqlRates rates[];
    //--- Request 3 bars starting from the current bar (index 0).
    //--- CopyRates orders data from oldest to newest.
    //--- rates[0] = candle [2] (oldest)
    //--- rates[1] = candle [1] (previous)
    //--- rates[2] = candle [0] (current, forming bar)
    if(CopyRates(_Symbol, _Period, 0, 3, rates) < 3)
    {
        Print("Failed to get rates history. Not enough bars.");
        return;
    }

    //--- Correctly assign candle data based on CopyRates behavior (oldest to newest)
    double candle1_close = rates[1].close;
    double candle2_high = rates[0].high;
    double candle2_low = rates[0].low;

    //--- Trade Logic
    CheckBuySignal(candle1_close, candle2_high, rates[1].low);
    CheckSellSignal(candle1_close, candle2_low, rates[1].high);

    //--- Manage open trades
    ManageOpenTrades();
}
//+------------------------------------------------------------------+
//| Check for buy signal and execute trade                           |
//+------------------------------------------------------------------+
void CheckBuySignal(double p_candle1_close, double p_candle2_high, double p_signal_candle_low)
{
    if(p_candle1_close > p_candle2_high)
    {
        CloseAllSellTrades();
        if(CheckRiskFilters())
        {
            OpenBuy(p_signal_candle_low);
        }
    }
}
//+------------------------------------------------------------------+
//| Manage all open trades                                           |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        //--- Only manage trades for the current symbol
        if(PositionGetSymbol(i) == _Symbol)
        {
            ulong ticket = PositionGetTicket(i);
            //--- Select the position to work with its properties
            if(PositionSelectByTicket(ticket))
            {
                ManageBreakeven(ticket);
                ManageTrailingStop(ticket);
            }
        }
    }
}
//+------------------------------------------------------------------+
//| Manage Breakeven                                                 |
//+------------------------------------------------------------------+
void ManageBreakeven(ulong p_ticket)
{
    if(InpBreakevenPips <= 0) return;

    //--- Position is already selected by ManageOpenTrades()
    double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
    double sl = PositionGetDouble(POSITION_SL);
    ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

    double breakeven_level = InpBreakevenPips * _Point * g_point_multiplier;

    if(type == POSITION_TYPE_BUY)
    {
        //--- Profit for a BUY is checked against the BID price
        double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        if(current_price > open_price + breakeven_level && sl != open_price)
        {
            trade.PositionModify(p_ticket, open_price, PositionGetDouble(POSITION_TP));
        }
    }
    else if(type == POSITION_TYPE_SELL)
    {
        //--- Profit for a SELL is checked against the ASK price
        double current_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        if(current_price < open_price - breakeven_level && sl != open_price)
        {
            trade.PositionModify(p_ticket, open_price, PositionGetDouble(POSITION_TP));
        }
    }
}
//+------------------------------------------------------------------+
//| Manage Trailing Stop                                             |
//+------------------------------------------------------------------+
void ManageTrailingStop(ulong p_ticket)
{
    if(InpTrailingStopPips <= 0) return;

    //--- Position is already selected by ManageOpenTrades()
    double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
    double sl = PositionGetDouble(POSITION_SL);
    ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

    double trailing_stop_dist = InpTrailingStopPips * _Point * g_point_multiplier;

    if(type == POSITION_TYPE_BUY)
    {
        //--- For a BUY position, SL is triggered by the BID price
        double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        double new_sl = current_price - trailing_stop_dist;
        if(new_sl > open_price && (sl == 0 || new_sl > sl))
        {
            trade.PositionModify(p_ticket, new_sl, PositionGetDouble(POSITION_TP));
        }
    }
    else if(type == POSITION_TYPE_SELL)
    {
        //--- For a SELL position, SL is triggered by the ASK price
        double current_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        double new_sl = current_price + trailing_stop_dist;
        if(new_sl < open_price && (sl == 0 || new_sl < sl))
        {
            trade.PositionModify(p_ticket, new_sl, PositionGetDouble(POSITION_TP));
        }
    }
}
//+------------------------------------------------------------------+
//| Check for sell signal and execute trade                          |
//+------------------------------------------------------------------+
void CheckSellSignal(double p_candle1_close, double p_candle2_low, double p_signal_candle_high)
{
    if(p_candle1_close < p_candle2_low)
    {
        CloseAllBuyTrades();
        if(CheckRiskFilters())
        {
            OpenSell(p_signal_candle_high);
        }
    }
}
//+------------------------------------------------------------------+
//| Check risk filters before opening a trade                        |
//+------------------------------------------------------------------+
bool CheckRiskFilters()
{
    //--- Spread filter
    double spread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) / g_point_multiplier;
    if(spread > InpMaxSpreadPips)
    {
        Print("Spread is too high: ", spread, " pips. Max allowed: ", InpMaxSpreadPips);
        return false;
    }

    //--- Max open trades filter
    if(PositionsTotal() >= InpMaxOpenTrades)
    {
        Print("Maximum open trades reached: ", PositionsTotal());
        return false;
    }

    //--- Time filter
    MqlDateTime current_time;
    TimeCurrent(current_time);
    int start_time_min = int(StringSubstr(InpTradingStartTime, 0, 2)) * 60 + int(StringSubstr(InpTradingStartTime, 3, 2));
    int end_time_min = int(StringSubstr(InpTradingEndTime, 0, 2)) * 60 + int(StringSubstr(InpTradingEndTime, 3, 2));
    int current_time_min = current_time.hour * 60 + current_time.min;

    bool time_to_trade = false;
    //--- Handle overnight session (e.g., 22:00 - 04:00)
    if(start_time_min > end_time_min)
    {
        if(current_time_min >= start_time_min || current_time_min <= end_time_min)
        {
            time_to_trade = true;
        }
    }
    //--- Handle normal day session (e.g., 08:00 - 16:00)
    else
    {
        if(current_time_min >= start_time_min && current_time_min <= end_time_min)
        {
            time_to_trade = true;
        }
    }

    if(!time_to_trade)
    {
        Print("Outside of trading hours.");
        return false;
    }

    return true;
}
//+------------------------------------------------------------------+
//| Open Buy Trade                                                   |
//+------------------------------------------------------------------+
void OpenBuy(double p_sl)
{
    double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double sl = p_sl;
    double tp_distance = (price - sl) * InpRiskRewardRatio;
    double tp = price + tp_distance;

    trade.Buy(InpLotSize, _Symbol, price, sl, tp, "Buy Trade");
}
//+------------------------------------------------------------------+
//| Open Sell Trade                                                  |
//+------------------------------------------------------------------+
void OpenSell(double p_sl)
{
    double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double sl = p_sl;
    double tp_distance = (sl - price) * InpRiskRewardRatio;
    double tp = price - tp_distance;

    trade.Sell(InpLotSize, _Symbol, price, sl, tp, "Sell Trade");
}
//+------------------------------------------------------------------+
//| Close all buy trades                                             |
//+------------------------------------------------------------------+
void CloseAllBuyTrades()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionGetSymbol(i) == _Symbol)
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
        if(PositionGetSymbol(i) == _Symbol)
        {
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
            {
                trade.PositionClose(PositionGetTicket(i));
            }
        }
    }
}
//+------------------------------------------------------------------+
