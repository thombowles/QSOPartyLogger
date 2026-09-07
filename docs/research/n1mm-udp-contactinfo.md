# N1MM-format UDP contact broadcast — banked official sources

All fetched 2026-09-07. The wire format belongs to N1MM Logger+ and is taken
from its own documentation; what RUMlogNG accepts is taken from RUMlogNG's
own documentation, version history and its author's forum post. No other
logger's source code and no forum guess was consulted for a byte.

## N1MM Logger+ documentation — "External UDP Messages"

`https://n1mmwp.hamdocs.com/appendices/external-udp-broadcasts/` (fetched
2026-09-07; the page carries no revision date).

- *"External UDP Messages pass information from N1MM Logger+ about the
  contest in progress to various third-party software programs. UDP Messages
  can be sent to remote addresses, provided the receiving computer can be
  reached through its local router. You cannot send broadcasts (like
  xx.xx.xx.255) to remote subnets."*
- Developer note: *"Vasily K3IT has found that if both SO_BROADCAST and
  SO_REUSEADDR options are used when a UDP port is opened, it is opened in a
  'non-exclusive' mode. This allows multiple applications to share the same
  port, as long as they all follow this method."*
- **Contacts** checkbox: *"Sends contact information (time, callsign, mode,
  frequency, exchange…) when a new contact (QSO) is added to the log, when an
  existing contact is edited in the log, or when an existing contact is
  deleted from the log."*
- Addressing: *"To send them to a program running on this PC, use the address
  127.0.0.1. To send them to another PC on this subnet, enter its IP on the
  corresponding line. To send them to all PCs on this subnet, enter 255 as
  the last number (octet) of this subnet's address. … Do not specify 255 in
  the higher order octets, or you will risk broadcasting to the internet."*
- Port: *"Except as noted below, the recommended default port number for N1MM
  Logger applications is 12060."*

### Contact Info UDP packet (verbatim)

```xml
<?xml version="1.0" encoding="utf-8"?>
<contactinfo>
	<app>N1MM</app>
	<contestname>CWOPS</contestname>
	<contestnr>73</contestnr>
	<timestamp>2020-01-17 16:43:38</timestamp>
	<mycall>W2XYZ</mycall>
	<band>3.5</band>
	<rxfreq>352519</rxfreq>
	<txfreq>352519</txfreq>
	<operator></operator>
	<mode>CW</mode>
	<call>W1AW</call>
	<countryprefix>K</countryprefix>
	<wpxprefix>W1</wpxprefix>
	<stationprefix>W2XYZ</stationprefix>
	<continent>NA</continent>
	<snt>599</snt>
	<sntnr>5</sntnr>
	<rcv>599</rcv>
	<rcvnr>0</rcvnr>
	<gridsquare></gridsquare>
	<exchangel></exchangel>
	<section></section>
	<comment></comment>
	<qth></qth>
	<name></name>
	<power></power>
	<misctext></misctext>
	<zone>0</zone>
	<prec></prec>
	<ck>0</ck>
	<ismultiplierl>1</ismultiplierl>
	<ismultiplier2>0</ismultiplier2>
	<ismultiplier3>0</ismultiplier3>
	<points>1</points>
	<radionr>1</radionr>
    <run1run2>1<run1run2>
	<RoverLocation></RoverLocation>
	<RadioInterfaced>1</RadioInterfaced>
	<NetworkedCompNr>0</NetworkedCompNr>
	<IsOriginal>False</IsOriginal>
	<NetBiosName></NetBiosName>
	<IsRunQSO>0</IsRunQSO>
	<StationName>CONTEST-PC</StationName>
	<ID>f9ffac4fcd3e479ca86e137df1338531</ID>
	<IsClaimedQso>1</IsClaimedQso>
    <oldtimestamp>2020-01-17 16:43:38</oldtimestamp>
    <oldcall>W1AW</oldcall>
    <SentExchange>XYZ NY</SentExchange>
</contactinfo>
```

The page's HTML spells `exchangel` and `ismultiplierl` with the letter *l*
(checked in the raw source, not a rendering). Their siblings are
`ismultiplier2` and `ismultiplier3`, and the N1MM–DXKeeper Gateway help
(`https://ny4i.github.io/DxKeeper-UDP-Gateway/`, fetched 2026-09-07) names
the ADIF `SRX_STRING` as *"populated from N1MM's Exchange1 field"* — so the
app emits `exchange1` and `ismultiplier1`, the digit. The unclosed
`<run1run2>1<run1run2>` is likewise the page's typo; the app closes it.

### The page's notes on the fields (verbatim)

- *"IsOriginal indicates that this is the station on which this contact was
  initially logged – to differentiate it from another station that may be
  forwarding the contact record. StationName is the netbios name of the
  station that sent this packet, not necessarily the name of the station
  that logged this contact."*
- *""power", "name" and "qth" refer to information about the station being
  worked in this contact. In a contest where transmit power is part of the
  exchange, "power" will contain the received power exchange from the other
  station."*
- *""run1run2" refer to the run radio number is a multi-2 arrangement."*
- *""band" is composed of 2 or 3 characters that may include localized
  delimiters. For example, 80 meters may be "3.5" or "3,5"; 160 meters as
  "1.8" or "1,8" The user's Windows setting will determine which delimiter is
  present in the band tag"*
- *"ID is a 32 byte unique GUID identifier for each contact in the log. Note
  that it is sent as 2 hex characters per byte."*
- *"IsClaimedQso will default initially to "1" for all contacts and is set to
  "0" when a contact is declared to be an X-QSO"*
- *"oldtimestamp and oldcall are used in contactreplace packets to indicate
  the time and callsign that were originally logged before editing, in case
  either was changed. In contactinfo packets they are the same as timestamp
  and call respectively"*
- *"SentExchange is the contents of the Sent Exchange box in the contest
  setup dialog window. This is not necessarily the same as the actual
  exchange sent during the QSO; there is no signal report, the serial number
  (# or 001) is a placeholder for the actual serial number (sntnr), and there
  is no guarantee that what is in the Sent Exchange box is the same as what
  was in the function key message"*
- *"ADIF fields in ContactInfo – It may be tempting to assume that there is a
  one-to-one correspondence between fields in the contactinfo messages and
  similar fields in the ADIF specification, but this is not always the case.
  The best example is the Section field in the contactinfo message; this
  means whatever the rules for the particular contest define it to mean. …
  Another example is the Zone field, which often means the same as CQZ in
  ADIF, but in some contests it means the same as ITUZ. Yet another example
  is the frequency field, which is not in the same format as in ADIF; in the
  contact info and radio info message, the frequency is exported in units of
  10 Hz."*
- Mode values named for the Radio Info packet, the same vocabulary:
  *"CW, USB, LSB, RTTY, PSK31, PSK63, PSK125, PSK250, QPSK31, QPSK63,
  QPSK125, QPSK250, FSK, GMSK, DOMINO, HELL, FMHELL, HELL80, MT63, THOR,
  THRB, THRBX, OLIVIA, MFSK8, MFSK16"*.

### Contact Replace (verbatim)

*"The Contact Replace packet contains the same fields as Contact Info above,
but with <contactreplace > XML tags."*

*"IMPORTANT NOTE TO DEVELOPERS: When a user edits an existing contact record,
the program will send a pair of UDP packets: A < contactdelete > packet,
followed by a < contactreplace > packet. The < contactdelete > packet will
contain the existing record's callsign and timestamp, in the event that the
< contactreplace > packet includes a new timestamp or callsign for this
record. (The need for this has now been eliminated with the addition of the
oldcall and oldtimestamp fields.)"*

### Contact Delete (verbatim)

```xml
<?xml version="1.0" encoding="utf-8"?>
<contactdelete>
	<app>N1MM</app>
	<timestamp>2020-01-17 16:43:38</timestamp>
	<mycall>W2XYZ</mycall>
	<band>3.5</band>
	<call>W1AW</call>
	<contestnr>73</contestnr>
	<StationName>CONTEST-PC</StationName>
	<ID>a1b2c3d4e5f6g7h</ID>
</contactdelete>
```

## RUMlogNG documentation — "Functions in the local network"

`https://dl2rum.de/RUMlogNG/docs/en/pages/Networking.html` (fetched
2026-09-07, undated).

*"RUMlog can communicate with third party applications or other RUMlog
instances in the local network. Information are broadcasted whenever a QSO is
logged or changed, a dx-spot arrives or the trx frequency changes. Zwo
different, not compatible protocols are supported: Fldigi compatible; N1MM and
TR4W compatible. For the data exchange between multiple RUMlog applications,
the N1MM protocol will be used."*

*"RUMlog, N1MM and TR4W — For different function you can set different host
addresses and ports. Third party applications must be configured accordingly.
Set the options to select the functions: App Info: name of the computer, name
of the logbook file, logbook changes (save, delete, edit); Radio: frequency
and operating mode - both connected trx are supported; DX-Spot: incoming
dx-spots"*

The page links N1MM's "External UDP Messages" page as its *"N1MM UDP"*
external reference.

## RUMlogNG version history

`https://dl2rum.de/RUMlogNG/docs/en/pages/OlderHistory.html` (fetched
2026-09-07):

- **5.0, 20-September-2020**: *"Real time import from from other loggers in
  N1MM format. (I.e. Flex Radio logbook)"* and *"Real time import from from
  N1MM"*.
- **5.7.1, 4-April-2022**: *"Second set for N1MM Contact Info in the UDP
  settings, useful for https://qsomap.org"*.
- **5.15.3, 6-February-2024**: *"Function in the QSO contextual menu to
  resend QSOs via UDP or tcp/ip to connected clients"*.

`https://machamradio.com/blog/2026/09/05/rumlogng-for-macos-version-6-5-1-released/`
(search-result excerpt, 2026-09-07; the page itself refuses fetches):
RUMlogNG 6.5.1 *"added my_gridsquare information in the N1MM contact UDP
broadcast"*.

## DL2RUM, RUMlogNG forum, "Automatic import to Dxkeeper (Dxlab)"

`https://dl2rum.de/forum/viewtopic.php?t=1425` (fetched 2026-09-07).

DL2RUM, 23 May 2021, 10:22: *"RUMlog can broadcast all logged QSOs over the
network."* — and, 19:39, *"The broadcast looks like this:"*, a tcpdump on
`lo0 port 12065`, given in clear as:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<contactinfo>
    <contestname>Rag Chewing</contestname>
    <timestamp>2021-05-23 19:34:33</timestamp>
    <mycall>DL2RUM</mycall>
    <band>24</band>
    <txfreq>2489800</txfreq>
    <mode>CW</mode>
    <call>DL2RUM</call>
    <countryprefix>DL</countryprefix>
    <wpxprefix>DL2</wpxprefix>
    <continent>Eu</continent>
    <snt>599</snt>
    <rcv>599</rcv>
    <gridsquare></gridsquare>
    <comment></comment>
    <qth></qth>
    <name></name>
    <power>High Power</power>
    <zone>14</zone>
    <IsOriginal>YES</IsOriginal>
    <StationName>MBP2019</StationName>
    <dxcc>230</dxcc>
</contactinfo>
```

What this establishes about RUMlogNG's reading of "N1MM format": no `app`
element, `IsOriginal` as `YES`, `band` as the whole-MHz `24` for 12 m,
`txfreq` alone in 10 Hz units (`2489800` = 24.898 MHz), and a `dxcc` element
of its own after N1MM's list. The app therefore sends every N1MM element in
N1MM's order, then RUMlogNG's `dxcc` and `my_gridsquare`.

## RUMlogNG Preferences › UDP (screenshot supplied by the operator, 2026-09-07)

Pane "RUMlog, N1MM & TR4W compatible": outgoing *App info (N1MM, RUMlog)*,
*Radio (N1MM)*, *DX spot (N1MM)*, *Contact info N1MM* (host
255.255.255.255, port 12060) and a second *Contact info* set (port 12061);
*Listen to other RUMlog instances*; incoming *QSOs received from Flex / ADIF*
(popup *Save QSO*, port 2237) and *QSOs received from N1MM* (popup *Save
QSO*, port 12060). The app targets the last of these.

## Verified against RUMlogNG 6.5.1 (build 727), 2026-09-07

The first build sent `<app>QSOPartyLogger</app>` and RUMlogNG saved nothing.
Diagnosed on the Mac mini running both apps, without the screen:

- `netstat -anv -p udp` showed RUMlogNG's IPv4 socket `*.12060` with 17,096
  bytes received and the logger holding no UDP socket (it closes the socket
  on every host edit and reopens on the next packet) — so packets had
  arrived and been dropped.
- RUMlogNG's own binary strings name what its listener does: it prints
  `%@ [%@] QSO imported --> %@ %@ %@` on success and `Error parsing N1MM
  xml: %@` on a bad document (neither appeared), and for a delete it reads
  `contactdelete/app` and compares it with the literal `N1MM`. Its saved
  preferences: `UdpSaveFromN1mmPort = 12060`, `UdpSaveQsFromN1mmIdx = 1`
  (*Save QSO*). The Network Status window's station table is the
  RUMlog-to-RUMlog sync ("RUMlog instances in the network"), which its page
  says is "not available for the contest interface yet"; it plays no part
  in the N1MM listener.
- The experiment, one variable: the app's exact KD2KW packet sent from a
  script to 127.0.0.1:12060, read-only counts of RUMlogNG's `ZCORE_QSO`
  table before and after each send —
  `<app>QSOPartyLogger</app>`: 13,929 → 13,929 (dropped);
  `<app>N1MM</app>`: 13,929 → 13,930, KD2KW 123 → 124 (saved);
  N1MM's `contactdelete` with the same `ID`, `call`, `timestamp`:
  13,930 → 13,929 (removed — the delete path works, and the logbook ended
  exactly as it began).

So `app` is `N1MM`. Every other element stayed as designed; the trailing
`dxcc` / `my_gridsquare` and `IsOriginal` `True` were accepted as sent.
