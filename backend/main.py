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
signal_states = {
    'GOLD': {'state': 'WAITING', 'history': []},
    'BTCUSD': {'state': 'WAITING', 'history': []}
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
    state_info = signal_states[symbol]
    current_state = state_info['state']

    df['EMA_9'] = calculate_ema(df['close'], 9)
    df['EMA_21'] = calculate_ema(df['close'], 21)
    df['RSI_14'] = calculate_rsi(df['close'], 14)

    # Drop NA values that may be created by indicators
    df.dropna(inplace=True)
    if df.empty:
        return current_state, df # Not enough data

    latest = df.iloc[-1]
    price = latest['close']
    is_buy_condition = latest['EMA_9'] > latest['EMA_21'] and latest['RSI_14'] > 52 and latest['RSI_14'] < 70
    is_sell_condition = latest['EMA_9'] < latest['EMA_21'] and latest['RSI_14'] < 48 and latest['RSI_14'] > 30

    new_signal = current_state
    timestamp = datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')

    # Case 1: Waiting for a signal
    if current_state == 'WAITING':
        if is_buy_condition:
            new_signal = 'BUY_HOLD'
            state_info['history'].append({'type': 'BUY', 'open_price': price, 'open_time': timestamp, 'status': 'OPEN'})
        elif is_sell_condition:
            new_signal = 'SELL_HOLD'
            state_info['history'].append({'type': 'SELL', 'open_price': price, 'open_time': timestamp, 'status': 'OPEN'})

    # Case 2: In a BUY trade
    elif current_state == 'BUY_HOLD':
        # Hedging: If a SELL signal appears, close BUY and open SELL.
        if is_sell_condition:
            new_signal = 'SELL_HOLD'
            # Close all open BUY trades
            for trade in state_info['history']:
                if trade['type'] == 'BUY' and trade['status'] == 'OPEN':
                    trade.update({'status': 'CLOSED', 'close_price': price, 'close_time': timestamp, 'reason': 'Hedged'})
            # Open new SELL trade
            state_info['history'].append({'type': 'SELL', 'open_price': price, 'open_time': timestamp, 'status': 'OPEN'})
        # Exit condition: If BUY condition is no longer true (and no SELL signal)
        elif not is_buy_condition:
            new_signal = 'WAITING'
            for trade in state_info['history']:
                 if trade['type'] == 'BUY' and trade['status'] == 'OPEN':
                    trade.update({'status': 'CLOSED', 'close_price': price, 'close_time': timestamp, 'reason': 'Condition False'})

    # Case 3: In a SELL trade
    elif current_state == 'SELL_HOLD':
        # Hedging: If a BUY signal appears, close SELL and open BUY.
        if is_buy_condition:
            new_signal = 'BUY_HOLD'
            # Close all open SELL trades
            for trade in state_info['history']:
                if trade['type'] == 'SELL' and trade['status'] == 'OPEN':
                    trade.update({'status': 'CLOSED', 'close_price': price, 'close_time': timestamp, 'reason': 'Hedged'})
            # Open new BUY trade
            state_info['history'].append({'type': 'BUY', 'open_price': price, 'open_time': timestamp, 'status': 'OPEN'})
        # Exit condition: If SELL condition is no longer true (and no BUY signal)
        elif not is_sell_condition:
            new_signal = 'WAITING'
            for trade in state_info['history']:
                if trade['type'] == 'SELL' and trade['status'] == 'OPEN':
                    trade.update({'status': 'CLOSED', 'close_price': price, 'close_time': timestamp, 'reason': 'Condition False'})

    state_info['state'] = new_signal
    if len(state_info['history']) > 10:
        # Prune history by removing the oldest closed trades
        open_trades = [t for t in state_info['history'] if t['status'] == 'OPEN']
        closed_trades = [t for t in state_info['history'] if t['status'] != 'OPEN']
        state_info['history'] = open_trades + closed_trades[-9:] # Keep open trades and 9 most recent closed

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
                'history': signal_states[symbol]['history']
            }
        except Exception as e:
            all_signals[symbol.lower()] = {
                'signal': 'ERROR', 'price': 0, 'error': str(e), 'history': []
            }

    return jsonify(all_signals)

if __name__ == '__main__':
    app.run(debug=True, port=5002)
