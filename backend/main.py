# backend/main.py
from flask import Flask, jsonify, send_from_directory
import ea

app = Flask(__name__, static_folder='../frontend')

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
            # The on_tick function will now return all the necessary data.
            all_signals[symbol.lower()] = ea.on_tick(symbol)
        except Exception as e:
            all_signals[symbol.lower()] = {
                'signal': 'ERROR', 'price': 0, 'error': str(e), 'history': []
            }
    return jsonify(all_signals)

if __name__ == '__main__':
    app.run(debug=True, port=5002)
