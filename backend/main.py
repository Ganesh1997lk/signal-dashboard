from flask import Flask, jsonify, send_from_directory
from ea import create_simulated_data, run_ea_logic, trades

app = Flask(__name__, static_folder='../frontend')

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
            signal, df_with_indicators = run_ea_logic(df.copy(), symbol)

            if df_with_indicators.empty:
                raise ValueError("Not enough data to generate signals.")

            latest_price = df_with_indicators['close'].iloc[-1]
            chart_data = df_with_indicators.iloc[-100:].reset_index().to_dict(orient='records')

            all_signals[symbol.lower()] = {
                'signal': signal,
                'price': round(latest_price, 2),
                'chart_data': chart_data,
                'open_trades': trades[symbol]['open'],
                'history': trades[symbol]['history']
            }
        except Exception as e:
            all_signals[symbol.lower()] = {
                'signal': 'ERROR', 'price': 0, 'error': str(e),
                'open_trades': [], 'history': []
            }

    return jsonify(all_signals)

if __name__ == '__main__':
    app.run(debug=True, port=5002)
