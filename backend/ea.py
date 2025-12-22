from datetime import datetime
from backend.trades import get_open_trades, add_trade, close_trade, update_trade
import pandas as pd

# --- EA Configuration ---
# These settings control the trading behavior for each symbol.
EA_CONFIG = {
    'GOLD': {
        'lot_size': 0.1,
        'stop_loss_pips': 20,
        'take_profit_pips': 40,
        'breakeven_pips': 10,       # Pips in profit to move SL to entry
        'trailing_stop_pips': 15,   # Pips behind the price to trail the SL
        'pip_value': 0.1,           # For GOLD, 1 pip is typically $0.1 for lot size 0.1
        'max_open_trades': 5,       # Maximum number of concurrent open trades
        'trading_hours_utc': (7, 19) # Only trade between 7:00 and 19:00 UTC
    },
    'BTCUSD': {
        'lot_size': 0.01,
        'stop_loss_pips': 100,
        'take_profit_pips': 200,
        'breakeven_pips': 50,
        'trailing_stop_pips': 70,
        'pip_value': 1.0,           # For BTCUSD, 1 pip is typically $1 for lot size 0.01
        'max_open_trades': 3,
        'trading_hours_utc': (0, 24) # BTC is a 24-hour market
    }
}

# --- Indicator Functions ---
def calculate_ema(data, period):
    """Calculates the Exponential Moving Average."""
    return data.ewm(span=period, adjust=False).mean()

def calculate_rsi(data, period=14):
    """Calculates the Relative Strength Index."""
    delta = data.diff()
    gain = (delta.where(delta > 0, 0)).ewm(alpha=1/period, adjust=False).mean()
    loss = (-delta.where(delta < 0, 0)).ewm(alpha=1/period, adjust=False).mean()
    rs = gain / loss
    rsi = 100 - (100 / (1 + rs))
    return rsi

# --- Core EA Logic ---

def run_ea_for_symbol(symbol: str, latest_candle: pd.Series):
    """
    Main function to run the EA logic for a given symbol on the latest market data.
    """
    config = EA_CONFIG[symbol]
    current_price = latest_candle['close']
    now = datetime.utcnow()

    # --- 1. Manage Existing Open Trades ---
    # This loop checks every open trade for this symbol to see if it needs management.
    for trade in get_open_trades(symbol=symbol):
        manage_open_trade(trade, current_price, config)

    # --- 2. Check for New Signals ---
    # These are the entry conditions based on indicators.
    is_buy_condition = latest_candle['EMA_9'] > latest_candle['EMA_21'] and latest_candle['RSI_14'] > 52
    is_sell_condition = latest_candle['EMA_9'] < latest_candle['EMA_21'] and latest_candle['RSI_14'] < 48

    current_signal = 'WAITING'

    # --- 3. Check Risk Filters Before Opening New Trades ---
    # Spread filter is not implemented as we are using simulated data without a bid/ask spread.

    # Time Filter
    start_hour, end_hour = config['trading_hours_utc']
    is_time_ok = start_hour <= now.hour < end_hour

    # Max Open Trades Filter
    num_open_trades = len(get_open_trades(symbol=symbol))
    is_max_trades_ok = num_open_trades < config['max_open_trades']

    # --- 4. Execute Actions Based on Signals and Filters ---
    if is_time_ok and is_max_trades_ok:
        if is_buy_condition:
            current_signal = 'BUY'
            # HEDGING RULE: Close all open SELL trades before opening a new BUY.
            for trade in get_open_trades(symbol=symbol, trade_type='SELL'):
                close_trade(trade['id'], current_price, now)

            # Open a new BUY trade.
            open_new_trade(symbol, 'BUY', current_price, now, config)

        elif is_sell_condition:
            current_signal = 'SELL'
            # HEDGING RULE: Close all open BUY trades before opening a new SELL.
            for trade in get_open_trades(symbol=symbol, trade_type='BUY'):
                close_trade(trade['id'], current_price, now)

            # Open a new SELL trade.
            open_new_trade(symbol, 'SELL', current_price, now, config)

    return current_signal

def open_new_trade(symbol, trade_type, price, timestamp, config):
    """Opens a new trade with calculated Stop Loss and Take Profit."""
    pip_value = config['pip_value']
    sl_pips = config['stop_loss_pips']
    tp_pips = config['take_profit_pips']

    if trade_type == 'BUY':
        stop_loss = price - (sl_pips * pip_value)
        take_profit = price + (tp_pips * pip_value)
    else: # SELL
        stop_loss = price + (sl_pips * pip_value)
        take_profit = price - (tp_pips * pip_value)

    add_trade({
        'symbol': symbol, 'type': trade_type, 'open_price': price,
        'open_time': timestamp, 'status': 'OPEN', 'stop_loss': stop_loss,
        'take_profit': take_profit, 'breakeven_triggered': False
    })

def manage_open_trade(trade, current_price, config):
    """
    Manages an individual open trade for SL, TP, Breakeven, and Trailing Stop.
    This function is called for every open trade on every new tick/candle.
    """
    now = datetime.utcnow()
    trade_type = trade['type']
    open_price = trade['open_price']
    pip_value = config['pip_value']

    # --- Check for Stop Loss or Take Profit Hit ---
    if trade_type == 'BUY':
        if current_price <= trade['stop_loss'] or current_price >= trade['take_profit']:
            close_trade(trade['id'], current_price, now)
            return # Trade is closed, no more management needed for it.
    elif trade_type == 'SELL':
        if current_price >= trade['stop_loss'] or current_price <= trade['take_profit']:
            close_trade(trade['id'], current_price, now)
            return

    # --- Breakeven Logic ---
    if not trade.get('breakeven_triggered', False):
        breakeven_pips = config['breakeven_pips']
        profit_pips = 0
        if trade_type == 'BUY':
            profit_pips = (current_price - open_price) / pip_value
        else: # SELL
            profit_pips = (open_price - current_price) / pip_value

        if profit_pips >= breakeven_pips:
            # Move stop loss to entry price
            update_trade(trade['id'], {'stop_loss': open_price, 'breakeven_triggered': True})
            return # SL has been updated, proceed to next tick

    # --- Trailing Stop Logic ---
    trailing_stop_pips = config['trailing_stop_pips']
    if trailing_stop_pips > 0:
        if trade_type == 'BUY':
            potential_new_sl = current_price - (trailing_stop_pips * pip_value)
            # We only move the stop loss up
            if potential_new_sl > trade['stop_loss']:
                update_trade(trade['id'], {'stop_loss': potential_new_sl})
        else: # SELL
            potential_new_sl = current_price + (trailing_stop_pips * pip_value)
            # We only move the stop loss down
            if potential_new_sl < trade['stop_loss']:
                update_trade(trade['id'], {'stop_loss': potential_new_sl})
