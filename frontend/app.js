document.addEventListener('DOMContentLoaded', () => {
    // --- Chart and State Initialization ---
    const charts = {};
    const previousSignals = {
        gold: 'WAITING',
        btcusd: 'WAITING'
    };

    // Initialize charts for both instruments
    createChart('gold');
    createChart('btcusd');

    // Request notification permission on load
    if (Notification.permission !== 'granted') {
        Notification.requestPermission();
    }

    // --- Chart Creation ---
    function createChart(symbol) {
        const chartCtx = document.getElementById(`${symbol}-chart`).getContext('2d');
        const rsiCtx = document.getElementById(`${symbol}-rsi-chart`).getContext('2d');

        charts[symbol] = {
            priceChart: new Chart(chartCtx, {
                type: 'candlestick',
                data: { datasets: [
                    { label: 'Price', data: [] },
                    { label: 'EMA Fast', type: 'line', data: [], borderColor: '#bb86fc', borderWidth: 1.5, pointRadius: 0 },
                    { label: 'EMA Slow', type: 'line', data: [], borderColor: '#03dac6', borderWidth: 1.5, pointRadius: 0 }
                ]},
                options: {
                    scales: { x: { type: 'time', time: { unit: 'minute' } } },
                    plugins: { legend: { display: false } }
                }
            }),
            rsiChart: new Chart(rsiCtx, {
                type: 'line',
                data: { datasets: [{ label: 'RSI', data: [], borderColor: '#fbc02d', borderWidth: 1.5 }] },
                options: {
                    scales: {
                        x: { type: 'time', time: { unit: 'minute' }, display: false },
                        y: { min: 0, max: 100 }
                    },
                    plugins: {
                        legend: { display: false },
                        annotation: {
                            annotations: {
                                line1: { type: 'line', yMin: 70, yMax: 70, borderColor: 'rgba(255, 99, 132, 0.5)', borderWidth: 1 },
                                line2: { type: 'line', yMin: 30, yMax: 30, borderColor: 'rgba(75, 192, 192, 0.5)', borderWidth: 1 }
                            }
                        }
                    }
                }
            })
        };
    }

    // --- Data Fetching and UI Update ---
    async function updateData() {
        try {
            const response = await fetch('/api/signals');
            if (!response.ok) throw new Error('Network response was not ok');
            const data = await response.json();

            updateInstrument('gold', data.gold);
            updateInstrument('btcusd', data.btcusd);

        } catch (error) {
            console.error('Error fetching data:', error);
        }
    }

    function updateInstrument(symbol, data) {
        if (!data || data.signal === 'ERROR') {
            console.error(`Error for ${symbol}:`, data ? data.error : 'No data');
            return;
        }

        // Update signal and price
        const signalEl = document.getElementById(`${symbol}-signal`);
        signalEl.textContent = data.signal;
        signalEl.className = `signal ${data.signal}`;
        document.getElementById(`${symbol}-price`).textContent = `$${data.price.toFixed(2)}`;

        // Check for new signal to send notification
        if (data.signal !== previousSignals[symbol] && (data.signal === 'BUY_HOLD' || data.signal === 'SELL_HOLD')) {
            sendNotification(`${symbol.toUpperCase()} Signal`, `New signal: ${data.signal}`);
        }
        previousSignals[symbol] = data.signal;

        // Update charts
        const priceChart = charts[symbol].priceChart;
        const rsiChart = charts[symbol].rsiChart;

        const chartLabels = data.chart_data.map(d => new Date(d.time));

        priceChart.data.labels = chartLabels;
        priceChart.data.datasets[0].data = data.chart_data.map(d => ({ x: new Date(d.time).valueOf(), o: d.open, h: d.high, l: d.low, c: d.close }));
        priceChart.data.datasets[1].data = data.chart_data.map(d => ({ x: new Date(d.time).valueOf(), y: d.EMA_9 }));
        priceChart.data.datasets[2].data = data.chart_data.map(d => ({ x: new Date(d.time).valueOf(), y: d.EMA_21 }));

        rsiChart.data.labels = chartLabels;
        rsiChart.data.datasets[0].data = data.chart_data.map(d => ({ x: new Date(d.time).valueOf(), y: d.RSI_14 }));

        priceChart.update('none');
        rsiChart.update('none');

        // Update trade panels
        updateOpenTrades(symbol, data.open_trades);
        updateHistory(symbol, data.history);
    }

    function updateOpenTrades(symbol, open_trades) {
        const openTradesLog = document.getElementById(`${symbol}-open-trades`);
        openTradesLog.innerHTML = '<h3>Open Trades</h3>';
        if (open_trades.length === 0) {
            openTradesLog.innerHTML += '<p>No open trades.</p>';
            return;
        }
        open_trades.forEach(trade => {
            const p = document.createElement('p');
            p.textContent = `${trade.open_time} - ${trade.type} @ ${trade.open_price.toFixed(2)} (SL: ${trade.sl.toFixed(2)}, TP: ${trade.tp.toFixed(2)})`;
            openTradesLog.appendChild(p);
        });
    }

    function updateHistory(symbol, history) {
        const historyLog = document.getElementById(`${symbol}-history`);
        historyLog.innerHTML = '<h3>Trade History</h3>'; // Clear previous entries

        if (history.length === 0) {
            historyLog.innerHTML += '<p>No trade history.</p>';
            return;
        }

        [...history].reverse().forEach(trade => {
            const p = document.createElement('p');
            let profit = 0;
            if (trade.type === 'BUY') {
                profit = trade.close_price - trade.open_price;
            } else {
                profit = trade.open_price - trade.close_price;
            }
            const profitClass = profit >= 0 ? 'profit' : 'loss';

            p.innerHTML = `
                ${trade.close_time} - ${trade.type} @ ${trade.open_price.toFixed(2)}
                → Closed @ ${trade.close_price.toFixed(2)}
                <span class="${profitClass}">(${profit.toFixed(2)})</span>
                - <i>${trade.status}</i>
            `;
            historyLog.appendChild(p);
        });
    }

    // --- Notifications ---
    function sendNotification(title, body) {
        if (Notification.permission === 'granted') {
            new Notification(title, { body: body });
        }
    }

    // --- Initial Load and Interval ---
    updateData(); // Initial call
    setInterval(updateData, 10000); // Update every 10 seconds
});
