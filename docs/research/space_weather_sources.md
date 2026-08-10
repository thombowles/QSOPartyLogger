# Space weather provenance — SWPC endpoints, payload shapes, modifier table

Banked research for `Sources/Core/Models/SpaceWeather.swift` and
`Sources/App/SpaceWeatherClient.swift`. Every endpoint below was fetched and
its response captured before a line of parser was written; the captures are the
test fixtures, so the parser is tested against what the server actually sends
rather than against what its documentation implies.

All NOAA/SWPC content is US Government work.

## Endpoint 1 — F10.7 cm solar flux (SFI)

`https://services.swpc.noaa.gov/json/f107_cm_flux.json`

Fetched 2026-08-09 18:27:42 GMT. `HTTP/2 200`, `content-type: application/json`,
`content-length: 23013`, `cache-control: max-age=60`. Captured whole as
`Tests/Fixtures/SpaceWeather/swpc_f107_cm_flux_2026-08-09.json`.

A flat array of objects, newest first in this capture:

```json
{"time_tag":"2026-08-09T17:00:00","frequency":2800,
 "flux":9.400000000000000e+001,"reporting_schedule":"Morning",
 "avg_begin_date":null,"ninety_day_mean":null,"rec_count":null}
```

Four facts the parser has to respect:

- `flux` arrives in **exponential notation** (`9.4e+001` = 94 sfu), so it must
  be decoded as a `Double`, never matched as an integer string.
- `time_tag` carries **no timezone suffix**. SWPC products are UTC throughout;
  the parser appends `Z` semantics explicitly rather than letting a
  locale-dependent formatter guess.
- Several fields are `null` on most rows (`avg_begin_date`, `ninety_day_mean`,
  `rec_count`) — all optional, none read.
- **Order is not guaranteed.** This capture is newest-first while Endpoint 2 is
  oldest-first, from the same server on the same day. The parser sorts by
  `time_tag` and takes the newest rather than trusting either end of the array.

There are three reports a day (`reporting_schedule` of Morning / Noon /
Afternoon). The newest is the current value; nothing here needs the history.

## Endpoint 2 — planetary K index (Kp)

`https://services.swpc.noaa.gov/products/noaa-planetary-k-index.json`

Fetched 2026-08-09 18:27:51 GMT. `HTTP/2 200`, `content-type: application/json`,
`content-length: 4794`. Captured whole as
`Tests/Fixtures/SpaceWeather/swpc_planetary_k_index_2026-08-09.json`.

```json
{"time_tag":"2026-08-09T15:00:00","Kp":1.33,"a_running":5,"station_count":8}
```

- **Objects, not the header-row array-of-arrays** that several other
  `/products/` endpoints use. Written against what this one serves; the
  fixture is the record of that.
- `Kp` is a `Double` in thirds (1.33, 3.67, 5.67) — the conventional
  Kp₋/Kp/Kp₊ steps as decimals. Never an `Int`.
- The capital `K` in `Kp` is the server's; the key is case-sensitive.
- Oldest-first in this capture — see the ordering note above.
- Three-hourly, so a reading is up to three hours old before a newer one
  exists. This is why `SW_STALE_HOURS` is 6 rather than 1: a Kp that is two
  hours old is not stale, it is the current Kp.

## Source 3 — NOAA Space Weather Scales (the Kp mapping authority)

<https://www.swpc.noaa.gov/noaa-scales-explanation>, read 2026-08-09
(redirects to `spaceweather.gov`). The G-scale rows, in NOAA's own words, with
the HF sentence from each level's "Other systems" entry:

| Scale | Physical measure | What NOAA says about HF |
| --- | --- | --- |
| G1 Minor | Kp = 5 | *(no HF effect listed — power, spacecraft and aurora only)* |
| G2 Moderate | Kp = 6 | "HF radio propagation can fade at higher latitudes" |
| G3 Strong | Kp = 7 | "HF radio may be intermittent" |
| G4 Severe | Kp = 8, including a 9− | "HF radio propagation sporadic" |
| G5 Extreme | Kp = 9 | "HF (high frequency) radio propagation may be impossible in many areas for one to two days" |

The scale itself sets the bucket edges: NOAA draws its first HF-affecting line
at **Kp 5** (G1, where the storm begins) and its first explicit HF-degradation
line at **Kp 6** (G2). The table below uses exactly those two edges rather than
inventing others.

## Source 4 — NOAA SWPC, "F10.7 cm Radio Emissions" (the SFI authority)

<https://www.swpc.noaa.gov/phenomena/f107-cm-radio-emissions>, read 2026-08-09.

> The solar radio flux at 10.7 cm (2800 MHz) is an excellent indicator of solar
> activity.

> The F10.7 correlates well with the sunspot number as well as a number of
> UltraViolet (UV) and visible solar irradiance records.

> Reported in "solar flux units", (s.f.u.), the F10.7 can vary from below 50
> s.f.u., to above 300 s.f.u., over the course of a solar cycle.

NOAA gives the range and the meaning but publishes no band-by-band table — it
is an activity index, not a propagation forecast. The bucket edges below are
therefore round numbers inside NOAA's stated 50–300 range, chosen to be
obviously coarse: **under 90** (a quiet sun, near the bottom of the range),
**90–150** (ordinary), **over 150** (high, the half of the range where
`propplan`'s F2-MUF argument — see `band_daypart_sources.md`, Source 3 — puts
the high bands in play).

## The modifier table

Multiplicative, applied to the `BandDaypart` weight, and identity by default.
Three buckets each, per spec §5.2. `hf` means 160 m through 10 m; the SFI
buckets touch only the bands whose MUF argument they come from.

| Kp | NOAA scale | Effect on the weights |
| --- | --- | --- |
| < 5 | below G1 | ×1.00 everywhere — identity |
| 5 ≤ Kp < 6 | G1 | ×0.90 on 160/80/60/40 m, ×0.95 on 30/20/17 m, ×1.00 on 15/12/10 m |
| ≥ 6 | G2 and above | ×0.75 on 160/80/60/40 m, ×0.85 on 30/20/17 m, ×0.95 on 15/12/10 m |

The gradient across the bands is Source 3 of `band_daypart_sources.md`,
finding 1: absorption goes as the inverse square of frequency, so a disturbance
takes the low bands first and the high bands last.

| SFI | Effect |
| --- | --- |
| < 90 | ×0.85 on 15/12/10 m, ×1.00 elsewhere |
| 90–150 | ×1.00 everywhere — identity |
| > 150 | ×1.15 on 15/12/10 m, ×1.05 on 20/17 m, ×1.00 elsewhere |

**Absence is identity.** No network, a failed fetch, a missing field, or a
reading older than `SW_STALE_HOURS` (6) leaves every modifier at 1.00 and the
advisor runs on geometry alone. The detail line always names the observation
time, so a stale reading can never read as a current one.

## What is deliberately not here

- **The R scale** (radio blackouts). It is driven by GOES X-ray flux, its
  events last minutes to hours, and by the time an hourly poll noticed one it
  would usually be over. Modelling it from an hourly cache would be
  advice-shaped noise.
- **The S scale** (solar radiation storms). Polar-path effect, and these are
  state QSO parties.
- **Forecasts.** SWPC publishes 3-day and 27-day outlooks; the advisor reports
  what is measured now and says when it was measured. A forecast in a live
  advisory is a claim the app cannot stand behind.
