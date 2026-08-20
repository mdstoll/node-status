# 05 — iOS-app

## 5.1 Uitgangspunten

- **SwiftUI**, minimum **iOS 26**, Swift 6 met strict concurrency.
- Xcode 26.6 en Swift 6.3 staan al op je Mac ✅.
- Doel-device: iPhone 16 Pro, iOS 26.6 (uit je screenshots). Dark mode is de primaire
  look; light mode wordt correct ondersteund maar is niet leidend.
- Géén externe dependencies. Charts komt uit Swift Charts, netwerk uit URLSession,
  opslag uit SwiftData + Keychain.

**Waarom iOS 26 als minimum:** de zwevende capsule-tabbar met glaseffect uit je
screenshots is de standaard `TabView`-rendering in iOS 26 (Liquid Glass). Op iOS 18 zou je
die volledig met de hand moeten namaken. Aangezien je toestel op 26.6 zit, kost dat minimum
je niets en scheelt het honderden regels custom UI-code.

## 5.2 Navigatiestructuur

**Vastgesteld: vier tabs — Server / Metrics / Tools / Settings.**

```
TabView (Liquid Glass, .tabBarMinimizeBehavior(.onScrollDown))
├── Tab "Server"    systemImage: "server.rack"
│    └── NavigationStack → ServerListView → ServerDetail/EditView
├── Tab "Metrics"   systemImage: "chart.bar.xaxis"        ← default tab
│    └── NavigationStack → MetricsView → Hardware/GPU/Sensors-details
├── Tab "Tools"     systemImage: "wrench.and.screwdriver"
│    └── NavigationStack → ToolsListView → per-tool detailschermen
└── Tab "Settings"  systemImage: "gearshape"
     └── NavigationStack → SettingsView
```

Er is bewust **geen aparte Hardware-tab**. De statische hardware-informatie (SMART, DIMM's,
NIC's, block devices, GPU-specificaties) leeft op twee plekken die dichter bij de vraag
zitten die je op dat moment hebt:

- **Vanuit Metrics** — tik op de identiteitskaart bovenaan, of op de `GPU`/`Sensors`-knoppen,
  en je duikt door naar het bijbehorende hardware-detailscherm. Je ziet iets in de
  live-data en wilt weten *wat* het is: één tik.
- **Vanuit Tools** — een eigen sectie **Hardware** met rijen naar dezelfde schermen, voor
  als je gericht naar hardware-informatie op zoek bent zonder eerst langs de metrics te gaan.

Dat scheelt een tab, houdt de tabbar in de vorm die je wilt, en het scheelt de gebruiker
een scherm dat je in de praktijk maar een paar keer per server opent.

**Bottom accessory (aanrader):** iOS 26 kent `.tabViewBottomAccessory { }` — een strook
die boven de tabbar zweeft. Perfect om altijd de **geselecteerde server + live CPU/RAM**
te tonen, ongeacht in welke tab je zit. Precies de functie die je beschrijft
("als je op een ander menu-item drukt, zie je die van de geselecteerde server").

```swift
enum AppTab: Hashable { case server, metrics, tools, settings }
```

De tab-set is één enum met één `TabView`-body; toevoegen of hernoemen is een lokale
wijziging op één plek.

## 5.3 State-model

```swift
@Observable final class AppState {
    var servers: [Server]           // uit SwiftData
    var selectedServerID: UUID?
    var connection: ConnectionState // .disconnected / .connecting / .live(since:) / .failed(Error)
    var preferences: Preferences    // uit Settings-tab, zie §5.11
}

@Observable final class MetricsStore {          // één per geselecteerde server
    private(set) var system: SystemInfo?         // /v1/system, 60 s cache
    private(set) var latest: Sample?             // laatste SSE-sample
    private(set) var history: RingBuffer<Sample> // 300 samples = 5 min
    var cpuSeries:  [ChartPoint] { ... }
    var netSeries:  (rx: [ChartPoint], tx: [ChartPoint]) { ... }
}
```

- `MetricsStore` is een `@MainActor`-geïsoleerde `@Observable` klasse; de SSE-parsing
  gebeurt in een detached task en levert samples via een `AsyncStream` aan.
- De **ringbuffer heeft een vaste grootte** — nooit een groeiende array; dat is de klassieke
  reden waarom monitoring-apps na een uur 400 MB gebruiken.
- Views observeren alleen wat ze nodig hebben. De netwerkgrafiek observeert `netSeries`,
  het CPU-blok alleen `latest.cpu` — anders hertekent iOS 26× per seconde het hele scherm.

## 5.4 Real-time pipeline (1 Hz)

```
URLSession.bytes(for: streamRequest)
   → AsyncLineSequence
   → SSEParser (event:/id:/data:)
   → JSONDecoder → Sample
   → await MainActor.run { store.append(sample) }
   → SwiftUI hertekent alleen de views die dat sample lezen
```

Regels die dit werkbaar houden:

1. **Alleen streamen als het scherm zichtbaar is.** `.task(id: selectedServerID)` op de
   Metrics-view start de stream; verlaten van de view cancelt hem automatisch.
2. **Stoppen bij achtergrond.** `scenePhase == .background` → stream sluiten. iOS zou hem
   toch binnen ~30 s killen; netjes sluiten voorkomt een halve seconde bevroren UI bij
   terugkeren.
3. **Herverbinden met backoff** 1 s → 2 s → 5 s → 10 s (max), plus meteen een poging bij
   `NWPathMonitor`-netwerkherstel. UI toont een discrete "reconnecting…"-pill, geen alert.
4. **Animatie.** Voortgangsbalken animeren met `.animation(.easeOut(duration: 0.35), value:)`
   — genoeg om vloeiend te ogen, kort genoeg om bij 1 Hz niet achter te lopen. Getallen
   krijgen `.contentTransition(.numericText())` zodat cijfers rollen in plaats van
   springen. Dat is precies het detail dat de app "af" laat voelen.
5. **Geen `Timer` op de main thread** voor de UI-klok; de sample-`t` uit de server is de
   waarheid.

## 5.5 Netwerk-laag

```swift
actor APIClient {
    init(server: Server, credentials: Credentials)   // token + pinned SPKI hash
    func get<T: Decodable>(_ path: String) async throws -> T
    func post<T: Decodable>(_ path: String, body: Encodable) async throws -> T
    func stream(_ path: String) -> AsyncThrowingStream<Sample, Error>
}
```

- **Client-certificaat (mTLS).** De `URLSessionDelegate` beantwoordt
  `NSURLAuthenticationMethodClientCertificate` met de `SecIdentity` van deze server uit de
  Keychain. Zonder die identiteit komt er geen verbinding tot stand — dat is de kern van
  [10 — Device enrollment](10-device-enrollment.md).
- **Servervalidatie tegen de per-server CA.** Bij `NSURLAuthenticationMethodServerTrust`
  evalueert de app het servercertificaat tegen het **CA-certificaat dat bij enrollment is
  ontvangen** (`SecTrustSetAnchorCertificates`). Dus geen TOFU, geen fingerprint-vergelijking
  en geen afhankelijkheid van publieke CA's — ook niet op `a.mest.dev`. Een servercert dat
  niet door die CA is uitgegeven, wordt geweigerd.
- **Token-header:** standaard `Authorization: Bearer`, met een schakelaar per server naar
  `X-Server-Info-Token` voor servers achter een proxy die zelf basic auth gebruikt.
  De app probeert bij *Test verbinding* beide en onthoudt wat werkte.
- **Basis-pad:** de host mag een pad-prefix bevatten (`a.mest.dev/_si`); de `APIClient`
  plakt endpoints daar correct achter.
- **Dual-host failover:** `lan_host` en `remote_host` worden parallel geprobeerd
  (`withTaskGroup`, eerste succes wint, 300 ms head start voor LAN).
- **Hostnames boven IP-literals voor remote hosts.** Op IPv6-only mobiele netwerken
  (NAT64/DNS64 — Apple vereist dat apps daar werken) faalt een hardgecodeerd IPv4-adres
  terwijl een hostname het wél doet. De app waarschuwt bij een IPv4-literal als remote host.
- **Timeouts:** 5 s voor gewone requests, geen timeout op de stream (keep-alive bewaakt hem).
- **Info.plist:** `NSAllowsLocalNetworking` voor .local/IP-literals + de
  `NSLocalNetworkUsageDescription`-string die iOS toont bij het eerste LAN-contact.
  Voor `.system`-servers is géén ATS-uitzondering nodig.

## 5.6 Tab "Server"

**Leeg** — grote SF Symbol, "Nog geen servers", knop *Server toevoegen*, plus een tweede
knop *QR scannen*.

**Gevuld** — een lijst kaarten, per server:

```
┌──────────────────────────────────────────────┐
│ ● web-01                      ✓ selected     │  ● groen = online, grijs = offline,
│   192.168.1.50 · Ubuntu 24.04                │      oranje = reconnecting
│   ▁▂▅▃▂▁  CPU 22%   RAM 89%   up 1d 18h      │  mini-sparkline, ververst op 5 s
└──────────────────────────────────────────────┘
```

- **Tik** = selecteren (haptische tik + de vinkje-badge verspringt). Er is altijd precies
  één geselecteerde server; die keuze wordt bewaard tussen sessies.
- **Swipe** = Bewerken / Verwijderen. Long-press = contextmenu met *Nu verversen*,
  *Token vernieuwen*, *Dupliceren*.
- De lijst pollt op **5 s** (niet 1 s) met `sections=cpu,memory` — genoeg voor een
  statusindicatie, zonder vier servers tegelijk te belasten.

**Toevoegen — formulier**

| Veld | Type | Default |
|------|------|---------|
| Naam | tekst | uit `/v1/system` na verbinden |
| Host (LAN) | tekst | — |
| Host (extern, optioneel) | tekst, mag pad bevatten (`a.mest.dev/_si`) | — |
| Poort | nummer | 29500 (leeg bij een proxy op 443) |
| Token | secure field / plak / QR | — |
| Koppelcode | uit de QR, of handmatig | — |
| Apparaatnaam | tekst | toestelnaam |
| Kleur/icoon | picker | willekeurig |

Onderaan een **Test verbinding**-knop die `/v1/health` en `/v1/system` doet en het
resultaat inline toont (versie, hostname, OS, capabilities) vóór je opslaat. Opslaan kan
pas na een geslaagde test — dat voorkomt de grootste bron van "waarom doet-ie niks".

**Koppelen via QR (de standaardroute):** de scanner leest
`serverinfo://enroll?h=192.168.1.50&p=29500&fp=<sha256>&c=K7QM3XR9&n=web-01`. De app
genereert een sleutelpaar, stuurt een CSR, en krijgt certificaat, CA en token terug — de
gebruiker ziet alleen een voortgangsbalkje en daarna de server in de lijst. Het handmatige
formulier hierboven is de terugvaloptie als de QR niet gescand kan worden.

**Instructiescherm.** Voordat de camera opengaat, toont de app het commando dat op de
server gedraaid moet worden, met een kopieerknop:

```
curl -fsSL https://get.<jouwdomein>/si | sudo bash
```

Daaronder: "Scan daarna de QR die in je terminal verschijnt." Dat is de volledige
onboarding — zie [10 §10.3](10-device-enrollment.md#103-de-koppelflow-klik-en-klaar).

**Serverdetail** (tik op de naam in plaats van op de kaart, of via het contextmenu):
verbindingsstatus, gemeten latency, agent-versie, capabilities, en per-server instellingen
die de globale defaults uit [§5.11](#511-tab-settings) overschrijven (refresh-interval,
mag-speedtesten, welke secties zichtbaar zijn).

## 5.7 Tab "Metrics"

Exact de opbouw uit je screenshots, van boven naar beneden:

### A. Header
`Device Status` in `.largeTitle.bold()`, subtitel `Real-time monitoring · web-01`.
Rechts een kleine live-indicator (pulserend groen bolletje + "LIVE").

### B. Identiteitskaart — tevens ingang naar Hardware
Icoon links (server.rack in een afgeronde gekleurde tegel), daarnaast hostname groot en
`Ubuntu 24.04.1 (6.8.0-45)` eronder. Daaronder een 2×3-grid:

| Model | Storage |
|-------|---------|
| Chip | Memory |
| Uptime | Reboot Date |

Labels in `.subheadline` wit, waarden in `.subheadline` secundair grijs — net als in je
screenshot. Uptime telt **live** door (`1d 18h 54m 47s`), berekend uit `boot_time` +
de wandklok, dus zonder serververkeer.

De hele kaart is tapbaar en heeft rechtsonder een subtiele chevron: tik → **Hardware-detail**
([§5.8](#58-hardware-detailschermen)). Zo blijft de hardware-informatie één tik weg zonder
een eigen tab te kosten.

### C. Vier metrische tegels (2×2)

| Tegel | Balk-gradient | Extra tekst |
|-------|---------------|-------------|
| **CPU** | blauw → cyaan | `64.4%` groot rechts |
| **RAM** | blauw → cyaan | `6.7 G / 7.5 G` links, `89.4%` rechts |
| **Storage** | magenta → rood | `163.1 G / 255.4 G` links, `63.9%` rechts |
| **Load / Swap** | groen → mint | `0.84 / 0.61 / 0.55` (vervangt "Battery" — een server heeft geen accu) |

Zie [06 — Designsysteem](06-design-system.md) voor exacte kleuren en de `GaugeBar`-component.

### D. Netwerk-sectie
- Kop met wifi/ethernet-icoon + interfacenaam.
- `Total Usage` met ↓ 3,5 GB en ↑ 1,8 GB (sinds boot).
- Rechtsboven in de chart de huidige snelheden: `5.1 K/s ↑` groen, `9.2 K/s ↓` blauw.
- **Chart:** Swift Charts, twee `AreaMark`+`LineMark`-lagen (groen up, blauw down), 60
  datapunten, gestippelde horizontale gridlijnen met schaal-labels links (`512 KB/s`,
  `384 KB/s`, …). De x-as heeft geen labels — alleen drie verticale stippellijnen.
- **Beweging van rechts naar links:** de x-as is `chartXScale(domain: -60...0)` met
  x = `sample.t - now`. Elk nieuw sample schuift alles automatisch naar links. De y-as
  gebruikt een "sticky max": schaal naar `max(historie) * 1.2`, afgerond op een mooie stap,
  en zakt pas terug na 10 s zonder piek — anders klapt de grafiek visueel heen en weer.
- Tik op de chart → detailscherm met per-interface uitsplitsing en een langere historie.

### E. Temperatuur-sectie
Grote waarde rechts (`29°C`, gekleurd naar status), met een sparkline eronder over de
laatste 5 minuten. Precies de layout uit je derde screenshot.

### F. GPU + Sensors (twee knoppen naast elkaar)
De `GPU | Screen`-rij uit je screenshot wordt `GPU | Sensors` — twee tappable helften met
icoon en label die naar de hardware-detailschermen navigeren. De GPU-helft is verborgen als
`capabilities` geen GPU bevat; dan vult Sensors de volle breedte.

### G. Sensors-sectie
Kop `Sensors` met een chevron om in/uit te klappen, rechts de badges
`✅ Available 12` en `❌ Not Available 2`. Daaronder een grid van 2 kolommen met per sensor
een ronde icoontegel + groen vinkje-badge + naam eronder, exact als je screenshot.
Tik op een sensor → waarde-detail met historie.

## 5.8 Hardware-detailschermen

Geen tab, maar een set `NavigationStack`-schermen die bereikbaar zijn vanuit **Metrics**
(identiteitskaart, GPU/Sensors-knoppen) én vanuit de **Hardware-sectie in Tools**
([§5.9](#59-tab-tools)). Eén overzichtsscherm `HardwareView` met secties, en per sectie een
dieper scherm:

| Scherm | Inhoud |
|--------|--------|
| **Systeem** | Vendor, product, serienummer (gemaskeerd), BIOS/firmware, virtualisatie, distro, kernel, architectuur |
| **CPU** | Model, sockets/cores/threads, caches, notabele flags, governor per core, huidige frequenties |
| **Geheugen** | Totaal, gebruikt/cached/buffers, swap, en per DIMM (slot, grootte, type, snelheid) als `dmidecode` beschikbaar is |
| **Opslag** | Per block device: model, grootte, type (NVMe/SSD/HDD), partities, filesystem, **SMART-health**, temperatuur, power-on-hours, wear level. RAID/LVM/ZFS-status als aanwezig |
| **Netwerk** | Per NIC: MAC, MTU, linksnelheid, IPv4/IPv6, gateway, DNS-servers, totaal verkeer |
| **GPU** | Kaart, driver, VRAM, klokken, temperatuur, vermogen, huidige processen |
| **Sensors** | Alle hwmon-chips gegroepeerd, per sensor waarde + drempels + historie-sparkline, filter op type |

Deze data komt uit `/v1/system` en `/v1/hardware/*` met 60 s cache — bewust niet uit de
1 Hz-stream, want het verandert niet.

## 5.9 Tab "Tools"

Gegroepeerde lijst, exact het patroon uit je vierde screenshot (gekleurde afgeronde
icoontegels, chevrons, secties met kopjes):

**Netwerk**
| Tool | Scherm |
|------|--------|
| Network Speed | Grote knop *Start test*, tijdens de run een animerende gauge; resultaat als drie grote cijfers (Download / Upload / Ping) + jitter, loss, server, ISP. Historie van eerdere tests eronder in een lijst met sparkline. |
| Ping | Doelveld, aantal, *Start*. Resultaat: live oplopende sparkline van RTT's + min/avg/max/mdev-tegels + packet loss. |
| DNS Query | Domein + recordtype-picker (A/AAAA/MX/TXT/NS/CNAME/SOA) + DNS-server-picker (systeem, 1.1.1.1, 8.8.8.8, custom). Resultaten als kaarten met TTL. |
| Traceroute | Hop-voor-hop verschijnend, met per hop RTT-balkje en reverse-DNS. |
| WHOIS | Domein → geparste kaart (registrar, aangemaakt, verloopt, nameservers) + ruwe tekst uitklapbaar. |

**Hardware** *(ingang naar de schermen uit [§5.8](#58-hardware-detailschermen))*
| Tool | Scherm |
|------|--------|
| CPU Information | Totaal/user/system-chart (drie lijnen, zoals je screenshot), per-core balkjes met historie-toggle, frequenties, governor, load-average-chart. |
| Sensors | Alle sensoren met waarden, drempels en historie. |
| Storage & SMART | Block devices, partities, health per schijf. |
| Memory | Totaal/gebruikt/cached/swap + DIMM-details. |
| Network Interfaces | Per NIC alle details en verkeer. |
| GPU | Alleen zichtbaar met GPU-capability. |

**Systeem**
| Tool | Scherm |
|------|--------|
| Processes | Volledige proceslijst, sorteerbaar op CPU / geheugen / naam, met zoekveld. Per regel een balkje voor het aandeel. Beantwoordt de vraag die "RAM 89%" oproept, zonder Metrics te overladen. |
| Log Analyzer | Zie [§5.10](#510-log-analyzer--hoe-dit-nuttig-wordt). |
| System & Updates | Aantal upgradable + security-badge, lijst pakketten met huidige→nieuwe versie, "reboot required"-banner, kernelversie, distro-EOL-datum, unattended-upgrades-status. **Read-only** — geen upgrade-knop (zie OQ-3). |
| Locale & Region | Exact het key/value-scherm uit je screenshot: locale identifier, region, language, preferred languages, keyboard, timezone + offset, calendar, first day of week, hour cycle, currency, NTP-sync. |
| Device Uptime | Uptime groot, boot-datum, load-average-chart over 5 min, en een lijst van de laatste 10 boots met duur. In plaats van de wake/sleep-donut uit je screenshot (niet zinvol op een server): een donut **CPU-tijd verdeeld over user / system / iowait / idle** sinds boot — dezelfde visuele taal, wel relevante data. |

Alle tools werken op de **geselecteerde server**; bovenaan de lijst staat een compacte rij
met servernaam en status, zodat je nooit per ongeluk op de verkeerde machine een speedtest
start.

### 5.10 Log Analyzer — hoe dit nuttig wordt

Je screenshot toont een importeer-flow voor een sysdiagnose; op een server is de
equivalente en veel bruikbaardere versie:

1. **Bronkeuze.** De app haalt `/v1/tools/logs/sources` op en toont wat er is:
   journal-units (ssh, nginx, docker, cron, ufw, kernel) en logbestanden. Elke bron toont
   het aantal regels in het laatste uur en het hoogste priority-niveau — zo zie je meteen
   waar iets mis is zonder te zoeken.
2. **Filterbalk.** Tijdvenster (15 m / 1 u / 24 u / 7 d), minimum-priority
   (error / warning / info / debug) en een zoekveld.
3. **Weergave.** Monospace-regels, links een gekleurd priority-streepje
   (rood err+, oranje warning, grijs info), tijd relatief ("2m geleden") met absolute tijd
   bij tik. Regels zijn selecteerbaar en deelbaar.
4. **Live tail.** Een schakelaar rechtsboven zet `/v1/tools/logs/stream` aan; nieuwe regels
   schuiven van onderen in met auto-scroll die pauzeert zodra je zelf omhoog scrollt.
5. **Samenvatting bovenaan** — een strook met tellingen per niveau over het gekozen venster
   en een mini-histogram van regels per minuut, zodat een piek meteen opvalt.

Dit is de reden om de log-tool te bouwen: niet om `journalctl` na te bouwen, maar om in
één blik te zien *waar* het druk of fout is.

## 5.11 Tab "Settings"

App-brede instellingen. Alles hier is een **globale default**; per server kun je ze
overschrijven in het serverdetail ([§5.6](#56-tab-server)). `.listStyle(.insetGrouped)`,
zelfde visuele taal als Tools.

**Weergave**
| Instelling | Opties | Default |
|-----------|--------|---------|
| Thema | Systeem / Licht / Donker | Systeem |
| Accentkleur | picker | Blauw |
| Standaardtab bij openen | Server / Metrics / Tools | Metrics |
| Secties in Metrics | herordenen + aan/uit per sectie | alles aan |

**Eenheden**
| Instelling | Opties | Default |
|-----------|--------|---------|
| Temperatuur | °C / °F | °C |
| Opslag & geheugen | GB (1000) / GiB (1024) | GB |
| Netwerksnelheid | bytes/s / bits/s | bytes/s |
| Tijdnotatie | 12u / 24u / systeem | Systeem |

**Real-time**
| Instelling | Opties | Default |
|-----------|--------|---------|
| Refresh-interval | 1 s / 2 s / 5 s | 1 s |
| Historievenster in charts | 1 / 5 / 15 min | 1 min (chart), 5 min (buffer) |
| Streamen op mobiel netwerk | aan / uit | aan |
| Terugvallen op polling als SSE faalt | aan / uit | aan |

**Privacy & beveiliging**
| Instelling | Opties | Default |
|-----------|--------|---------|
| App vergrendelen met Face ID | aan / uit | uit |
| Serienummers en publieke IP's maskeren | aan / uit | **aan** |
| Hostnames anonimiseren bij delen/screenshot | aan / uit | uit |
| Gekoppelde apparaten | per server een lijst, swipe om in te trekken | — |
| Certificaat-status | per server: verloopdatum + automatische vernieuwing | auto |

**Data**
| Instelling | Opties | Default |
|-----------|--------|---------|
| Waarschuwen vóór speedtest (verbruikt 1–3 GB) | aan / uit | **aan** |
| Speedtest-historie bewaren | 10 / 50 / uit | 10 |
| Alle lokale data wissen | knop met bevestiging | — |

**Over**
- App-versie + buildnummer, en per verbonden server de **agent-versie** met een
  waarschuwing als die ouder is dan de app verwacht (API-versie-mismatch).
- Link naar de agent-installatie-instructies en het `uninstall.sh`-commando — handig als je
  op je telefoon zit en wilt opzoeken hoe je een agent verwijdert.
- Diagnostiek: laatste 100 app-logregels, deelbaar. Geen analytics, geen crash-reporting
  naar derden — dat staat er expliciet bij.

## 5.12 Foutafhandeling en lege staten

Elk scherm heeft drie toestanden en die worden allemaal expliciet ontworpen:

| Toestand | Weergave |
|----------|----------|
| Geen server geselecteerd | Vriendelijke lege staat met knop naar de Server-tab |
| Server offline | Laatste bekende data **grijs/gedimd** + banner "Laatste update 2 min geleden" — nooit een leeg scherm |
| Feature niet beschikbaar | Sectie verborgen, of een rij "Vereist smartmontools op de server" met uitleg |
| Auth mislukt (401) | Alert met knop *Token bijwerken* die direct naar het edit-scherm gaat |
| Certificaat gewijzigd / niet door de CA getekend | Blokkerende waarschuwing, verbinding geweigerd |
| Client-certificaat verlopen of ingetrokken | Scherm "Opnieuw koppelen" met het commando om een nieuw venster te openen |

## 5.13 Toegankelijkheid en polish

- Dynamic Type tot XXL: kaarten groeien mee, grids vallen terug naar één kolom.
- VoiceOver-labels op elke gauge ("CPU-gebruik, 64 procent").
- Kleur is nooit de enige informatiedrager (status krijgt ook een icoon).
- Haptics: lichte tik bij serverselectie, succes-notificatie bij afgeronde speedtest.
- `Reduce Motion` → chart-animaties uit, waarden springen direct.
- Live Activity / Dynamic Island voor een lopende speedtest is een leuke stretch goal
  (en past bij de "Show In Dynamic Island"-knoppen uit je screenshots).
