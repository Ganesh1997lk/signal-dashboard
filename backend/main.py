import os
import random
import time
from flask import Flask, jsonify, send_from_directory
import pandas as pd
from datetime import datetime

# --- Local Imports ---
from ea import process_market_data
from trades import get_trade_manager

# --- Configuration ---
USE_SIMULATOR = True

app = Flask(__name__, static_folder='../frontend')

# --- Global State ---
simulator_trend = {'direction': 'up', 'change_time': time.time()}

# --- Data Simulation ---
def create_simulated_data(symbol):
    """
    Generates realistic, simulated candlestick data for trading symbols.
    """
    global simulator_trend
    now = int(time.time())

    # Randomly change trend direction every 1-3 minutes
    if now - simulator_trend['change_time'] > random.randint(60, 180):
        simulator_trend['direction'] = 'down' if simulator_trend['direction'] == 'up' else 'up'
        simulator_trend['change_time'] = now

    trend_factor = 0.00015 if simulator_trend['direction'] == 'up' else -0.00015

    prices = []
    # Set initial price based on symbol
    current_price = 1950.0 if symbol == 'GOLD' else 30000.0
    price_factor = 0.0005 if symbol == 'GOLD' else 0.001

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
            # 1. Get the trade manager for the symbol
            trade_manager = get_trade_manager(symbol)

            # 2. Fetch or simulate market data
            df = create_simulated_data(symbol)

            # 3. Process data with the EA
            signal, df_with_indicators = process_market_data(symbol, df.copy(), trade_manager)

            if df_with_indicators.empty:
                raise ValueError("Not enough data for indicators.")

            # 4. Prepare data for the frontend
            latest_price = df_with_indicators['close'].iloc[-1]
            chart_df = df_with_indicators.iloc[-100:].reset_index()
            chart_data = chart_df.to_dict(orient='records')

            # 5. Get trade data from the manager
            trade_data = trade_manager.get_all_data()

            all_signals[symbol.lower()] = {
                'signal': signal or 'WAIT',
                'price': round(latest_price, 2),
                'chart_data': chart_data,
                'trades': trade_data # Includes open and historical trades
            }
        except Exception as e:
            print(f"Error processing {symbol}: {e}")
            all_signals[symbol.lower()] = {
                'signal': 'ERROR', 'price': 0, 'error': str(e), 'trades': {'open': [], 'history': []}
            }

    return jsonify(all_signals)

if __name__ == '__main__':
    app.run(debug=True, port=5002)
