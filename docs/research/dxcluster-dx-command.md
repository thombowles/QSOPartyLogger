# DX cluster — posting a spot (`DX` command) — banked official sources

All fetched 2026-08-15. The two node families the app is verified against
(README: `dxc.wa9pie.net:8000` is DXSpider, `dxc.nc7j.com:7373` AR-Cluster)
document the same command; the app uses the one form both accept. No other
logger was consulted for the wording.

## DXSpider User Manual v1.51 — "Getting and posting DX"

`https://www.dxspider.org/usermanual_en-4.html` (fetched 2026-08-15; the same
text at `https://wiki.dxcluster.org/wiki/Getting_and_posting_DX`).

- Syntax: *"dx (frequency) (callsign) (remarks)"* — *"frequency is in
  kilohertz and the callsign is the callsign of the station you have worked or
  heard, (ie not your own callsign!)."*
- *"DXSpider will allow the frequency and callsign fields to be entered in any
  order."* Examples, all equivalent:
  `dx 14004 pa3ezl OP Aurelio 599`, `dx pa3ezl 14004 OP Aurelio 599`,
  `dx pa3ezl 14.004 OP Aurelio 599`.
- *"The remarks section allows you to add information like the operators name
  or perhaps a location."*
- Distribution and **the confirmation the app relies on**: *"This posting, or
  callout as it is known, will be forwarded to all other connected stations
  both at the cluster you are connected to and other active clusters in the
  network. The callout will also be sent to you as proof of receipt."*
- No maximum length is stated for the remarks or the callsign.

## DXSpider User Command Reference

`https://wiki.dxcluster.org/wiki/DXSpider_User_Command_Reference` (page last
modified 17 July 2025; fetched 2026-08-15).

- `dx [by <call>] <freq> <call> <remarks> - Send a DX spot`
- *"You can credit someone else by saying: `DX by G1TLH FR0G 144.600 he isn't
  on the cluster`"* — the `by` form is not used by this app.
- The node compares the frequency against its band table (`SHOW/BANDS`).

## AR-Cluster — DX command

`https://www.ng3k.com/Cluster/dx.html` (a mirror of the AR-Cluster user
manual's DX page; fetched 2026-08-15. The k3lr.com WebCluster copy of the same
manual refused the connection that day.)

- Syntax: *"DX frequency callsign misc-info"*, frequency *"14025.10, for
  example"*.
- *"Misc-info should be kept brief as the system will add the date and time
  after it."* *"Misc-info is optional."*
- The manual's own example: `DX/K1GQ 14001.1 3C0A`.

## What this bakes into the app

- `ClusterSpot.command` writes `DX <kHz> <CALL> <remarks>` — frequency
  first, which is the order both families document; kilohertz, up to two
  decimals, no trailing zeros; the call upper-cased; the remarks after.
- The remarks are the party's Cabrillo contest name, then the county (a
  cluster has no county field of its own), then whatever the operator typed —
  each optional, single-spaced, and sanitised of CR/LF and control characters,
  because a newline would end the command and send the rest as a second one.
  No length cap is enforced, since neither manual states one; the whole line
  is previewed in the sheet before it goes.
- Confirmation is the node's echo — the manual's *"proof of receipt"*: an
  incoming spot whose spotter is the login call and whose call and frequency
  are the ones just sent. A missing echo is never a failure — a node-side
  filter can hide it — so the receipt stays at "sent" rather than guessing.
- The command goes down the existing session (`SpotClient.send`), so it is
  only ever available while a node is connected — and never under a
  NON-ASSISTED declaration, which cannot connect (`SpottingPolicy`).
