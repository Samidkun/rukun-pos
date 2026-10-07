# 🏪 Rukun — Offline-First Retail POS & Real-Time Live Owner Console

> **Resilient offline-first Point-of-Sale mobile app powered by Flutter, Drift SQLite, and Go Fiber backend with Server-Sent Events (SSE).**

---

## 📸 Visual Showcase & Dual-Surface Operations

<p align="center">
  <img src="docs/screenshots/preview.png" alt="Rukun POS Console" width="100%" style="border-radius: 10px; border: 1px solid rgba(255,255,255,0.1);" />
</p>
<p align="center"><em>Figure 1: Web Owner Live Console streaming real-time cashier transactions, daily gross revenue, and low-stock alerts.</em></p>

<br />

<div align="center">
  <table width="100%">
    <tr>
      <td width="100%" align="center">
        <img src="docs/screenshots/02-mobile-pos-cashier.png" alt="Mobile POS Cashier" width="100%" style="border-radius: 8px;" />
        <br /><strong>Figure 2: Flutter Tablet Cashier Register (Offline-First)</strong><br />
        <em>Instant local checkout backed by Drift SQLite with optimistic queue synchronization on internet reconnection.</em>
      </td>
    </tr>
  </table>
</div>

---

## 🔌 Offline-First Resiliency

- **Zero Network Blocker:** Kasir can process unlimited sales even when the internet is completely severed. Orders write immediately to local Drift SQLite.
- **Automatic Sync Queue:** Background worker replays queued orders to the Go backend via idempotent UUIDs upon network restoration.
- **Live SSE Stream:** Store owner dashboard updates in real-time via Server-Sent Events without polling.
