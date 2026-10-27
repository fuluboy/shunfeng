# Shunfeng — your ears for the journey

An iPhone app for deaf and hard-of-hearing travelers. It listens to airport announcements and alerts you only when one is about your flight: gate changes, delays, boarding, final call, cancellations. You get the message in your language plus a vibration pattern you can feel in your pocket.

It's built around one idea: help people be sure. Shunfeng never pretends to know more than it heard. When something is unclear, it says so, double-checks against live flight data, and helps you ask airport staff.

Built for the [Meta Global AI Developer Hackathon](https://cerebralvalley.ai/e/meta-ai-developer-hackathon) (Indie Developer track, "Build for Your World").

## Status

Work in progress during the hackathon (Oct 27 – Nov 4, 2026).

## Meta models

- **Muse Voice Transcribe**: live speech-to-text for Mandarin and English announcements
- **Muse Spark**: re-checks unclear clips and reads boarding passes and departure boards (planned)

## What was built during the hackathon

Everything in this repository was written during the hackathon, starting Oct 27, 2026.

Before the hackathon (Oct 23–26), I did some research outside this repo:

- a set of synthetic airport announcement scripts with answer keys, used to measure accuracy
- Python prototypes for parsing announcements
- snapshots of Taipei Taoyuan Airport's public open-data flight feed

None of that code is included here.

## Flight data

Live flight status comes from Taoyuan International Airport's open data (ADIP), published under Taiwan's Open Government Data License.
