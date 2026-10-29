# Shunfeng — your ears for the journey

An iPhone app for deaf and hard-of-hearing travelers. It listens to airport announcements and alerts you only when one is about your flight: gate changes, delays, boarding, final call, cancellations. You get the message in your language plus a vibration pattern you can feel in your pocket.

It's built around one idea: help people be sure. Shunfeng never pretends to know more than it heard. When something is unclear, it says so, double-checks against live flight data, and helps you ask airport staff.

Built for the [Meta Global AI Developer Hackathon](https://cerebralvalley.ai/e/meta-ai-developer-hackathon) (Indie Developer track, "Build for Your World").

## What it does

- **Listens** with the iPhone microphone, screen off or in a pocket, and streams to Muse Voice Transcribe.
- **Reads** each announcement with rules that find the flight, the event, the gate and the time, in Mandarin,
  English and Japanese, including spoken codes ("C I one zero zero") and airline names without codes.
- **Decides "sure" or "maybe"**: an alert needs your flight number; a different destination, or a gate heard
  two different ways, turns it into "maybe, please check" rather than a confident wrong answer.
- **Checks** against Taoyuan Airport's live flight data every 5 minutes, and alerts on data changes too,
  in case the microphone missed an announcement.
- **Alerts** with a time-sensitive notification and a vibration language you can feel:
  1 long buzz = maybe, 2 = a change, 3 = go now (boarding, final call), one very long = cancelled.
- **Stops when the trip is over**: once the flight data shows your flight has left, or when the phone goes
  into airplane mode. A cancellation or a move to the next day is told first, then you're asked whether to
  stop. Without flight data, it asks around the departure time and stops if nobody answers. Can be turned off.
- **Reads your boarding pass** from a photo, including handwritten changes, so you don't type the flight.
- **Translates** English and Japanese announcements into Traditional Chinese as a reading aid.
- **Helps you ask** with a large bilingual card to show airport staff.

## Meta models

- **Muse Voice Transcribe** (realtime WebSocket): live speech-to-text. Keyword boosting is off on purpose:
  it turned a nearby flight number into the user's, which would cause false alerts.
- **Muse Spark** (Meta Model API): reads boarding pass photos into structured fields. On 12 real EVA Air
  and ANA boarding passes (rotated photos, highlighter, handwriting), all 8 fields were right on all 12,
  about 5 seconds each.
- **Muse Spark Open** (open weights, served by Baseten): translates announcements, about 2.5 seconds.
  The translation never decides anything; whose flight it is and what happened come from the rules
  and the flight data.

## Building

Requires Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen) and an iPhone.

```
export META_API_KEY=...       # Meta Model API key
export BASETEN_API_KEY=...    # Baseten key, for translation (optional)
xcodegen generate
open Shunfeng.xcodeproj
```

Keys are injected into the app's Info.plist at build time and never committed. A build made this way
contains your keys, so keep it for your own testing.

The rules, flight data and API clients are in the `ShunfengCore` Swift package: `cd ShunfengCore && swift test`.
`swift run shunfeng-listen` has development tools: stream a WAV file as the microphone would, look up a
flight in the live data, read a boarding pass photo, translate a line.

## Evaluation

See [`evaluation/prepared-before-hackathon/`](evaluation/prepared-before-hackathon/): 47 announcements
written before the hackathon (47/47 right) and 10 held out (10/10 alerts right, 7/10 every field right).

## What was built during the hackathon

All code in this repository was written during the hackathon, starting Oct 27, 2026.

Before the hackathon (Oct 23–26), I did some research outside this repo:

- a set of synthetic airport announcement scripts with answer keys, used to measure accuracy. With the
  organizers' permission it is included, clearly labeled, in `evaluation/prepared-before-hackathon/`
- Python prototypes for parsing announcements (not included; the rules were rewritten in Swift)
- snapshots of Taipei Taoyuan Airport's public open-data flight feed (not included)

## Flight data

Live flight status comes from Taoyuan International Airport's open data (ADIP), published under Taiwan's Open Government Data License.

## License

[MIT](LICENSE). Flight data from ADIP keeps its own license (above).
