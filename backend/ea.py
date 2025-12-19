import random
import time
import pandas as pd
from datetime import datetime
import uuid

# --- EA Configuration ---
sl_pips = 20
tp_pips = 40
breakeven_pips = 10
trailing_stop_pips = 15
use_breakeven = True
use_trailing_stop = True
pip_size = {'GOLD': 0.01, 'BTCUSD': 0.1}

# --- Global State ---
trades = {
    'GOLD': {'open': [], 'history': []},
    'BTCUSD': {'open': [], 'history': []}
}
simulator_trend = {'direction': 'up', 'change_time': time.time()}

# --- Custom Indicator Functions ---
def calculate_ema(data, period):
    return data.ewm(span=period, adjust=False).mean()

def calculate_rsi(data, period=14):
    delta = data.diff()
    gain = (delta.where(delta > 0, 0)).ewm(alpha=1/period, adjust=False).mean()
    loss = (-delta.where(delta < 0, 0)).ewm(alpha=1/period, adjust=False).mean()
    rs = gain / loss
    return 100 - (100 / (1 + rs))

# --- Data Simulation ---
def create_simulated_data(symbol):
    global simulator_trend
    now = int(time.time())
    if now - simulator_trend['change_time'] > random.randint(60, 180):
        simulator_trend['direction'] = 'down' if simulator_trend['direction'] == 'up' else 'up'
    trend_factor = 0.00015 if simulator_trend['direction'] == 'up' else -0.00015
    prices = []
    price_factor = 0.0005 if symbol == 'GOLD' else 0.001
    current_price = 1950.0 if symbol == 'GOLD' else 30000.0
    for i in range(200):
        timestamp = now - (200 - i) * 60
        drift = trend_factor * current_price * (random.uniform(0.5, 1.5))
        open_price = current_price + drift
        high_price = open_price + random.uniform(0, price_factor * open_price)
        low_price = open_price - random.uniform(0, price_factor * open_price)
        close_price = random.uniform(low_price, high_price)
        prices.append({
            "time": timestamp, "open": open_price, "high": high_price,
            "low": low_price, "close": close_price
        })
        current_price = close_price
    df = pd.DataFrame(prices)
    df['time'] = pd.to_datetime(df['time'], unit='s')
    df.set_index('time', inplace=True)
    return df

# --- EA Logic ---
def run_ea_logic(df, symbol):
    symbol_trades = trades[symbol]
    latest = df.iloc[-1]
    price = latest['close']
    p_size = pip_size[symbol]
    now = datetime.utcnow()

    # 1. Manage Open Trades
    trades_to_close = []
    for trade in symbol_trades['open']:
        # Check SL/TP
        if trade['type'] == 'BUY':
            if price <= trade['sl']:
                trade['status'] = 'CLOSED (SL)'
                trades_to_close.append(trade)
            elif price >= trade['tp']:
                trade['status'] = 'CLOSED (TP)'
                trades_to_close.append(trade)
            # Breakeven
            elif use_breakeven and price >= trade['open_price'] + (breakeven_pips * p_size):
                trade['sl'] = trade['open_price']
            # Trailing Stop
            elif use_trailing_stop and price > trade['sl'] + (trailing_stop_pips * p_size):
                trade['sl'] = price - (trailing_stop_pips * p_size)
        elif trade['type'] == 'SELL':
            if price >= trade['sl']:
                trade['status'] = 'CLOSED (SL)'
                trades_to_close.append(trade)
            elif price <= trade['tp']:
                trade['status'] = 'CLOSED (TP)'
                trades_to_close.append(trade)

    for trade in trades_to_close:
        trade['close_price'] = price
        trade['close_time'] = now.strftime('%Y-%m-%d %H:%M:%S UTC')
        symbol_trades['history'].append(trade)
        symbol_trades['open'].remove(trade)

    # 2. Check for New Signals
    df['EMA_9'] = calculate_ema(df['close'], 9)
    df['EMA_21'] = calculate_ema(df['close'], 21)
    df['RSI_14'] = calculate_rsi(df['close'], 14)
    df.dropna(inplace=True)
    if df.empty:
        return "WAITING", df

    latest = df.iloc[-1]
    is_buy_condition = latest['EMA_9'] > latest['EMA_21'] and latest['RSI_14'] > 52
    is_sell_condition = latest['EMA_9'] < latest['EMA_21'] and latest['RSI_14'] < 48

    # 3. Hedging Logic & Opening New Trades
    if is_buy_condition:
        # Close all sell trades if a buy signal appears
        for trade in list(symbol_trades['open']):
            if trade['type'] == 'SELL':
                trade['status'] = 'CLOSED (HEDGE)'
                trade['close_price'] = price
                trade['close_time'] = now.strftime('%Y-%m-%d %H:%M:%S UTC')
                symbol_trades['history'].append(trade)
                symbol_trades['open'].remove(trade)
        # Open new buy trade if none are open
        if not any(t['type'] == 'BUY' for t in symbol_trades['open']):
            new_trade = {
                'id': str(uuid.uuid4()),'type': 'BUY','open_price': price,
                'open_time': now.strftime('%Y-%m-%d %H:%M:%S UTC'),
                'sl': price - (sl_pips * p_size),'tp': price + (tp_pips * p_size),
                'status': 'OPEN'
            }
            symbol_trades['open'].append(new_trade)

    elif is_sell_condition:
        # Close all buy trades if a sell signal appears
        for trade in list(symbol_trades['open']):
            if trade['type'] == 'BUY':
                trade['status'] = 'CLOSED (HEDGE)'
                trade['close_price'] = price
                trade['close_time'] = now.strftime('%Y-%m-%d %H:%M:%S UTC')
                symbol_trades['history'].append(trade)
                symbol_trades['open'].remove(trade)
        # Open new sell trade if none are open
        if not any(t['type'] == 'SELL' for t in symbol_trades['open']):
            new_trade = {
                'id': str(uuid.uuid4()),'type': 'SELL','open_price': price,
                'open_time': now.strftime('%Y-%m-%d %H:%M:%S UTC'),
                'sl': price + (sl_pips * p_size),'tp': price - (tp_pips * p_size),
                'status': 'OPEN'
            }
            symbol_trades['open'].append(new_trade)

    # 4. Determine overall signal
    if any(t['type'] == 'BUY' for t in symbol_trades['open']):
        signal = 'BUY_HOLD'
    elif any(t['type'] == 'SELL' for t in symbol_trades['open']):
        signal = 'SELL_HOLD'
    else:
        signal = 'WAITING'

    if len(symbol_trades['history']) > 20:
        symbol_trades['history'].pop(0)

    return signal, df
