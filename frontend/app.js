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
        if (data.signal !== previousSignals[symbol] && (data.signal === 'BUY' || data.signal === 'SELL')) {
            sendNotification(`${symbol.toUpperCase()} Signal`, `New signal: ${data.signal}`);
        }
        previousSignals[symbol] = data.signal;

        // Update charts if data is available
        if (data.chart_data && data.chart_data.length > 0) {
            updateCharts(symbol, data.chart_data);
        }

        // Update trade panels
        if (data.trades) {
            updateTradesPanel(symbol, data.trades);
        }
    }

    function updateCharts(symbol, chart_data) {
        const priceChart = charts[symbol].priceChart;
        const rsiChart = charts[symbol].rsiChart;
        const chartLabels = chart_data.map(d => new Date(d.time));

        priceChart.data.labels = chartLabels;
        priceChart.data.datasets[0].data = chart_data.map(d => ({ x: new Date(d.time).valueOf(), o: d.open, h: d.high, l: d.low, c: d.close }));
        priceChart.data.datasets[1].data = chart_data.map(d => ({ x: new Date(d.time).valueOf(), y: d.EMA_9 }));
        priceChart.data.datasets[2].data = chart_data.map(d => ({ x: new Date(d.time).valueOf(), y: d.EMA_21 }));

        rsiChart.data.labels = chartLabels;
        rsiChart.data.datasets[0].data = chart_data.map(d => ({ x: new Date(d.time).valueOf(), y: d.RSI_14 }));

        priceChart.update('none');
        rsiChart.update('none');
    }

    function updateTradesPanel(symbol, trades) {
        const openTradesList = document.querySelector(`#${symbol}-open-trades .trade-list`);
        const historyList = document.querySelector(`#${symbol}-history .trade-list`);
        openTradesList.innerHTML = '';
        historyList.innerHTML = '';

        // Update Open Trades
        if (trades.open && trades.open.length > 0) {
            trades.open.forEach(trade => {
                const p = document.createElement('p');
                p.innerHTML = `
                    <strong>${trade.type}</strong> @ ${trade.open_price.toFixed(2)}
                    <small>(SL: ${trade.sl.toFixed(2)}, TP: ${trade.tp.toFixed(2)})</small>
                `;
                openTradesList.appendChild(p);
            });
        } else {
            openTradesList.innerHTML = '<p>No open trades.</p>';
        }

        // Update Trade History
        if (trades.history && trades.history.length > 0) {
            trades.history.forEach(trade => {
                const p = document.createElement('p');
                const profit = (trade.close_price - trade.open_price) * (trade.type === 'BUY' ? 1 : -1);
                const profitClass = profit >= 0 ? 'profit' : 'loss';
                p.innerHTML = `
                    <strong>${trade.type}</strong> from ${trade.open_price.toFixed(2)} to ${trade.close_price.toFixed(2)}
                    <span class="${profitClass}">(${profit.toFixed(2)})</span>
                    <small>Closed: ${trade.close_reason || 'Signal'}</small>
                `;
                historyList.appendChild(p);
            });
        } else {
            historyList.innerHTML = '<p>No trade history.</p>';
        }
    }


    // --- Notifications ---
    function sendNotification(title, body) {
        if (Notification.permission === 'granted') {
            new Notification(title, { body: body });
        }
    }

    // --- Initial Load and Interval ---
    updateData(); // Initial call
    setInterval(updateData, 5000); // Update every 5 seconds
});
