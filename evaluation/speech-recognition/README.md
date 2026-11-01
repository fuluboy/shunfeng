# Speech recognition results (made during the hackathon)

The written announcements in `../prepared-before-hackathon/` were turned into speech with macOS voices
(Meijia for Mandarin, Samantha for English) and transcribed with Muse Voice Transcribe. Each file here has
the transcript in the `script` column and the expected answer in the other columns, so the same scorer runs
on it:

```
cd ShunfengCore
swift run shunfeng-listen eval ../evaluation/speech-recognition/muse_voice_transcribe_plain.csv
```

| File | How it was transcribed | Alert right | Every field right |
| --- | --- | --- | --- |
| `muse_voice_transcribe_plain.csv` | 47 audio files, no hints (what the app does), Oct 27 | 47/47 | 40/47 |
| `muse_voice_transcribe_keywords.csv` | same, with the flight and gates as keyword hints, Oct 27 | 39/47 | 35/47 |
| `iphone_mic_1-2m_mix12.csv` | 12 announcements played on a Mac speaker, heard live by the app on an iPhone 1–2 m away, Nov 1 | 12/12 | 9/12 |

What the misses are:

- **Every field wrong, alert right**: all of them are Mandarin gates whose number the recognizer dropped
  ("A5" heard as "A", "B1R" as "BER"). The app shows the gate as unclear and, for Taoyuan flights, takes the
  gate from the airport's live flight data.
- **Keyword hints**: giving the recognizer the user's flight number made it hear that number where it
  wasn't said: CI110's delay became CI100's (a false alert), and other times the number turned into a gate
  ("自A5班機"). That is why the app sends no hints.

The same speech heard through AirPods' microphone from 1–2 m caught 3 fragments of 12 announcements, so
the app uses the phone's microphone by default.
