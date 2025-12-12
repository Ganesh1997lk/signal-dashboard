import os
import random
import time
from flask import Flask, jsonify, send_from_directory
import pandas as pd
from datetime import datetime
import numpy as np

# --- Configuration ---
API_KEY = "YOUR_API_KEY"
USE_SIMULATOR = True

# --- EA Input Parameters (EA එකට අවශ්‍ය වන මූලික සැකසුම්) ---
STOP_LOSS_PIPS = 50  # ගනුදෙනුවකදී පාඩුව සීමා කරන අගය
TAKE_PROFIT_PIPS = 100  # ගනුදෙනුවකින් අපේක්ෂිත ලාභය
LOT_SIZE = 0.1  # ගනුදෙනුවේ ප්‍රමාණය
BREAKEVEN_PIPS = 10  # ලාභය මෙම අගයට පැමිණි විට Stop Loss අගය ගනුදෙනුව විවෘත වූ මිලට ගෙන ඒම
TRAILING_STOP_PIPS = 20  # ලාභය වැඩි වන විට Stop Loss අගය ලාභය පසුපස ගෙන ඒම
MAX_SPREAD = 20  # උපරිම Spread අගය
MAX_TRADES = 5  # එකවර විවෘත කළ හැකි උපරිම ගනුදෙනු ගණන
START_HOUR = 8  # ගනුදෙනු කළ හැකි ආරම්භක වේලාව
END_HOUR = 20  # ගනුදෙනු කළ හැකි අවසන් වේලාව

app = Flask(__name__, static_folder='../frontend')

# --- Global State ---
signal_states = {
    'GOLD': {'state': 'WAITING', 'history': []},
    'BTCUSD': {'state': 'WAITING', 'history': []}
}
simulator_trend = {'direction': 'up', 'change_time': time.time()}

# --- Custom Indicator Functions ---
def calculate_itrend(df, period=7):
    """Calculates the Ehlers Instantaneous Trendline from scratch."""
    alpha = 2 / (period + 1)
    itrend = np.zeros_like(df['close'])
    trigger = np.zeros_like(df['close'])

    for i in range(2, len(df['close'])):
        itrend[i] = (alpha - (alpha**2) / 4) * df['close'].iloc[i] + \
                    0.5 * (alpha**2) * df['close'].iloc[i-1] - \
                    (alpha - 0.75 * (alpha**2)) * df['close'].iloc[i-2] + \
                    2 * (1 - alpha) * itrend[i-1] - \
                    ((1 - alpha)**2) * itrend[i-2]

    trigger = 2 * itrend - np.roll(itrend, 2)

    itrend_df = pd.DataFrame({
        'trendline': itrend,
        'smooth_price': trigger
    }, index=df.index)

    return itrend_df

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
    current_trades = [t for t in state_info['history'] if t.get('status') == 'OPEN']

    # --- Indicator Calculation (දර්ශක ගණනය කිරීම) ---
    itrend_df = calculate_itrend(df)
    if itrend_df.empty:
        return state_info['state'], df

    df = df.join(itrend_df, how='inner')
    if df.empty:
        return state_info['state'], df

    latest = df.iloc[-1]
    price = latest['close']
    timestamp = datetime.now(datetime.UTC).strftime('%Y-%m-%d %H:%M:%S UTC')

    # --- Trade Management (විවෘත ගනුදෙනු කළමනාකරණය) ---
    for trade in current_trades:
        if trade['type'] == 'BUY':
            # Breakeven (පාඩුවක් නොමැතිව ගනුදෙනුව වසා දැමීමට SL අගය වෙනස් කිරීම)
            if price >= trade['open_price'] + (BREAKEVEN_PIPS / 10000.0):
                trade['stop_loss'] = trade['open_price']
            # Trailing Stop (ලාභයත් සමග SL අගය ලුහුබැඳ යාම)
            if price > trade['stop_loss'] + (TRAILING_STOP_PIPS / 10000.0):
                trade['stop_loss'] = price - (TRAILING_STOP_PIPS / 10000.0)
            # Stop Loss (පාඩුව සීමා කිරීම)
            if price <= trade['stop_loss']:
                trade.update({'status': 'CLOSED', 'close_price': price, 'close_time': timestamp, 'reason': 'SL'})
            # Take Profit (ලාභය ලබා ගැනීම)
            elif price >= trade['take_profit']:
                trade.update({'status': 'CLOSED', 'close_price': price, 'close_time': timestamp, 'reason': 'TP'})

        elif trade['type'] == 'SELL':
            # Breakeven
            if price <= trade['open_price'] - (BREAKEVEN_PIPS / 10000.0):
                trade['stop_loss'] = trade['open_price']
            # Trailing Stop
            if price < trade['stop_loss'] - (TRAILING_STOP_PIPS / 10000.0):
                trade['stop_loss'] = price + (TRAILING_STOP_PIPS / 10000.0)
            # Stop Loss
            if price >= trade['stop_loss']:
                trade.update({'status': 'CLOSED', 'close_price': price, 'close_time': timestamp, 'reason': 'SL'})
            # Take Profit
            elif price <= trade['take_profit']:
                trade.update({'status': 'CLOSED', 'close_price': price, 'close_time': timestamp, 'reason': 'TP'})

    # --- Entry Conditions (ගනුදෙනු විවෘත කිරීමේ කොන්දේසි) ---
    is_buy_condition = latest['smooth_price'] > latest['trendline']  # Buy signal condition
    is_sell_condition = latest['smooth_price'] < latest['trendline']  # Sell signal condition

    # --- Risk Filters ( අවදානම් කළමනාකරණය) ---
    spread = (latest['high'] - latest['low']) * 10000
    current_hour = datetime.utcnow().hour
    time_filter_ok = START_HOUR <= current_hour < END_HOUR

    if not current_trades:
        if is_buy_condition and spread <= MAX_SPREAD and len(current_trades) < MAX_TRADES and time_filter_ok:
            sl = price - (STOP_LOSS_PIPS / 10000.0)
            tp = price + (TAKE_PROFIT_PIPS / 10000.0)
            state_info['history'].append({
                'type': 'BUY', 'open_price': price, 'open_time': timestamp,
                'status': 'OPEN', 'stop_loss': sl, 'take_profit': tp, 'lot_size': LOT_SIZE
            })
            state_info['state'] = 'BUY_HOLD'
        elif is_sell_condition and spread <= MAX_SPREAD and len(current_trades) < MAX_TRADES and time_filter_ok:
            sl = price + (STOP_LOSS_PIPS / 10000.0)
            tp = price - (TAKE_PROFIT_PIPS / 10000.0)
            state_info['history'].append({
                'type': 'SELL', 'open_price': price, 'open_time': timestamp,
                'status': 'OPEN', 'stop_loss': sl, 'take_profit': tp, 'lot_size': LOT_SIZE
            })
            state_info['state'] = 'SELL_HOLD'
    else:
        # Close opposite trades (විරුද්ධ ගනුදෙනු වසා දැමීම)
        if is_buy_condition and any(t['type'] == 'SELL' for t in current_trades):
            for t in current_trades:
                if t['type'] == 'SELL':
                    t.update({'status': 'CLOSED', 'close_price': price, 'close_time': timestamp, 'reason': 'OPPOSITE'})

        if is_sell_condition and any(t['type'] == 'BUY' for t in current_trades):
            for t in current_trades:
                if t['type'] == 'BUY':
                    t.update({'status': 'CLOSED', 'close_price': price, 'close_time': timestamp, 'reason': 'OPPOSITE'})

    if not any(t['status'] == 'OPEN' for t in state_info['history']):
        state_info['state'] = 'WAITING'

    if len(state_info['history']) > 20:
        state_info['history'] = [t for t in state_info['history'] if t['status'] == 'OPEN'] + state_info['history'][-10:]

    df.rename(columns={'trendline': 'ITrend', 'smooth_price': 'SmoothPrice'}, inplace=True)
    return state_info['state'], df

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
