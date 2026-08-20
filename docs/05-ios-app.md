# 05 — The iOS app

## 5.1 Foundations

SwiftUI, iOS 26 minimum, Swift 6 with strict concurrency. No external dependencies: charts
from Swift Charts, networking from URLSession, storage from JSON plus the Keychain.

iOS 26 as the floor is what gives the floating Liquid Glass tab bar for free. On iOS 18 it
would have to be rebuilt by hand, which is hundreds of lines of custom UI for no gain.

## 5.2 Structure

```
TabView (Liquid Glass, .tabBarMinimizeBehavior(.onScrollDown))
├── Server     server list, pairing, per-server settings
├── Metrics    the live screen — default tab
├── Tools      network, hardware and system tools
└── Settings   units, real-time behaviour, privacy, paired devices, language
```

Hardware information has no tab of its own. It lives as detail screens reachable from two
places: the identity card at the top of **Metrics** (you are looking at a live CPU graph and
want to know what CPU it is), and a **Hardware** section in Tools (you went looking for it
deliberately). Hardware detail is something you open a few times per server and then never
again — that does not deserve permanent space in the tab bar.

A **bottom accessory** floats above the tab bar with the selected server and its live
CPU/RAM, so you always know which machine you are looking at. Lists get extra bottom
content margin so their last row is not hidden underneath it.

## 5.3 State

```swift
@Observable @MainActor final class AppState {
    var servers: [Server]
    var selectedID: UUID?
    var connection: ConnectionState   // idle / connecting / live / reconnecting / failed
    var system: SystemInfo?
    var latest: Sample?
    var history = RingBuffer<Sample>(capacity: 300)
}
```

The ring buffer has a **fixed size**. A growing array is the classic reason monitoring apps
sit at 400 MB after an hour.

## 5.4 The 1 Hz pipeline

```
URLSession.bytes(for:) → AsyncLineSequence → SSE parser → JSONDecoder → Sample → @MainActor
```

Rules that keep it smooth:

1. Stream only while the screen is visible; `.task(id:)` cancels it on the way out.
2. Stop on background — iOS would kill it anyway, and closing cleanly avoids a frozen
   second on return.
3. Reconnect with backoff 1 → 2 → 5 → 10 s, shown as a discreet pill, never an alert.
4. `.contentTransition(.numericText())` and `.monospacedDigit()` on everything that changes
   every second. Without monospaced digits the layout visibly wobbles, because `1` is
   narrower than `8`.
5. No `Timer` for the clock — the sample's own timestamp is the truth.

## 5.5 Networking

One code path for all four connection profiles: always send the client certificate, always
validate the server against the CA received at pairing.

Two subtleties cost real debugging time and are worth knowing:

- **The TLS challenge for a stream arrives at task level.** Ordinary requests via
  `URLSession.data(for:)` land in `urlSession(_:didReceive:)`, but `URLSession.bytes(for:)`
  uses `urlSession(_:task:didReceive:)`. With only the first implemented, every endpoint
  worked and only the live stream was rejected.
- **URLSession opens several connections in parallel** and races them. During pairing the
  first one succeeded, which closed the pairing window, and the second then failed the
  handshake — so a successful pairing reported "the network connection was lost". The
  pairing session is now limited to one connection per host, and the agent keeps accepting
  unauthenticated connections for 15 seconds after a successful pairing.

## 5.6 Stale data

When the stream drops, the last known values stay on screen — a blank screen tells you
less than old numbers do — but they are **dimmed**, a banner reports how long ago the last
update was, and the uptime counter **stops**. Letting uptime tick on would assert the
server is still running, which is exactly what is no longer known.

## 5.7 The screens

**Server** — cards with a live status dot, CPU/RAM/uptime and a sparkline, polled every
5 s (not 1 s: enough to see whether a machine is alive without loading several of them).
Tap to select, swipe to edit or delete.

**Metrics** — identity card (model, storage, chip, memory, uptime, reboot date), four
gauges (CPU, RAM, storage, load), a network section with a live chart, temperature with
history, quick links to GPU and sensors, and a sensor grid.

**Tools** — grouped list: network tools (speed, ping, DNS, traceroute, WHOIS), hardware
(CPU detail, sensors, SMART, interfaces, overview) and system (log analyzer, updates,
processes, locale, uptime).

**Settings** — units, history window, privacy toggles, paired devices with swipe-to-revoke,
and the language switch.

## 5.8 Charts

The network chart caused two rounds of fixes and both are worth recording:

- **The scale is held in state with hysteresis.** Recomputing it from the current peak
  every second made the whole chart rescale continuously, which reads as flicker. It now
  grows immediately and only shrinks after ten quiet seconds.
- **The peak is taken over the visible window only.** It was computed over the whole
  300-sample buffer, so a spike from four minutes ago inflated the scale while being
  invisible — and 600 marks were being drawn where 120 were shown.
- **`chartPlotStyle { $0.clipped() }`**, or line and fill spill past the card edge.
- **Y labels are drawn as an overlay inside the plot**, not as axis labels. Axis labels
  reserve width on the left, which made the chart narrower than the sparkline below it.

## 5.9 Localisation

English is the default. Dutch is offered **only when the device language is Dutch** —
otherwise it is a choice nobody who sees it wants.

Rather than `.strings` files, translations sit inline: `T("Storage", "Opslag")`. For a
two-language personal app that is deterministic, works naturally with string interpolation,
switches instantly without restarting, and keeps the translation next to the text it
belongs to. The trade-off is that it is not the idiomatic Apple mechanism and cannot be
handed to a translator — acceptable here, and worth revisiting if a third language ever
appears.

## 5.10 Verification

`NodeStatusUITests` walks the whole app and writes 19 screenshots to
`/tmp/nodestatus-shots/`. It is not an assertion test but a visual one: run it, look at the
images, compare against the reference. It caught the hidden last row, the flickering chart
and several layout regressions.

```bash
cd ios && xcodebuild -project NodeStatus.xcodeproj -scheme NodeStatus \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Two launch arguments exist **only in DEBUG builds**: `-SIPairURL <nodestatus://enroll?…>`
pairs automatically at launch, and `-SITab server|metrics|tools|settings` opens a specific
tab. They exist because the simulator has no camera.
