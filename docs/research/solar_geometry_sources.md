# Solar position provenance — declination, elevation, sunrise/sunset

Banked research for `Sources/Core/Models/SolarGeometry.swift`. The advisor's
solar strand needs three things and nothing more: **is the sun up here**, **how
high**, and **when does it cross the horizon** — enough to say "sunset was
0112Z, 40 m and 80 m usually take over from here" and to place the gray-line
window. Everything below is the source for those three answers.

## Source 1 — NOAA Global Monitoring Laboratory, Solar Calculator

<https://gml.noaa.gov/grad/solcalc/calcdetails.html>, read 2026-08-09.

The page names its own authority and its accuracy claim:

> The calculations in the NOAA Sunrise/Sunset and Solar Position Calculators
> are based on equations from *Astronomical Algorithms*, by Jean Meeus.

and, for the atmospheric-refraction correction, gives the piecewise formula
reproduced in §"Refraction" below. The page carries a notice that the
calculator is **no longer actively supported or maintained** by the GML team;
the equations themselves are Meeus's and do not rot, and the cross-check in §3
is what actually pins this implementation.

### The equations, verbatim from NOAA's own spreadsheet

The page does not print the equations as text — it publishes them as the cell
formulas of `NOAA_Solar_Calculations_day.ods`
(<https://gml.noaa.gov/grad/solcalc/NOAA_Solar_Calculations_day.ods>, downloaded
2026-08-09, 248 552 bytes). Extracted from `content.xml`, sheet `Calculations`,
row 2. `$B$3` is latitude, `$B$4` longitude, `$B$5` the time-zone offset in
hours (this app always passes 0 — everything is UTC), `$B$7` the date.

| Quantity | NOAA cell formula |
| --- | --- |
| Julian Day | `date + 2415018.5 + time − tz/24` |
| Julian Century `G` | `(JD − 2451545) / 36525` |
| Geom Mean Long Sun `I` | `MOD(280.46646 + G*(36000.76983 + G*0.0003032), 360)` |
| Geom Mean Anom Sun `J` | `357.52911 + G*(35999.05029 − 0.0001537*G)` |
| Eccent Earth Orbit `K` | `0.016708634 − G*(0.000042037 + 0.0000001267*G)` |
| Sun Eq of Ctr `L` | `SIN(RAD(J))*(1.914602 − G*(0.004817 + 0.000014*G)) + SIN(RAD(2J))*(0.019993 − 0.000101*G) + SIN(RAD(3J))*0.000289` |
| Sun True Long `M` | `I + L` |
| Sun App Long `P` | `M − 0.00569 − 0.00478*SIN(RAD(125.04 − 1934.136*G))` |
| Mean Obliq Ecliptic `Q` | `23 + (26 + ((21.448 − G*(46.815 + G*(0.00059 − G*0.001813))))/60)/60` |
| Obliq Corr `R` | `Q + 0.00256*COS(RAD(125.04 − 1934.136*G))` |
| **Sun Declin `T`** | `DEG(ASIN(SIN(RAD(R))*SIN(RAD(P))))` |
| var y `U` | `TAN(RAD(R/2))^2` |
| **Eq of Time `V`** (minutes) | `4*DEG(U*SIN(2*RAD(I)) − 2*K*SIN(RAD(J)) + 4*K*U*SIN(RAD(J))*COS(2*RAD(I)) − 0.5*U*U*SIN(4*RAD(I)) − 1.25*K*K*SIN(2*RAD(J)))` |
| **HA Sunrise `W`** (deg) | `DEG(ACOS(COS(RAD(90.833))/(COS(RAD(lat))*COS(RAD(T))) − TAN(RAD(lat))*TAN(RAD(T))))` |
| **Solar Noon `X`** (day fraction) | `(720 − 4*lon − V + tz*60) / 1440` |
| Sunrise `Y` | `X − W*4/1440` |
| Sunset `Z` | `X + W*4/1440` |
| True Solar Time `AB` (min) | `MOD(time*1440 + V + 4*lon − 60*tz, 1440)` |
| Hour Angle `AC` (deg) | `IF(AB/4 < 0, AB/4 + 180, AB/4 − 180)` |
| Solar Zenith `AD` | `DEG(ACOS(SIN(RAD(lat))*SIN(RAD(T)) + COS(RAD(lat))*COS(RAD(T))*COS(RAD(AC))))` |
| **Solar Elevation `AE`** | `90 − AD` |
| Atm Refraction `AF` | see below, `/3600` |
| **Corrected elevation `AG`** | `AE + AF` |

Two constants carry meaning rather than arithmetic. **90.833°** is the zenith
angle NOAA defines sunrise/sunset at — the sun's apparent radius plus mean
refraction at the horizon — which is why the computed times land on the
almanac's and not on geometric zero. **1440** and the factor **4** are the same
fact twice: one degree of hour angle is four minutes of time.

### Refraction

`AF`, in arc-seconds before the `/3600`, with `e` the uncorrected elevation:

```
e > 85°       : 0
e > 5°        : 58.1/tan(e) − 0.07/tan³(e) + 0.000086/tan⁵(e)
e > −0.575°   : 1735 + e*(−518.2 + e*(103.4 + e*(−12.79 + e*0.711)))
otherwise     : −20.772/tan(e)
```

## Source 2 — Julian Day from a Unix timestamp

`JD = unixSeconds/86400 + 2440587.5`. The Unix epoch 1970-01-01T00:00:00Z **is**
JD 2440587.5 by definition, so this replaces NOAA's spreadsheet-serial term
exactly and removes the only calendar-dependent step in the chain. There is no
`Calendar` anywhere in `SolarGeometry`, and therefore no daylight-saving,
locale, or leap-second edge to get wrong.

## Source 3 — the cross-check that actually pins the implementation

US Naval Observatory Astronomical Applications API v4.0.1,
`https://aa.usno.navy.mil/api/rstt/oneday`, queried 2026-08-09 with `tz=0`.
Independent authority, independent code: if the transcription of Source 1 were
wrong, these would not agree.

| Place | Date | USNO rise / transit / set (UTC) | This implementation |
| --- | --- | --- | --- |
| W1AW, Newington CT (41.714775, −72.727260) | 2026-06-21 | 09:16 / 16:53 / 00:29 | 09:16:32 / 16:52:46 / 00:29:00 |
| W1AW | 2026-12-21 | 12:15 / 16:49 / 21:23 | 12:14:46 / 16:49:05 / 21:23:23 |
| EM13 (33.5, −97.0) | 2026-08-09 | 11:46 / 18:33 / 01:21 | 11:46:25 / 18:33:29 / 01:20:33 |
| Equator/prime meridian (0, 0) | 2026-03-20 | 06:04 / 12:07 / 18:11 | 06:04:05 / 12:07:25 / 18:10:45 |

Every figure agrees to within one minute. Note the UTC-day convention
difference: USNO reports the set that falls *inside* the requested UTC day
(2026-06-21's 00:29 is the previous local evening), while `sunriseSunset`
returns the set that *follows* the returned sunrise. The clock times are the
same to the minute either way, which is the only thing the advisor reads.

These four rows are the pinned cases in `Tests/Core/SolarGeometryTests.swift`.

## Polar cases

`HA Sunrise` takes `ACOS` of a quantity that leaves [−1, 1] wherever the sun
neither rises nor sets. NOAA's spreadsheet yields `#NUM!` there; this
implementation returns `nil`, and the advisor's solar strand goes silent rather
than inventing a terminator. Verified at Svalbard (78 N, 15 E) on 2026-06-21
(midnight sun) and 2026-12-21 (polar night).
