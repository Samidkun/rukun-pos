// Rukun POS — Live Owner Dashboard SSE Client
(function () {
  let totalRevenueCents = 0;
  let totalSalesCount = 0;
  const productSales = new Map(); // name -> qty

  const totalRevenueEl = document.getElementById('total-revenue');
  const totalSalesCountEl = document.getElementById('total-sales-count');
  const feedContainer = document.getElementById('transaction-feed');
  const feedCounterEl = document.getElementById('feed-counter');
  const emptyPlaceholder = document.getElementById('empty-feed-placeholder');
  const topProductsListEl = document.getElementById('top-products-list');
  const statusBadge = document.getElementById('connection-status');
  const statusLabel = document.getElementById('status-label');
  const btnSimSale = document.getElementById('btn-sim-sale');

  function formatRupiah(cents) {
    return 'Rp ' + Number(cents).toLocaleString('id-ID');
  }

  function formatTime(isoOrDate) {
    const d = isoOrDate ? new Date(isoOrDate) : new Date();
    return d.toLocaleTimeString('id-ID', { hour: '2-digit', minute: '2-digit', second: '2-digit' });
  }

  function handleIncomingSale(sale) {
    if (emptyPlaceholder) {
      emptyPlaceholder.style.display = 'none';
    }

    totalRevenueCents += sale.total_cents || 0;
    totalSalesCount += 1;

    totalRevenueEl.textContent = formatRupiah(totalRevenueCents);
    totalSalesCountEl.textContent = totalSalesCount.toString();
    feedCounterEl.textContent = `${totalSalesCount} transaksi tersinkron`;

    // Update Top Products
    if (Array.isArray(sale.items)) {
      for (const it of sale.items) {
        const cur = productSales.get(it.name) || 0;
        productSales.set(it.name, cur + (it.qty || 1));
      }
      renderTopProducts();
    }

    // Render Transaction Card
    const invoiceNum = sale.invoice_number ? String(sale.invoice_number).padStart(6, '0') : '000001';
    const invoiceFull = `${sale.invoice_series || 'T01'}-${invoiceNum}`;
    const itemsSummary = Array.isArray(sale.items)
      ? sale.items.map(i => `${i.name} (x${i.qty})`).join(', ')
      : 'Penjualan offline';

    const card = document.createElement('div');
    card.className = 'tx-card';
    card.innerHTML = `
      <div class="tx-left">
        <div class="tx-meta">
          <span class="tx-term">${sale.terminal_id || 'T01'}</span>
          <span class="tx-invoice">${invoiceFull}</span>
          <span class="tx-time">${formatTime(sale.occurred_at)}</span>
        </div>
        <div class="tx-items">${itemsSummary}</div>
      </div>
      <div class="tx-right">
        <div class="tx-amount">${formatRupiah(sale.total_cents || 0)}</div>
        <div class="tx-method">${(sale.payment_method || 'CASH').toUpperCase()}</div>
      </div>
    `;

    feedContainer.prepend(card);
  }

  function renderTopProducts() {
    if (productSales.size === 0) return;

    const sorted = Array.from(productSales.entries())
      .sort((a, b) => b[1] - a[1])
      .slice(0, 5);

    topProductsListEl.innerHTML = sorted.map(([name, qty]) => `
      <div class="top-prod-row">
        <span class="top-prod-name">${name}</span>
        <span class="top-prod-qty">${qty} terjual</span>
      </div>
    `).join('');
  }

  // SSE Connection
  function initSSE() {
    const sseUrl = window.location.port === '8080'
      ? '/api/v1/realtime/sales'
      : 'http://localhost:8080/api/v1/realtime/sales';

    try {
      const evtSource = new EventSource(sseUrl);

      evtSource.onopen = function () {
        statusBadge.className = 'status-badge live';
        statusLabel.textContent = 'LIVE STREAMING';
      };

      evtSource.addEventListener('sale', function (e) {
        try {
          const sale = JSON.parse(e.data);
          handleIncomingSale(sale);
        } catch (err) {
          console.error('Error parsing SSE sale data:', err);
        }
      });

      evtSource.onerror = function () {
        statusBadge.className = 'status-badge connecting';
        statusLabel.textContent = 'MENGHUBUNGKAN ULANG...';
      };
    } catch (e) {
      statusBadge.className = 'status-badge connecting';
      statusLabel.textContent = 'SSE OFFLINE';
    }
  }

  // Simulation Trigger for Demonstrations
  let simCounter = 1;
  btnSimSale.addEventListener('click', function () {
    const mockProducts = [
      { name: 'Kopi Susu Aren', price_cents: 18000 },
      { name: 'Roti Bakar Cokelat', price_cents: 16000 },
      { name: 'Matcha Latte', price_cents: 22000 },
    ];
    const picked = mockProducts[Math.floor(Math.random() * mockProducts.length)];
    const qty = Math.floor(Math.random() * 2) + 1;
    const total = picked.price_cents * qty;
    const term = Math.random() > 0.5 ? 'T01' : 'T02';

    handleIncomingSale({
      terminal_id: term,
      invoice_series: term,
      invoice_number: simCounter++,
      total_cents: total,
      payment_method: 'cash',
      occurred_at: new Date().toISOString(),
      items: [{ name: picked.name, qty: qty, price_cents: picked.price_cents }],
    });
  });

  // Start SSE on page load
  window.addEventListener('DOMContentLoaded', initSSE);
})();
