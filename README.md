# Shunfeng

Shunfeng is an iPhone app for deaf and hard-of-hearing travelers. It listens to airport announcements for you and buzzes only when one is about your flight.

The name comes from Shunfeng'er (順風耳, "wind-following ears"), the god in Taiwanese folk belief who can hear anything, however far away. He stands beside Mazu, the goddess who protects people traveling by sea, and listens out for them. This app tries to do the same for travelers at the airport.

Airports still tell you most things out loud. If your gate moves or your flight is delayed, the people around you hear it and start walking. If you can't hear it, you find out from the departure board, if you happen to look in time. Shunfeng keeps the phone's microphone on while you wait, works out which announcements are yours, and tells you with a vibration you can feel in your pocket and a notification you can read.

I built it for the [Meta Global AI Developer Hackathon](https://cerebralvalley.ai/e/meta-ai-developer-hackathon) (Indie Developer track, "Build for Your World"). It was designed around airports in Taiwan, where announcements come in Mandarin and then English, and it handles Japanese ones too.

## How it works

You type your flight number, or take a photo of your boarding pass and the app reads it. Then you press Start listening and put the phone away.

The microphone streams to Muse Voice Transcribe, which turns each announcement into text. Rules on the phone read that text for a flight number, what happened (gate change, delay, boarding, final call, cancellation, a passenger being paged), the gate and the time. Only announcements that match your flight reach you.

The vibration says how urgent it is, so you know before you look:

| Buzzes | Meaning |
| --- | --- |
| 1 | Maybe about you, please check |
| 2 | Something changed (gate, time) |
| 3 | Go now (boarding, final call) |
| One long buzz | Cancelled |

For boarding and final calls, the notification comes back every 30 seconds, up to four times, until you answer. "I'm at the gate" quiets them.

Speech recognition makes mistakes, so the app is careful about what it claims. If it hears your flight number but not the news, or the announcement names a different destination, it says "maybe" instead of sounding sure. If two announcements give different gates, it shows both and asks you to check the board. For flights from Taipei Taoyuan it also compares what it heard with the airport's live flight data every five minutes, and tells you when the data changes on its own, in case an announcement was missed. When it is still unclear, a large card in Chinese and English helps you ask staff.

Announcements in another language are translated into yours. The whole app, including notifications, works in English or Traditional Chinese.

The app also tries not to fail quietly. During a phone call it pauses and picks up again when you hang up. Without signal it pauses and resumes when the network is back. If the app is closed or the phone restarts, a notification tells you it is no longer listening. When your flight departs, it stops by itself.

## Meta models

**Muse Voice Transcribe** does the listening, as a live stream from the phone. I turned off its keyword hints on purpose. Giving it the user's flight number made it hear that number in announcements for other flights (a CI110 delay came back as CI100), which would mean false alarms. The app sends plain audio and decides afterwards.

**Muse Spark** reads boarding pass photos into flight, date, route, gate, times and seat. It also catches handwritten changes, which matter because staff often write a new boarding time on the pass. On 12 real EVA Air and ANA passes, including rotated photos and highlighter marks, it read all eight fields correctly on every one, in about five seconds.

**Muse Spark Open**, Meta's open-weight model served through Baseten, translates announcements in about two to three seconds. It also fixes some recognition errors as it goes: a Mandarin announcement transcribed as "潮融航空188" came back as "EVA Air flight BR188". The translation helps you read; it doesn't decide whether an announcement is about you. That stays with the rules and the flight data.

## What testing showed

Most of the design came from testing on an iPhone, at home with a speaker and with real recordings:

- Recording audio the usual way silenced the app's own notifications, so alerts showed up with no sound and no vibration. Switching the audio mode fixed it.
- Live transcription once turned "CI1000 to Hong Kong" into "CI 100". Checking the destination is what stops that from becoming a false alarm.
- At Haneda, announcements use airline names instead of codes and plain numbers for gates, so the rules learned both.
- Letters inside Mandarin speech are hard to recognize ("BR188" came back as "PS188" and worse), so the airline's spoken name now decides the code, and the flight number alone, plus the destination, is enough.
- The phone's own microphone caught 12 of 12 announcements from a speaker one to two meters away. AirPods caught 3, so the phone's microphone is the default.
- Listening with the screen off uses about 5% of the battery an hour. The speech service ends each session after an hour, and the app reconnects without a gap.

## Privacy

While you listen, the app streams microphone audio to Muse Voice Transcribe. Nothing is recorded to a file.

On the phone, the app keeps only transcripts that are about flights. Anything else the microphone hears, like people talking nearby, is logged only as "a line of so many characters". A test mode in Settings keeps everything, for development.

Boarding pass photos are sent to Muse Spark to be read and aren't stored.

## Building

You need Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen) and an iPhone.

```
export META_API_KEY=...       # Meta Model API key
export BASETEN_API_KEY=...    # Baseten key, for translation (optional)
xcodegen generate
open Shunfeng.xcodeproj
```

The keys are written into the app at build time and are never committed. A build made this way contains your keys, so keep it to yourself.

The rules, the flight data and the API clients live in the `ShunfengCore` Swift package (`cd ShunfengCore && swift test`). `swift run shunfeng-listen` has a few development tools: stream a WAV file the way the microphone would, look up a flight in Taoyuan's live data, read a boarding pass photo, translate a line, and score the rules on an evaluation file.

## Evaluation

[`evaluation/prepared-before-hackathon/`](evaluation/prepared-before-hackathon/) has 47 test announcements in Mandarin and English with the expected answers, plus 10 held back and never used to tune the rules. On the written text, the rules get all 47 right, and alert correctly on all 10 held-out ones (7 of 10 with every detail right).

[`evaluation/speech-recognition/`](evaluation/speech-recognition/) has the same announcements after speech recognition. Through Muse Voice Transcribe, the alert decision is right on 47 of 47. The misses on details are Mandarin gate numbers the recognizer dropped, which the app marks as unclear and fills in from the flight data. Heard live by the app on an iPhone, it was 12 of 12.

## Before the hackathon

All the code here was written during the hackathon, from October 27, 2026. Before that, from October 23 to 26, I did some groundwork outside this repository:

- wrote the synthetic test announcements and their answers (included, with the organizers' permission, in `evaluation/prepared-before-hackathon/`)
- tried parsing announcements in Python (not included; the rules were rewritten in Swift)
- saved snapshots of Taoyuan Airport's open flight data (not included)

## Data and license

Live flight status comes from Taoyuan International Airport's open data (ADIP), published under Taiwan's Open Government Data License.

The code is under the [MIT license](LICENSE).
