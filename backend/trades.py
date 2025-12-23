# backend/trades.py
import time
from datetime import datetime

# --- In-Memory Trade Storage ---
_open_trades = {}
_trade_history = []
_next_trade_id = 1

def _generate_trade_id():
    """Generates a unique, sequential trade ID."""
    global _next_trade_id
    trade_id = _next_trade_id
    _next_trade_id += 1
    return trade_id

def open_trade(symbol, trade_type, price, sl, tp):
    """Opens a new trade and adds it to the open trades list."""
    trade_id = _generate_trade_id()
    trade = {
        'id': trade_id,
        'symbol': symbol,
        'type': trade_type, # 'BUY' or 'SELL'
        'open_price': price,
        'open_time': datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC'),
        'status': 'OPEN',
        'sl': sl,
        'tp': tp,
        'close_price': None,
        'close_time': None
    }
    _open_trades[trade_id] = trade
    print(f"Opened trade {trade_id}: {trade}")
    return trade

def close_trade(trade_id, price):
    """Closes an open trade and moves it to history."""
    if trade_id in _open_trades:
        trade = _open_trades.pop(trade_id)
        trade['status'] = 'CLOSED'
        trade['close_price'] = price
        trade['close_time'] = datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')
        _trade_history.append(trade)
        print(f"Closed trade {trade_id}: {trade}")
        return trade
    return None

def update_trade(trade_id, sl=None, tp=None):
    """Updates the SL or TP of an open trade."""
    if trade_id in _open_trades:
        if sl is not None:
            _open_trades[trade_id]['sl'] = sl
        if tp is not None:
            _open_trades[trade_id]['tp'] = tp
        return _open_trades[trade_id]
    return None

def get_open_trades(symbol=None):
    """Gets all open trades, optionally filtered by symbol."""
    if symbol:
        return [trade for trade in _open_trades.values() if trade['symbol'] == symbol]
    return list(_open_trades.values())

def get_trade_history(symbol=None, limit=50):
    """Gets the trade history, optionally filtered by symbol."""
    history = _trade_history
    if symbol:
        history = [trade for trade in history if trade['symbol'] == symbol]

    # Return the most recent trades
    return sorted(history, key=lambda x: x['open_time'], reverse=True)[:limit]

def get_all_trades(symbol=None):
    """Returns a combined list of open trades and historical trades for the UI."""
    open_trades = get_open_trades(symbol)
    history = get_trade_history(symbol)

    # The frontend expects the latest trade first, so we combine and sort.
    # Open trades should appear at the top.
    all_trades = open_trades + history
    return sorted(all_trades, key=lambda x: (x['status'] == 'OPEN', x['open_time']), reverse=True)
