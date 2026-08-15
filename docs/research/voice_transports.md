# Playing this Mac's recordings through the radio — sources and open questions

Research behind [`docs/superpowers/specs/2026-08-15-voice-messages-design.md`](../superpowers/specs/2026-08-15-voice-messages-design.md).
Two transports, one per radio family the app supports, and one recorder that
feeds both. All fetched 2026-08-15 unless a line says otherwise.

## Sources

### FlexRadio 6000/8000 — audio over the network (DAX)

| Source | What it is authority for | Banked as |
| --- | --- | --- |
| **SmartSDR TCP/IP API wiki** — github.com/flexradio/smartsdr-api-docs/wiki (FlexRadio's own GitHub organisation), pages `SmartSDR-TCPIP-API`, `SmartSDR-Ethernet-API`, `TCPIP-client`, `TCPIP-stream`, `TCPIP-dax`, `TCPIP-transmit`, `TCPIP-xmit`, `TCPIP-slice`, `TCPIP-sub`, `Boolean-State`, `SmartSDR-Status-Responses`, `Known-API-Responses` | every command the driver sends and every reply code it interprets: `client udpport`, `stream create type=dax_tx`, `stream remove`, `dax audio set … tx=1`, `transmit set dax=`, `xmit`, `sub dax all`; the `R<seq>\|<hex>\|<message>` reply format; UDP port 4991 for VITA-49 | [`flex_smartsdr_tcpip_api_voice.txt`](flex_smartsdr_tcpip_api_voice.txt) (full pages) |
| **FlexLib API v3.2.37** (FlexRadio Systems, © 2012-2017) — `DAXTXAudioStream.cs`, `Radio.cs`, `Slice.cs`, `Vita/VitaFlex.cs`, `Vita/VitaCommon.cs`, `Vita/VitaIFDataPacket.cs`, `Vita/VitaSocket.cs`; read from the versioned copy at github.com/KevinSShaffer/JJFlexRadio, `FlexLib_API_v3.2.37/` | the VITA-49 packet a client sends *to* the radio: header bits, OUI `0x001C2D`, information class `0x534C`, packet class `0x03E3`, 128 stereo float frames per packet, packet size 263 words, sequence mod 16, big-endian throughout; the setup order (udpport, stream create, `stream <id> type=dax_tx … tx=` status); the send-only-when-`tx=1` rule; destination port 4991 | [`flexlib_3_2_37_dax_tx_excerpts.txt`](flexlib_3_2_37_dax_tx_excerpts.txt) (constants and line numbers, not code) |
| **FlexRadio Community**, Steve-N5AC (Community Manager, admin), September 2014, thread 6346756 | the sample rate (24 ksps) and sample format (stereo IEEE-754 float32, 0 dBFS = 1.0) of DAX audio over the API; that DAX audio replaces the mic and passes through the compressor and modulator | [`flex_dax_audio_format_staff_answer.txt`](flex_dax_audio_format_staff_answer.txt) |

Two working third-party clients were read as **hints only** (Article 1) to see
which of the wiki's documented commands a client actually issues, and in what
order: **nDAX** (github.com/kc2g-flex-tools/nDAX, `main.go`) and **FT8CN**
(github.com/N0BOY/FT8CN, `flex/FlexRadio.java`, `connector/FlexConnector.java`).
Both send `client udpport <port>`, then `dax audio set <ch> slice=<n> tx=1`, then
`stream create type=dax_tx`, take the stream id from the reply's message field
(`R<seq>|0|<hex id>`), and stream 128-frame packets every 5.33 ms. FT8CN's
comment states the transmit rate as 24 000 sps, agreeing with the staff answer.
No byte in the driver comes from either program.

### Elecraft K3 / K3S / KX3 / KX2 — audio through a sound card, PTT over CAT

| Source | What it is authority for | Banked as |
| --- | --- | --- |
| **K3S/K3/KX3/KX2 Programmer's Reference, Rev. G5** (Feb. 20 2019), already banked in full | `TX;` "Same as activating PTT or using the XMIT switch"; `RX;` "Terminates transmit in all modes" | [`k3_programmers_reference_g5.txt`](k3_programmers_reference_g5.txt) |
| **K3 Owner's Manual, Rev. D10** (Aug. 24 2011) — ftp.elecraft.com/K3/Manuals Downloads/E740107 K3 Owner's man D10.pdf | LINE IN "should be connected to your computer's soundcard output"; `MAIN:MIC SEL` = LINE IN or `MIC+LIN` ON; the 6–10 dB-below-clipping level guidance | [`k3_owners_d10_voice_excerpts.txt`](k3_owners_d10_voice_excerpts.txt) |

### The recorder and the sound-card player

Apple's frameworks, not a radio protocol: `AVAudioEngine`/`AVAudioFile`/
`AVAudioConverter` and CoreAudio's device enumeration
(`kAudioHardwarePropertyDevices`, `kAudioOutputUnitProperty_CurrentDevice`).
Nothing to bank; the behaviour is pinned by tests over synthetic buffers.

## The Flex sequence, as designed

```
connect:      sub dax all                       (alongside slice / tx / cwx)
first play:   [open connected UDP socket → radio:4991; local port P]
              client udpport P
              dax audio set <ch> tx=1           <ch> = TX slice's dax channel, or 1 (with slice=<tx slice>) if it has none
              stream create type=dax_tx          → R<seq>|0|<id>  and/or  S…|stream <id> type=dax_tx client_handle=<ours> tx=…
              stream set <id> tx=1               the claim (added 2026-08-15 after the bench — see OPEN QUESTION 1); then wait for tx=1
every play:   transmit set dax=1               (only if the transmit status says dax=0; restored after)
              xmit 1
              120 ms of silence packets, then the clip, one packet per 128/24000 s
              100 ms of silence packets
              xmit 0
              transmit set dax=0               (only if it was 0 before)
abort:        stop pacing; xmit 0; restore dax
disconnect:   stream remove <id>; close socket
```

Packet: VITA-49 IF Data with Stream ID, class ID present, no trailer, TSI=Other,
TSF=SampleCount, OUI `0x001C2D`, info class `0x534C`, packet class `0x03E3`,
128 frames of stereo float32 (mono duplicated into L and R), big-endian, packet
size 263 words, packet count mod 16, timestamps zero.

## OPEN QUESTIONS

Verified from the sources above; unverified on a bench. Named so the first
session with a radio on the desk knows what to look at.

1. **Which command makes this client the DAX transmit source.** *Answered on
   the bench 2026-08-15, in the negative form:* with `dax audio set <ch> tx=1`
   alone the radio keyed on `xmit 1` and put silence on the air. Two further
   clients read afterwards — one written against SmartSDR v4 through FlexLib
   itself (github.com/patrickrb/cqk1af, `flexlib_client.py`), one from scratch
   (github.com/dividebysandwich/sdroxide, `net.rs`) — both say the same thing:
   the radio modulates only the `dax_tx` stream that has claimed transmit with
   **`stream set 0x<id> tx=1`** (the wiki's `stream set <stream_id> tx=[1|0]`,
   banked page [4]) and drops packets from every other; "PTT keys with
   silence" is the documented symptom of a stream that never claimed. The
   driver now sends the claim as soon as it knows its stream id and still
   waits for the radio's `tx=1` before keying. cqk1af adds the operational
   half: **if the DAX application's own TX channel is enabled, the radio keeps
   that stream and drops ours** — the README says to turn it off. `dax audio
   set … tx=1` is kept as well (nDAX and M0LTE.Flex send it and work).
2. **Whether a non-GUI client may key.** SmartSDR v3 multiFLEX binds
   transmit to a GUI client's station; the wiki says `client bind` "performs
   no function in the radio" as of v3.0. The existing driver's `cwx send`
   already transmits from an unbound non-GUI client, which is the evidence
   `xmit 1` will too.
3. **Port 4991 for a LAN client's transmit packets.** FlexLib sends to
   `IP:4991`; FT8CN sends to 4993. FlexLib is the manufacturer's; the driver
   uses 4991.
4. **The DAX channel.** The design uses the TX slice's own DAX channel when it
   has one and channel 1 otherwise, associating it with the slice only in the
   second case. Whether any association is required for TX at all is unknown;
   FT8CN passes `slice=` every time.
5. **PTT lead on the K3.** 120 ms between `TX;` and the first sample is a
   default, adjustable in the tab; an amplifier's sequencer may want more.
6. **KX3/KX2 audio input.** Their manuals were not read; the README points at
   them rather than describing a jack.

## KNOWN LIMITATIONS

- The recorder writes 48 kHz mono 16-bit WAV. Imported files of any format
  `AVAudioFile` reads are folded to mono and left at their own rate; both are
  resampled at play time.
- Level is one number for both paths. The Flex has no DAX TX gain of its own
  over the API (FlexLib's `TXGain` is a client-side scalar), so the app scales
  samples; the K3 additionally has its MIC/LINE IN gain.
