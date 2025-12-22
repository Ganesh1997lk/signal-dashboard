# backend/trades.py

# This file will manage the state of all open and closed trades.

# A simple in-memory store for trades for now.
# In a real application, you'd use a database.
trades = []
trade_id_counter = 1

def get_trades():
    """Returns all trades."""
    return trades

def get_open_trades(symbol=None, trade_type=None):
    """Returns all open trades, optionally filtered by symbol and/or type."""
    open_trades = [t for t in trades if t['status'] == 'OPEN']
    if symbol:
        open_trades = [t for t in open_trades if t['symbol'] == symbol]
    if trade_type:
        open_trades = [t for t in open_trades if t['type'] == trade_type]
    return open_trades

def add_trade(trade):
    """Adds a new trade."""
    global trade_id_counter
    trade['id'] = trade_id_counter
    trades.append(trade)
    trade_id_counter += 1

def close_trade(trade_id, close_price, close_time):
    """Closes an open trade."""
    for trade in trades:
        if trade['id'] == trade_id and trade['status'] == 'OPEN':
            trade['status'] = 'CLOSED'
            trade['close_price'] = close_price
            trade['close_time'] = close_time
            return True
    return False

def update_trade(trade_id, updates):
    """Updates an open trade with new values (e.g., for SL)."""
    for trade in trades:
        if trade['id'] == trade_id and trade['status'] == 'OPEN':
            trade.update(updates)
            return True
    return False
