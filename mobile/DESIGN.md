# Rukun Mobile — Anti-UI-Slop Design Contract & Tokens

> **Standard:** Strict Anti-UI-Slop Contract. No pitch-black `#000000`, no emoji buttons, no floating blurry cards, no generic AI-generated filler layouts.

---

## 1. Visual Foundation

| Token | Hex | Role |
|---|---|---|
| `bgPrimary` | `#16181C` | App background, master canvas |
| `surfacePrimary` | `#1E2228` | Product grid cards, list items, sheets |
| `surfaceElevated` | `#252A32` | Dialogs, bottom sheets, active modals |
| `borderHairline` | `#2A2E35` | 1px clean separator borders |
| `borderFocus` | `#3F4550` | Focused input border |
| `accentPrimary` | `#C7F53B` | Electric Lime — Hero CTA (Bayar, Checkout, Confirm) |
| `accentSuccess` | `#4EE5B6` | Serene Mint — Synced state, online connectivity |
| `accentWarning` | `#F5A623` | Warm Amber — Pending outbox sync, caution |
| `accentDanger` | `#FF4D4D` | Crimson — Oversold alert, offline error, delete |
| `textPrimary` | `#F4F5F6` | Primary headlines, product names, price |
| `textSecondary` | `#9DA5B4` | Subtitles, SKU, secondary metadata |
| `textMuted` | `#5A6270` | Inactive icons, timestamps, placeholders |

---

## 2. Typography & Formatting Rules

1. **Numeric Figures & Currency:**
   - Always use tabular figures / monospace font for prices (`Rp 25.000`) and stock counts (`x12`).
   - Prevents layout jitter when numbers change rapidly during scanning and checkout.
2. **Text Hierarchy:**
   - Title / Hero: 20sp - 24sp, SemiBold / Bold, tight letter spacing.
   - Body / Product Name: 14sp - 16sp, Medium.
   - Metadata / SKU / Status: 11sp - 12sp, Regular / Monospace.

---

## 3. Anti-Slop Component Guidelines

1. **Buttons & Actions:**
   - Minimum tap target: 48dp x 48dp.
   - Border radius: 8dp - 12dp (clean, sharp, industrial).
   - Never use emoji icons in buttons (e.g. no "🛒 Beli" or "✅ Simpan"). Use clean standard vector icons.
   - Primary action (Bayar): Solid `accentPrimary` (`#C7F53B`) with dark text (`#16181C`) for maximum contrast and zero squinting under bright daylight or dim stalls.
2. **Product Cards:**
   - 1px hairline border (`#2A2E35`) on `surfacePrimary` (`#1E2228`).
   - Zero diffuse 20px blur shadows. Flat, crisp elevation.
   - Instant visual stock badge:
     - Stock > 5: subtle muted count (`#9DA5B4`)
     - Stock 1 - 5: Warning Amber (`#F5A623`)
     - Stock <= 0: Crimson Alert (`#FF4D4D` / "Habis")
3. **Receipt Preview:**
   - Monospaced thermal-paper preview (58mm / 80mm).
   - High density, clear separator lines (`--------------------------------`).

---

## 4. Sync State Visual Indicator

| State | Indicator | Visual Contract |
|---|---|---|
| **Synced (Online)** | Mint Dot + "Tersinkron" | `#4EE5B6` dot, 12sp muted label |
| **Pending Outbox** | Amber Badge + `N` pending | `#F5A623` pill badge with item counter |
| **Offline** | Subtle Slate Dot + "Offline" | `#5A6270` dot, cashier stays functional |
| **Syncing** | Pulsing Mint Dot | Subtle 1s breath cycle |
