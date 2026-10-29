# Evaluation set (prepared before the hackathon)

These two files were written on Oct 23, 2026, before the hackathon started. With the organizers'
permission they are included here, clearly labeled, so anyone can re-run the scores. No code from
before the hackathon is in this repository; the rules being scored were rewritten in Swift during it.

- `announcements.csv`: 47 synthetic airport announcements in Mandarin and English, modeled on Taoyuan
  Airport: gate changes, delays, boarding, final calls, cancellations, a name call, and traps such as
  CI110 and CI1000 for a traveler on CI100, a gate correction, and spoken codes ("C-I一零零").
  Each row has the answer: flight, event, new gate or time, and whether the CI100 traveler should be alerted.
- `announcements_heldout.csv`: 10 more announcements in new wording, kept aside and never used to
  adjust the rules.

All scripts are invented. They contain no recordings, real passengers, or personal data.

## Re-running

```
cd ShunfengCore
swift run shunfeng-listen eval ../evaluation/prepared-before-hackathon/announcements.csv
swift run shunfeng-listen eval ../evaluation/prepared-before-hackathon/announcements_heldout.csv
```

This scores the written scripts, without speech recognition, as a traveler on CI100 to Tokyo.
"Notify right" means the app would alert for exactly the announcements about CI100; "everything
right" also needs the event, gate and time to match.

## Results (Oct 29, 2026)

| Set | Notify right | Everything right |
| --- | --- | --- |
| 47 announcements | 47/47 | 47/47 |
| 10 held out | 10/10 | 7/10 |

The three held-out misses are wordings the rules don't know yet ("ready for boarding", "brought
forward", "depart from gate B2 instead of A5"). In each one the app still hears the flight number, so it
shows "maybe about your flight, please check" instead of a wrong event. They are left unfixed so the
held-out set stays a fair test.
