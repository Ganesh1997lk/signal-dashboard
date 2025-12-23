# backend/ea.py
import time
import random
import pandas as pd
import trades
from datetime import datetime

# --- EA Configuration ---
EA_INPUTS = {
    'GOLD': {
        'lot_size': 0.1,
        'stop_loss_pips': 200,
        'take_profit_pips': 400,
        'breakeven_pips': 50,
        'trailing_stop_pips': 100,
        'pip_value': 0.01,  # For GOLD, 1 pip = 0.01
        'max_concurrent_trades': 5,
        'allowed_trading_hours_utc': [8, 9, 10, 11, 12, 13, 14, 15, 16], # London session
        'max_spread_pips': 30
    },
    'BTCUSD': {
        'lot_size': 0.01,
        'stop_loss_pips': 10000,
        'take_profit_pips': 20000,
        'breakeven_pips': 2000,
        'trailing_stop_pips': 4000,
        'pip_value': 0.1, # For BTCUSD, 1 pip = 0.1
        'max_concurrent_trades': 3,
        'allowed_trading_hours_utc': list(range(24)), # All hours
        'max_spread_pips': 500
    }
}

# --- Global State ---
simulator_trend = {'direction': 'up', 'change_time': time.time()}

# --- Indicator Calculations ---
def calculate_ema(data, period):
    return data.ewm(span=period, adjust=False).mean()

def calculate_rsi(data, period=14):
    delta = data.diff()
    gain = (delta.where(delta > 0, 0)).ewm(alpha=1/period, adjust=False).mean()
    loss = (-delta.where(delta < 0, 0)).ewm(alpha=1/period, adjust=False).mean()
    rs = gain / loss
    rsi = 100 - (100 / (1 + rs))
    return rsi

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
        # Simulate spread
        spread = random.uniform(10, 50) * EA_INPUTS[symbol]['pip_value']
        prices.append({
            "time": timestamp, "open": open_price, "high": high_price,
            "low": low_price, "close": close_price, "spread": spread
        })
        current_price = close_price
    df = pd.DataFrame(prices)
    df['time'] = pd.to_datetime(df['time'], unit='s')
    df.set_index('time', inplace=True)
    return df

# --- Risk Management ---
def check_risk_filters(symbol, latest, open_trades):
    """Checks spread, max trades, and time filters."""
    inputs = EA_INPUTS[symbol]

    # Spread check
    if latest['spread'] > inputs['max_spread_pips'] * inputs['pip_value']:
        return False

    # Max trades check
    if len(open_trades) >= inputs['max_concurrent_trades']:
        return False

    # Time filter check
    if datetime.utcnow().hour not in inputs['allowed_trading_hours_utc']:
        return False

    return True

# --- Core EA Logic ---
def on_tick(symbol):
    """Main EA function, called on every new data tick."""
    inputs = EA_INPUTS[symbol]
    pip_value = inputs['pip_value']

    # 1. Get Market Data
    df = create_simulated_data(symbol)
    df['EMA_9'] = calculate_ema(df['close'], 9)
    df['EMA_21'] = calculate_ema(df['close'], 21)
    df['RSI_14'] = calculate_rsi(df['close'], 14)
    df.dropna(inplace=True)
    if df.empty:
        raise ValueError("Not enough data to generate signals.")

    latest = df.iloc[-1]
    price = latest['close']

    # 2. Manage Existing Trades
    manage_open_trades(symbol, price)

    # 3. Check for New Signals
    is_buy_condition = latest['EMA_9'] > latest['EMA_21'] and latest['RSI_14'] > 52
    is_sell_condition = latest['EMA_9'] < latest['EMA_21'] and latest['RSI_14'] < 48

    current_signal = 'WAITING'
    open_trades = trades.get_open_trades(symbol)

    if is_buy_condition:
        current_signal = 'BUY_SIGNAL'
        # Hedging: Close all SELL trades if a BUY signal appears
        for trade in [t for t in open_trades if t['type'] == 'SELL']:
            trades.close_trade(trade['id'], price)

        # Open a new BUY trade if risk filters pass and no buy trade is open
        if check_risk_filters(symbol, latest, open_trades) and not any(t['type'] == 'BUY' for t in open_trades):
            sl = price - (inputs['stop_loss_pips'] * pip_value)
            tp = price + (inputs['take_profit_pips'] * pip_value)
            trades.open_trade(symbol, 'BUY', price, sl, tp)

    elif is_sell_condition:
        current_signal = 'SELL_SIGNAL'
        # Hedging: Close all BUY trades if a SELL signal appears
        for trade in [t for t in open_trades if t['type'] == 'BUY']:
            trades.close_trade(trade['id'], price)

        # Open a new SELL trade if risk filters pass and no sell trade is open
        if check_risk_filters(symbol, latest, open_trades) and not any(t['type'] == 'SELL' for t in open_trades):
            sl = price + (inputs['stop_loss_pips'] * pip_value)
            tp = price - (inputs['take_profit_pips'] * pip_value)
            trades.open_trade(symbol, 'SELL', price, sl, tp)

    # 4. Prepare data for the frontend
    chart_df = df.iloc[-100:].reset_index()
    chart_data = chart_df.to_dict(orient='records')

    return {
        'signal': current_signal,
        'price': round(price, 4),
        'chart_data': chart_data,
        'history': trades.get_all_trades(symbol)
    }

def manage_open_trades(symbol, current_price):
    """Manages SL, TP, Breakeven, and Trailing Stops for open trades."""
    inputs = EA_INPUTS[symbol]
    pip_value = inputs['pip_value']

    for trade in trades.get_open_trades(symbol):
        # Check for SL/TP hit
        if trade['type'] == 'BUY':
            if current_price <= trade['sl']:
                trades.close_trade(trade['id'], current_price)
                continue
            if current_price >= trade['tp']:
                trades.close_trade(trade['id'], current_price)
                continue
        elif trade['type'] == 'SELL':
            if current_price >= trade['sl']:
                trades.close_trade(trade['id'], current_price)
                continue
            if current_price <= trade['tp']:
                trades.close_trade(trade['id'], current_price)
                continue

        # Breakeven Logic
        breakeven_level = inputs['breakeven_pips'] * pip_value
        if breakeven_level > 0:
            if trade['type'] == 'BUY' and current_price >= trade['open_price'] + breakeven_level:
                if trade['sl'] < trade['open_price']:
                    trades.update_trade(trade['id'], sl=trade['open_price'])
            elif trade['type'] == 'SELL' and current_price <= trade['open_price'] - breakeven_level:
                if trade['sl'] > trade['open_price']:
                    trades.update_trade(trade['id'], sl=trade['open_price'])

        # Trailing Stop Logic
        trailing_stop_level = inputs['trailing_stop_pips'] * pip_value
        if trailing_stop_level > 0:
            if trade['type'] == 'BUY':
                new_sl = current_price - trailing_stop_level
                if new_sl > trade['sl']:
                    trades.update_trade(trade['id'], sl=new_sl)
            elif trade['type'] == 'SELL':
                new_sl = current_price + trailing_stop_level
                if new_sl < trade['sl']:
                    trades.update_trade(trade['id'], sl=new_sl)
