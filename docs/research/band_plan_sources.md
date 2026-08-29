# Band plan provenance — CW/phone crossover per band

Banked research for `Sources/Core/Models/BandPlan.swift`. Two sources, in
priority order. Where they disagree the *higher* (more conservative) frequency
wins, so the app never puts a radio into phone below the legal phone edge.

## Source 1 — 47 CFR §97.305(c), "Authorized emission types"

Read 2026-07-25 from Cornell LII (<https://www.law.cornell.edu/cfr/text/47/97.305>);
`ecfr.gov` 302-redirects to an interstitial and could not be fetched directly.
This is the authority for **where phone/image emissions are permitted at all**.
It is an emission-type table, not a license-class table — the stricter
General/Advanced phone edges in §97.301(a) are deliberately *not* used, because
the logger does not know the operator's license class and putting the radio in
SSB is not itself an unlawful act.

| Wavelength band | Frequencies | Emission types authorized |
| --- | --- | --- |
| 160 m | Entire band | RTTY, data / phone, image |
| 80 m | Entire band | RTTY, data |
| 75 m | Entire band | Phone, image |
| 40 m | 7.000–7.100 MHz | RTTY, data |
| 40 m | 7.075–7.100 MHz | Phone, image |
| 40 m | 7.100–7.125 MHz | RTTY, data |
| 40 m | 7.125–7.300 MHz | Phone, image |
| 30 m | Entire band | RTTY, data *(no phone row)* |
| 20 m | 14.00–14.15 MHz | RTTY, data |
| 20 m | 14.15–14.35 MHz | Phone, image |
| 17 m | 18.068–18.110 MHz | RTTY, data |
| 17 m | 18.110–18.168 MHz | Phone, image |
| 15 m | 21.0–21.2 MHz | RTTY, data |
| 15 m | 21.20–21.45 MHz | Phone, image |
| 12 m | 24.89–24.93 MHz | RTTY, data |
| 12 m | 24.93–24.99 MHz | Phone, image |
| 10 m | 28.0–28.3 MHz | RTTY, data |
| 10 m | 28.3–29.7 MHz | Phone, image |
| 6 m | 50.1–54.0 MHz | MCW, phone, image, RTTY, data |
| 2 m | 144.1–148.0 MHz | MCW, phone, image, RTTY, data, test |

Notes taken from the table:

- **6 m and 2 m** have no phone row below 50.1 / 144.1 MHz, so 50.000–50.100 and
  144.000–144.100 are CW-only. Those are the crossovers used.
- **30 m** has no phone row at all. Phone is never authorized; the app treats
  the whole band as CW.
- The **40 m 7.075–7.100 phone** row is the ITU Region 1/3 and Pacific-area
  allowance, not a mainland-US privilege, so the mainland crossover is 7.125.

## Source 2 — 47 CFR §97.301(a), for the 80 m / 75 m numeric boundary

Read 2026-07-25 from Cornell LII (<https://www.law.cornell.edu/cfr/text/47/97.301>).
§97.305(c) names the 80 m and 75 m bands without giving MHz, so the boundary
comes from the Amateur Extra allocation table:

- 80 m — "3.500–3.600" MHz, all ITU regions
- 75 m — "3.600–3.800" (Region 1), **"3.600–4.000" (Region 2)**, "3.600–3.900" (Region 3)

The US is Region 2, so the 80/75 m phone crossover is **3600 kHz**.

## Source 3 — ARRL band plan (<https://www.arrl.org/band-plan>), read 2026-07-25

The voluntary US band plan. Used only where §97.305(c) permits phone across a
whole band and therefore cannot supply a crossover — that is 160 m alone.
Quoted verbatim from the page:

- 160 m: `"1.800 - 2.000 CW"`, `"1.800 - 1.810 Digital Modes"`, `"1.810 CW QRP"`,
  **`"1.843-2.000 SSB, SSTV and other wideband modes"`**, `"1.910 SSB QRP"`,
  `"1.995 - 2.000 Experimental"`, `"1.999 - 2.000 Beacons"`
- 6 m: `"50.0-50.1 CW, beacons"`, `"50.1-50.3 SSB, CW"`, `"50.125 SSB calling"` —
  agrees with §97.305(c) at 50.1
- 2 m: `"144.00-144.05 EME (CW)"`, `"144.05-144.10 General CW and weak signals"`,
  `"144.10-144.20 EME and weak-signal SSB"` — agrees with §97.305(c) at 144.1

## Bands deliberately left with no crossover

- **60 m** — five channels, USB by rule with CW/data also permitted. There is no
  CW/phone split to infer from a frequency.
- **1.25 m, 70 cm** — all-mode allocations whose band plans are organised by
  activity (EME, beacons, repeater pairs, FM simplex), not by a single CW→phone
  boundary.

On these bands the app leaves the mode alone.

## Source 4 — sideband convention (which sideband "SSB" means)

Read 2026-08-29. Authority for `BandPlan.sidebandRawMode(atKHz:)`.

**IARU Region 2 Band Plan, September 2020**
(<https://www.iaru-r2.org/wp-content/uploads/2020/02/IARU-Region-2-Band-plan.pdf>),
Definitions, page 4, quoted verbatim:

> **Upper Sideband (USB) and Lower Sideband (LSB):** For SSB phone operations
> below 10 MHz use lower sideband (LSB); above 10 MHz use upper sideband
> (USB). Exception: On 60 m band (5.3 MHz) the best practice is to use upper
> sideband (USB).

That one sentence is the whole rule, 60 m exception included. The 60 m
exception is also US regulation, stated in engineering terms:

- **47 CFR §97.303(h)(3)** (<https://www.law.cornell.edu/cfr/text/47/97.303>,
  read 2026-08-29): phone on the discrete channels is emission designator
  2K80J3E, and operators *"may set the carrier frequency 1.5 kHz below the
  center frequency"* — a suppressed carrier below the occupied bandwidth,
  which is an upper-sideband carrier.
- **ARRL 60 Meter FAQ** (<https://www.arrl.org/60-meter-faq>, read
  2026-08-29): *"Effective March 5, 2012 the FCC has permitted CW, USB, and
  certain digital modes on the channelized segment of 60m"*, and the channel
  center is *"1.5 kHz above the suppressed carrier frequency of a transceiver
  operated in the Upper Sideband (USB) mode."*

The ARRL band plan page (Source 3) and the R2 plan's band tables say nothing
about sideband choice; the R2 Definitions entry above is the only place any of
the banked sources states the convention outright.

## Behaviour reference — N1MM Logger+

Read 2026-07-25.

- Configurer → Mode Control (<https://n1mmwp.hamdocs.com/setup/the-configurer/>)
  offers "Follow band plan" among the mode sources, and the manual states the
  program *"does not switch the radio automatically to a digital mode if you
  click within a digital band segment."* This app follows that rule: the band
  plan can select CW or SSB and never a digital mode.
- Bandmap window (<https://n1mmwp.hamdocs.com/manual-windows/bandmap-window/>):
  dupes are shown in **gray**, not removed — `"Gray: Dupe"`.
- Key assignments (<https://n1mmwp.hamdocs.com/setup/keyboard-shortcuts/>):
  `"Ctrl+Down Arrow – Get next spot higher in frequency."` N1MM does not
  document dupe-skipping on that key; skipping worked stations in ⌘←/⌘→ is this
  app's own choice, requested by the operator.
