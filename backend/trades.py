# backend/trades.py
import time
from datetime import datetime
import uuid

# --- In-Memory Trade Store ---
# In a real application, this would be a database.
trades_store = {
    'GOLD': {'open': [], 'history': []},
    'BTCUSD': {'open': [], 'history': []}
}

class TradeManager:
    def __init__(self, symbol):
        self.symbol = symbol
        self.open_trades = trades_store[symbol]['open']
        self.trade_history = trades_store[symbol]['history']

    def open_trade(self, trade_type, price, sl, tp, lot_size):
        """Opens a new trade and adds it to the open trades list."""
        trade = {
            'id': str(uuid.uuid4()),
            'symbol': self.symbol,
            'type': trade_type,
            'open_time': datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC'),
            'open_price': price,
            'sl': sl,
            'tp': tp,
            'lot_size': lot_size,
            'status': 'OPEN'
        }
        self.open_trades.append(trade)
        print(f"Opened {trade_type} trade for {self.symbol} at {price}")
        return trade

    def close_trade(self, trade_id, price, reason="Unknown"):
        """Closes a trade and moves it to the history."""
        trade_to_close = None
        for trade in self.open_trades:
            if trade['id'] == trade_id:
                trade_to_close = trade
                break

        if trade_to_close:
            trade_to_close.update({
                'status': 'CLOSED',
                'close_price': price,
                'close_time': datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC'),
                'close_reason': reason
            })
            self.trade_history.append(trade_to_close)
            self.open_trades.remove(trade_to_close)
            print(f"Closed trade {trade_id} for {self.symbol} at {price}. Reason: {reason}")
            # Keep history clean
            if len(self.trade_history) > 50:
                self.trade_history.pop(0)
            return True
        return False

    def get_open_trades(self, trade_type=None):
        """Gets all open trades, optionally filtering by type."""
        if trade_type:
            return [t for t in self.open_trades if t['type'] == trade_type]
        return self.open_trades

    def get_trade_history(self):
        """Gets the trade history."""
        return self.trade_history

    def get_all_data(self):
        """Returns all open and historical trades."""
        return {
            'open': self.open_trades,
            'history': sorted(self.trade_history, key=lambda x: x['open_time'], reverse=True)
        }

# --- Functions to be called from the main app ---
def get_trade_manager(symbol):
    """Factory function to get a TradeManager instance."""
    if symbol not in trades_store:
        raise ValueError(f"Invalid symbol: {symbol}")
    return TradeManager(symbol)
