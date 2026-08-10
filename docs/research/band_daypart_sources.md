# Band-daypart provenance — which bands the sun opens, and when

Banked research for the weight table in `Sources/Core/Models/SolarGeometry.swift`
(`SolarGeometry.weight(band:daypart:)`). Read this before touching a number in
that table. The space-weather modifiers that scale these weights are banked
separately, in `space_weather_sources.md`.

**What this table is.** A coarse statement of *tendency*: with the sun up the
high bands carry the traffic, after dark the low bands do, 40 m works both
sides, and the terminator is worth naming. It is not a propagation prediction
and it never outranks observed evidence — where spots exist, the advisor counts
spots and the daypart weight only breaks ties. The copy always says "usually".
VOACAP-grade prediction is deliberately out of scope: it needs a target area,
an antenna model, and a month of statistics, none of which a live QSO-party
sidebar has.

## Source 1 — NOAA SWPC, "Ionosphere" (phenomena)

<https://www.swpc.noaa.gov/phenomena/ionosphere>, read 2026-08-09. US
Government work.

> The Ionosphere is part of Earth's upper atmosphere, between 80 and about
> 600 km where Extreme UltraViolet (EUV) and x-ray solar radiation ionizes the
> atoms and molecules thus creating a layer of electrons.

> Since the largest amount of ionization is caused by solar irradiance, the
> night-side of the earth, and the pole pointed away from the sun (depending on
> the season) have much less ionization than the day-side of the earth, and the
> pole pointing towards the sun.

This is the whole basis for keying the table on **solar elevation at the
operator's own location**: ionization tracks illumination, so the sun's height
is the one locally-available number that moves it.

## Source 2 — NOAA SWPC, "HF Radio Communications" (impacts)

<https://www.swpc.noaa.gov/impacts/hf-radio-communications>, read 2026-08-09.
US Government work.

> At frequencies in the 1 to 30 mega Hertz range (known as "High Frequency" or
> HF radio), the changes in ionospheric density and structure modify the
> transmission path and even block transmission of HF radio signals completely.

> The solar x-rays from the sun penetrate to the bottom of the ionosphere (to
> around 80 km). There the x-ray photons ionize the atmosphere and create an
> enhancement of the D layer of the ionosphere. This enhanced D-layer acts both
> as a reflector of radio waves at some frequencies and an absorber of waves at
> other frequencies.

The D layer is the reason the low bands are daytime-dead and come alive after
dark: it exists while the sun is on it and absorbs the lowest HF hardest. It is
also why this table stops at 10 m — above 30 MHz NOAA's sentence no longer
applies, and 6 m and up are given a flat, opinion-free weight (§Table, last
row).

## Source 3 — ARRL Technical Information Service, K9LA

Two ARRL-published papers by Carl Luetzelschwab, K9LA, downloaded 2026-08-09:

- *Propagation Planning for Contests: Using Propagation Predictions to Develop
  a Band Plan* —
  <http://www.arrl.org/files/file/Technology/tis/info/pdf/propcontest.pdf>
- *Propagation Planning for DXpeditions* —
  <http://www.arrl.org/files/file/Technology/tis/info/pdf/propplan.pdf>

Both are linked from ARRL's *Propagation of RF Signals*
(<http://www.arrl.org/propagation-of-rf-signals>, read 2026-08-09).
Copyrighted ARRL material — summarised here, not reproduced.

Three findings this table rests on:

1. **Absorption falls off as the square of frequency**, so the higher bands are
   hit last by an absorption event and recover first (*propcontest*, on radio
   blackouts). This orders the bands under a disturbance and is why the Kp
   modifier in `space_weather_sources.md` damps low before high.
2. **The high bands live or die by the F2-region MUF**, which is what makes
   15/12/10 the bands that follow solar activity (*propplan*, step 3). This is
   why the SFI modifier lifts the high bands and leaves the low ones alone.
3. **Sunrise and sunset matter on their own**, not merely as the boundary of
   darkness: K9LA singles out 160 m for sunrise and sunset signal-strength
   enhancements, calling the sunrise ones the most spectacular
   (*propplan*, 160 m section). ARRL's propagation index also carries
   *An Introduction to Gray-Line DXing* (QST, November 1992) for the same
   effect. This is the gray-line column, and the ±45-minute window around each
   crossing.

The contest paper's framing is worth recording because it is the same
distinction the advisor's goal switch makes: it separates being on the band
that gives the highest **score** from the band that gives the highest **rate**,
and treats those as different questions.

## The table

Three dayparts. `grayLine` wins where it applies — within ±45 minutes of the
nearest sunrise or sunset — otherwise `day` while the sun is above the horizon
and `night` below it.

| Band | day | grayLine | night |
| --- | --- | --- | --- |
| 160 m | 0.10 | 1.00 | 1.00 |
| 80 m | 0.20 | 1.00 | 1.00 |
| 60 m | 0.30 | 0.95 | 0.90 |
| 40 m | 0.60 | 1.00 | 1.00 |
| 30 m | 0.70 | 0.90 | 0.90 |
| 20 m | 1.00 | 0.90 | 0.60 |
| 17 m | 1.00 | 0.80 | 0.40 |
| 15 m | 0.90 | 0.70 | 0.20 |
| 12 m | 0.80 | 0.60 | 0.15 |
| 10 m | 0.80 | 0.60 | 0.10 |
| 6 m and above | 0.50 | 0.50 | 0.50 |

Reading of the rows, against the sources above:

- **160/80 m** are Source 2's D-layer case at its sharpest: near-dead in
  daylight, the primary bands after dark, and Source 3's named gray-line
  beneficiaries.
- **40 m** is the transitional band every operator knows and the sources
  describe by implication — high enough to survive some daytime absorption,
  low enough to be a night band. It is the only band whose day weight sits in
  the middle on purpose.
- **20 m** is the one band that is genuinely good on both sides of the
  terminator, so it never falls to a low weight; it is the highest night weight
  above 40 m.
- **15/12/10 m** follow the F2 MUF (Source 3, finding 2): strong with the sun
  up, and the first to close after it goes down.
- **6 m and above** get a flat 0.5 — no daypart claim at all. Sporadic-E and
  tropospheric modes are not what Source 2 describes, and a table that pretended
  otherwise would be inventing a rule rather than modelling one.

Nothing here is tuned against a contest log, and none of it should be until one
exists to tune against. The numbers are ordinal — they exist so a
`(posture, band)` candidate that has no spot evidence still sorts sensibly
against one that does.
