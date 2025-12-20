# backend/ea.py
import time
from datetime import datetime
import pandas as pd

# --- EA Configuration ---
EA_INPUTS = {
    'GOLD': {
        'lot_size': 0.01,
        'stop_loss_pips': 200,
        'take_profit_pips': 400,
        'breakeven_pips': 100,
        'trailing_stop_pips': 50,
        'max_open_trades': 5,
        'enable_breakeven': True,
        'enable_trailing_stop': True,
    },
    'BTCUSD': {
        'lot_size': 0.01,
        'stop_loss_pips': 500,
        'take_profit_pips': 1000,
        'breakeven_pips': 200,
        'trailing_stop_pips': 100,
        'max_open_trades': 3,
        'enable_breakeven': True,
        'enable_trailing_stop': False,
    }
}

# --- Global State ---
ea_states = {
    'GOLD': {'last_candle_time': None},
    'BTCUSD': {'last_candle_time': None}
}

# --- Custom Indicator Functions ---
def calculate_ema(data, period):
    return data.ewm(span=period, adjust=False).mean()

def calculate_rsi(data, period=14):
    delta = data.diff()
    gain = (delta.where(delta > 0, 0)).ewm(alpha=1/period, adjust=False).mean()
    loss = (-delta.where(delta < 0, 0)).ewm(alpha=1/period, adjust=False).mean()
    rs = gain / loss
    rsi = 100 - (100 / (1 + rs))
    return rsi

# --- Core EA Logic ---
def process_market_data(symbol, df, trade_manager):
    """
    Main EA function to process data and generate trading signals.
    """
    config = EA_INPUTS[symbol]
    state = ea_states[symbol]

    # 1. New Candle Check
    latest_candle_time = df.index[-1]
    if latest_candle_time == state['last_candle_time']:
        return None, df  # No new candle, do nothing
    state['last_candle_time'] = latest_candle_time

    # 2. Add Indicators
    df['EMA_9'] = calculate_ema(df['close'], 9)
    df['EMA_21'] = calculate_ema(df['close'], 21)
    df['RSI_14'] = calculate_rsi(df['close'], 14)
    df.dropna(inplace=True)
    if df.empty:
        return None, df

    latest_data = df.iloc[-1]
    current_price = latest_data['close']
    open_trades = trade_manager.get_open_trades()

    # 3. Manage Existing Trades (SL, TP, Breakeven, Trailing Stop)
    for trade in list(open_trades):
        manage_open_trade(trade, current_price, config, trade_manager)

    # 4. Check Buy/Sell Conditions
    is_buy_signal = latest_data['EMA_9'] > latest_data['EMA_21'] and latest_data['RSI_14'] > 52
    is_sell_signal = latest_data['EMA_9'] < latest_data['EMA_21'] and latest_data['RSI_14'] < 48

    # 5. Hedging and Opening New Trades
    if is_buy_signal:
        # Close all sell trades before opening a buy
        for trade in list(open_trades):
            if trade['type'] == 'SELL':
                trade_manager.close_trade(trade['id'], current_price, 'Hedging')

        # Open new buy trade if conditions are met
        if len(trade_manager.get_open_trades(trade_type='BUY')) < config['max_open_trades']:
            open_new_trade(symbol, 'BUY', current_price, config, trade_manager)
            return 'BUY', df

    elif is_sell_signal:
        # Close all buy trades before opening a sell
        for trade in list(open_trades):
            if trade['type'] == 'BUY':
                trade_manager.close_trade(trade['id'], current_price, 'Hedging')

        # Open new sell trade if conditions are met
        if len(trade_manager.get_open_trades(trade_type='SELL')) < config['max_open_trades']:
            open_new_trade(symbol, 'SELL', current_price, config, trade_manager)
            return 'SELL', df

    return 'WAIT', df

def open_new_trade(symbol, trade_type, price, config, trade_manager):
    """Calculates SL/TP and opens a new trade."""
    pip_value = 0.01 if symbol == 'GOLD' else 1.0

    if trade_type == 'BUY':
        sl = price - (config['stop_loss_pips'] * pip_value)
        tp = price + (config['take_profit_pips'] * pip_value)
    else: # SELL
        sl = price + (config['stop_loss_pips'] * pip_value)
        tp = price - (config['take_profit_pips'] * pip_value)

    trade_manager.open_trade(trade_type, price, sl, tp, config['lot_size'])

def manage_open_trade(trade, current_price, config, trade_manager):
    """Applies SL, TP, breakeven, and trailing stop logic."""
    pip_value = 0.01 if trade['symbol'] == 'GOLD' else 1.0

    # SL/TP Hit Detection
    if trade['type'] == 'BUY':
        if current_price <= trade['sl']:
            trade_manager.close_trade(trade['id'], current_price, 'SL Hit')
            return
        if current_price >= trade['tp']:
            trade_manager.close_trade(trade['id'], current_price, 'TP Hit')
            return
    else:  # SELL
        if current_price >= trade['sl']:
            trade_manager.close_trade(trade['id'], current_price, 'SL Hit')
            return
        if current_price <= trade['tp']:
            trade_manager.close_trade(trade['id'], current_price, 'TP Hit')
            return

    # Breakeven Logic
    if config['enable_breakeven'] and not trade.get('breakeven_activated', False):
        profit_pips = 0
        if trade['type'] == 'BUY':
            profit_pips = (current_price - trade['open_price']) / pip_value
        else: # SELL
            profit_pips = (trade['open_price'] - current_price) / pip_value

        if profit_pips >= config['breakeven_pips']:
            trade['sl'] = trade['open_price']
            trade['breakeven_activated'] = True

    # Trailing Stop Logic
    if config['enable_trailing_stop']:
        trail_pips = config['trailing_stop_pips']
        if trade['type'] == 'BUY':
            potential_new_sl = current_price - (trail_pips * pip_value)
            if potential_new_sl > trade['sl']:
                trade['sl'] = potential_new_sl
        else: # SELL
            potential_new_sl = current_price + (trail_pips * pip_value)
            if potential_new_sl < trade['sl']:
                trade['sl'] = potential_new_sl
