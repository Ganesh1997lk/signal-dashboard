import random
import time
from flask import Flask, jsonify, send_from_directory
import pandas as pd
from datetime import datetime

# --- Local Imports ---
from backend.ea import run_ea_for_symbol, calculate_ema, calculate_rsi
from backend.trades import get_trades

# --- Configuration ---
USE_SIMULATOR = True

app = Flask(__name__, static_folder='../frontend')

# --- Global State ---
# Trend simulation for our data generator
simulator_trend = {'direction': 'up', 'change_time': time.time()}

# --- Data Simulation ---
def create_simulated_data(symbol):
    """Generates realistic-looking OHLC data for a given symbol."""
    global simulator_trend
    now = int(time.time())

    # Randomly change the trend direction every 1-3 minutes
    if now - simulator_trend['change_time'] > random.randint(60, 180):
        simulator_trend['direction'] = 'down' if simulator_trend['direction'] == 'up' else 'up'
        simulator_trend['change_time'] = now

    trend_factor = 0.00015 if simulator_trend['direction'] == 'up' else -0.00015
    price_factor = 0.0005 if symbol == 'GOLD' else 0.001
    current_price = 1950.0 if symbol == 'GOLD' else 30000.0

    prices = []
    for i in range(200): # Generate 200 candles
        timestamp = now - (200 - i) * 60 # 1-minute candles
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

# --- API Endpoints ---
@app.route('/')
def serve_index():
    return send_from_directory(app.static_folder, 'index.html')

@app.route('/<path:path>')
def serve_static(path):
    # Serve static files from the 'frontend' directory
    return send_from_directory(app.static_folder, path)

@app.route('/api/signals')
def get_signals():
    """
    The main API endpoint. For each symbol, it generates data, runs the EA,
    and returns the results.
    """
    all_signals = {}
    for symbol in ['GOLD', 'BTCUSD']:
        try:
            # 1. Get Market Data
            df = create_simulated_data(symbol)

            # 2. Add Indicators
            df['EMA_9'] = calculate_ema(df['close'], 9)
            df['EMA_21'] = calculate_ema(df['close'], 21)
            df['RSI_14'] = calculate_rsi(df['close'], 14)
            df.dropna(inplace=True) # Remove rows with NaN from indicator calculations

            if df.empty:
                raise ValueError("Not enough data to generate signals.")

            # 3. Run the EA logic for the latest candle
            latest_candle = df.iloc[-1]
            current_signal = run_ea_for_symbol(symbol, latest_candle)

            # 4. Prepare data for the frontend
            latest_price = latest_candle['close']
            chart_df = df.iloc[-100:].reset_index() # Display last 100 candles
            chart_data = chart_df.to_dict(orient='records')

            all_signals[symbol.lower()] = {
                'signal': current_signal,
                'price': round(latest_price, 2),
                'chart_data': chart_data,
                'trades': [t for t in get_trades() if t['symbol'] == symbol]
            }
        except Exception as e:
            all_signals[symbol.lower()] = {
                'signal': 'ERROR', 'price': 0, 'error': str(e), 'trades': []
            }

    return jsonify(all_signals)

if __name__ == '__main__':
    # It's recommended to use a production-ready WSGI server instead of app.run() in a real environment.
    app.run(debug=True, port=5002)
