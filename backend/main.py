import os
import random
import time
from flask import Flask, jsonify, send_from_directory
import pandas as pd
from datetime import datetime, timezone
import numpy as np

# --- Configuration ---
API_KEY = "YOUR_API_KEY"
USE_SIMULATOR = True

app = Flask(__name__, static_folder='../frontend')

# --- Global State ---
# Each trade will be a dictionary: {'type': 'BUY'/'SELL', 'open_price': float, 'open_time': str, 'status': 'OPEN'/'CLOSED', 'sl': float, 'tp': float}
trade_history = {
    'GOLD': [],
    'BTCUSD': []
}
simulator_trend = {'direction': 'up', 'change_time': time.time()}

# --- Custom Indicator Functions ---
def calculate_ema(data, period):
    return data.ewm(span=period, adjust=False).mean()

def calculate_rsi(data, period=14):
    """A robust RSI calculation."""
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
        prices.append({
            "time": timestamp, "open": open_price, "high": high_price,
            "low": low_price, "close": close_price
        })
        current_price = close_price
    df = pd.DataFrame(prices)
    df['time'] = pd.to_datetime(df['time'], unit='s')
    df.set_index('time', inplace=True)
    return df

# --- Signal Generation ---
def generate_signal(df, symbol):

    # --- Indicators ---
    # Sinhala: දර්ශක ගණනය කිරීම
    df['EMA_9'] = calculate_ema(df['close'], 9)
    df['EMA_21'] = calculate_ema(df['close'], 21)
    df['RSI_14'] = calculate_rsi(df['close'], 14)

    # --- EA Configuration ---
    STOP_LOSS_PIPS = 10
    TAKE_PROFIT_PIPS = 20
    BREAKEVEN_PIPS = 5 # Profit pips needed to trigger breakeven
    TRAILING_STOP_PIPS = 10 # Pips to trail behind the price
    MAX_OPEN_TRADES = 5 # Maximum number of open trades at a time
    PIP_VALUE = 0.01 if symbol != 'GOLD' else 1 # Adjust pip value for GOLD

    # Drop NA values that may be created by indicators
    df.dropna(inplace=True)
    if df.empty:
        return 'ERROR', df # Not enough data

    latest = df.iloc[-1]
    price = latest['close']
    timestamp = datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')
    symbol_trades = trade_history[symbol]

    # --- Manage Open Trades ---
    # Sinhala: දැනට පවතින ගනුදෙනු කළමනාකරණය කිරීම
    open_trades = [t for t in symbol_trades if t['status'] == 'OPEN']
    for trade in open_trades:
        # Breakeven Logic
        if trade.get('breakeven_triggered', False) == False:
            if trade['type'] == 'BUY' and price >= trade['open_price'] + BREAKEVEN_PIPS * PIP_VALUE:
                trade['sl'] = trade['open_price']
                trade['breakeven_triggered'] = True
            elif trade['type'] == 'SELL' and price <= trade['open_price'] - BREAKEVEN_PIPS * PIP_VALUE:
                trade['sl'] = trade['open_price']
                trade['breakeven_triggered'] = True

        # Trailing Stop Logic (only triggers after breakeven)
        if trade.get('breakeven_triggered', False) == True:
            if trade['type'] == 'BUY':
                new_sl = price - TRAILING_STOP_PIPS * PIP_VALUE
                if new_sl > trade['sl']:
                    trade['sl'] = new_sl
            elif trade['type'] == 'SELL':
                new_sl = price + TRAILING_STOP_PIPS * PIP_VALUE
                if new_sl < trade['sl']:
                    trade['sl'] = new_sl

        # SL/TP Hit Logic
        if trade['type'] == 'BUY':
            if price <= trade['sl']:
                trade.update({'status': 'CLOSED', 'close_price': price, 'close_time': timestamp, 'reason': 'SL'})
            elif price >= trade['tp']:
                trade.update({'status': 'CLOSED', 'close_price': price, 'close_time': timestamp, 'reason': 'TP'})
        elif trade['type'] == 'SELL':
            if price >= trade['sl']:
                trade.update({'status': 'CLOSED', 'close_price': price, 'close_time': timestamp, 'reason': 'SL'})
            elif price <= trade['tp']:
                trade.update({'status': 'CLOSED', 'close_price': price, 'close_time': timestamp, 'reason': 'TP'})


    # --- Check for New Signals ---
    # Sinhala: නව සංඥා සඳහා පරීක්ෂා කිරීම
    is_buy_condition = latest['EMA_9'] > latest['EMA_21'] and latest['RSI_14'] > 52 and latest['RSI_14'] < 70
    is_sell_condition = latest['EMA_9'] < latest['EMA_21'] and latest['RSI_14'] < 48 and latest['RSI_14'] > 30

    open_buy_trades = any(t['type'] == 'BUY' and t['status'] == 'OPEN' for t in symbol_trades)
    open_sell_trades = any(t['type'] == 'SELL' and t['status'] == 'OPEN' for t in symbol_trades)

    # --- Opposing Signal Logic ---
    # Sinhala: ප්‍රතිවිරුද්ධ සංඥා සඳහා ගනුදෙනු වැසීම
    if is_buy_condition and open_sell_trades:
        for t in symbol_trades:
            if t['type'] == 'SELL' and t['status'] == 'OPEN':
                # Close at a simulated profit as per user instruction "සියල්ලට tp කර close කරන්න"
                t.update({'status': 'CLOSED', 'close_price': t['tp'], 'close_time': timestamp, 'reason': 'OPPOSING_SIGNAL'})
    elif is_sell_condition and open_buy_trades:
        for t in symbol_trades:
            if t['type'] == 'BUY' and t['status'] == 'OPEN':
                t.update({'status': 'CLOSED', 'close_price': t['tp'], 'close_time': timestamp, 'reason': 'OPPOSING_SIGNAL'})

    # --- Open New Trades ---
    # Re-check open trades after potential closures
    open_trades_count = len([t for t in symbol_trades if t['status'] == 'OPEN'])
    open_buy_trades = any(t['type'] == 'BUY' and t['status'] == 'OPEN' for t in symbol_trades)
    open_sell_trades = any(t['type'] == 'SELL' and t['status'] == 'OPEN' for t in symbol_trades)

    if is_buy_condition and open_trades_count < MAX_OPEN_TRADES:
        # Sinhala: නව BUY ගනුදෙනුවක් විවෘත කිරීම
        sl = price - STOP_LOSS_PIPS * PIP_VALUE
        tp = price + TAKE_PROFIT_PIPS * PIP_VALUE
        symbol_trades.append({
            'type': 'BUY', 'open_price': price, 'open_time': timestamp, 'status': 'OPEN', 'sl': sl, 'tp': tp
        })
    elif is_sell_condition and open_trades_count < MAX_OPEN_TRADES:
        # Sinhala: නව SELL ගනුදෙනුවක් විවෘත කිරීම
        sl = price + STOP_LOSS_PIPS * PIP_VALUE
        tp = price - TAKE_PROFIT_PIPS * PIP_VALUE
        symbol_trades.append({
            'type': 'SELL', 'open_price': price, 'open_time': timestamp, 'status': 'OPEN', 'sl': sl, 'tp': tp
        })

    # --- Determine Overall Signal for Frontend ---
    current_open_trades = [t for t in symbol_trades if t['status'] == 'OPEN']
    if not current_open_trades:
        new_signal = 'WAITING'
    else:
        # Signal is based on the type of the most recent open trade
        new_signal = f"{current_open_trades[-1]['type']}_HOLD"

    # --- History Management ---
    if len(symbol_trades) > 20: # Keep a longer history
        # Keep all open trades plus the most recent 20 closed trades
        open_trades = [t for t in symbol_trades if t['status'] == 'OPEN']
        closed_trades = sorted([t for t in symbol_trades if t['status'] == 'CLOSED'], key=lambda x: x['close_time'], reverse=True)
        trade_history[symbol] = open_trades + closed_trades[:20]

    return new_signal, df

# --- API Endpoints ---
@app.route('/')
def serve_index():
    return send_from_directory(app.static_folder, 'index.html')

@app.route('/<path:path>')
def serve_static(path):
    return send_from_directory(app.static_folder, path)

@app.route('/api/signals')
def get_signals():
    all_signals = {}
    for symbol in ['GOLD', 'BTCUSD']:
        try:
            df = create_simulated_data(symbol)
            signal, df_with_indicators = generate_signal(df.copy(), symbol)

            if df_with_indicators.empty:
                raise ValueError("Not enough data to generate signals.")

            latest_price = df_with_indicators['close'].iloc[-1]
            chart_df = df_with_indicators.iloc[-100:].reset_index()
            chart_data = chart_df.to_dict(orient='records')

            all_signals[symbol.lower()] = {
                'signal': signal,
                'price': round(latest_price, 2),
                'chart_data': chart_data,
                'history': trade_history[symbol] # Use the new global state
            }
        except Exception as e:
            all_signals[symbol.lower()] = {
                'signal': 'ERROR', 'price': 0, 'error': str(e), 'history': []
            }

    return jsonify(all_signals)

if __name__ == '__main__':
    app.run(debug=True, port=5002)
