# 06 — Design system

Built to match the reference screenshots, and aligned with the iOS 26 (Liquid Glass)
guidance. Three rules from that guidance apply directly here:

- **Glass is for the navigation layer** — tab bar, nav bar, accessory. Content cards stay
  opaque. That is exactly what the reference shows: a floating glass tab bar above flat,
  dark cards.
- **Text never sits directly on glass.** Contrast at least 4.5:1.
- **Hierarchy through depth**, not through more colour.

## Colours

| Token | Dark | Use |
|---|---|---|
| `bg/base` | `#000000` | Screen background |
| `bg/card` | `#1C1C1E` | Cards |
| `bg/cardElevated` | `#2C2C2E` | Nested blocks |
| `stroke/hairline` | white 8% | 0.5 pt card border |
| `text/primary` | `#FFFFFF` | Values, titles |
| `text/secondary` | `#EBEBF5` 62% | Labels |
| `text/tertiary` | `#EBEBF5` 32% | Axes, hints |
| `accent` | systemBlue | Selection, links, active tab |

Status colours are tied to thresholds, not chosen ad hoc: green below 70%, orange 70–89%,
red at 90% or above. For temperatures the rule is 85% of the critical threshold.

## Gradients

| Metric | From | To |
|---|---|---|
| CPU, RAM | `#0A84FF` | `#32D0FF` |
| Storage | `#FF2D9B` | `#FF453A` |
| Load | `#30D158` | `#66E39A` |
| Network up / down | `#30D158` / `#0A84FF` | line only |

The gradient runs across the **full width of the bar**, not across the filled portion — so
22% has the same colour ramp as 80%. Subtle, and the difference between looking designed
and looking cheap.

## Type

| Role | Style |
|---|---|
| Screen title | `.largeTitle` bold |
| Card title | `.headline` |
| Large value | `.title2` bold, **`.monospacedDigit()`** |
| Label | `.subheadline` |
| Chart axis | `.caption2` tertiary |

`.monospacedDigit()` is mandatory on anything that updates every second.

## Metrics

| Element | Value |
|---|---|
| Card radius | 20 pt, continuous |
| Icon tile | 32×32, radius 10 |
| Card padding | 16 pt |
| Gap between cards | 12 pt |
| Gap between sections | 24 pt |
| Bar height | 8 pt, capsule |
| Grid | `LazyVGrid`, adaptive minimum 160 pt |

## Components

**`Card`** — the dark surface with a hairline border.
**`IconTile`** — 32×32 rounded tile, 20% tint fill, SF Symbol in the full tint.
**`GaugeBar`** — capsule track, gradient fill, `.easeOut(0.35)` animation, minimum 6 pt so
0.3% is a dot rather than nothing.
**`SegmentedGaugeBar`** — several volumes in one bar, 1 pt separators, tints interpolated
along the same magenta→red ramp. With one volume it collapses to a plain bar.
**`MetricTile`** — icon, title, bar, caption left and value right on one line; the caption
shrinks, the value never does.
**`NetworkChart`** — two `AreaMark` + `LineMark` layers, monotone interpolation, dashed
grid lines, scale labels overlaid inside the plot.
**`ThroughputChart`** — live speedtest, coloured by phase so the switch from download to
upload is visible.

## Motion

| What | Duration |
|---|---|
| Bar fill | 0.35 s easeOut |
| Number changes | `.contentTransition(.numericText())` |
| New chart point | none — the series shifts, no per-mark animation |
| Section expand | `.spring(response: 0.35, dampingFraction: 0.85)` |
| Status colour change | 0.6 s easeInOut, so a value sitting on a threshold does not strobe |

All of it respects Reduce Motion.
