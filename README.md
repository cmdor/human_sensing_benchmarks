# Health Sensing Trials

A Flutter application for exploring auditory and visual perception thresholds.
Results are **for informal sensing and perception exploration only** and are not
intended for medical diagnosis, screening, or clinical assessment. Outcomes
depend on the device(s), calibration, environment, and individual participant.

---

## Features

### Extendible sensing framework

Each experiment is built on a shared `TrialRunner` / `TrialFramework` pipeline:

- **`TrialRunner<Trial, Guess>`** — generic engine that holds a `generateTrial`
  function, a `scoreTrial` function, and a `reduceState` reducer. Adding a new
  experiment means supplying these three functions; the session bookkeeping,
  event logging, and JSON export are handled automatically.
- **Adaptive staircase** — a reusable N-down 1-up staircase with configurable
  step sizes, decay, and reversal-based threshold estimation (shared utility).
  Used by gap detection, pitch JND, amplitude JND; easy to wire into new trials.
- **Experiment metadata** — each session is tagged with kind and title so the
  outcomes UI can route charts and summaries correctly.

#### Included experiments

| Experiment | Modality | Method |
|---|---|---|
| Contrast Finder | Visual | Multiplicative descent, bit-depth estimate |
| E Rotation Trial | Visual | Adaptive scale, arc-minute acuity |
| Pitch Frequency Range | Auditory | Slider range submission |
| Sound Gap Detection | Auditory | Adaptive staircase (gap ms) |
| Pitch JND | Auditory | Adaptive staircase (Hz delta) |
| Amplitude JND | Auditory | Adaptive staircase (dB delta) |

---

### Session time and engagement reporting

Every session records a start timestamp and a finish timestamp. While a trial
is in progress, a live **elapsed timer chip** updates every second. After the
run ends the elapsed time freezes at the true session duration.

Per-trial **reaction times** (ms from trial presentation to guess submission)
are captured in the event log and shown in the reaction-time chart on the
Outcomes screen. The `SessionStatsBar` widget at the top of each trial page
also shows running accuracy, wrong-streak, and the time of the last correct
response.

---

### Save and clear data

Sessions are persisted locally (via `shared_preferences`). Each completed trial
appends a JSON record containing:

- A `summary` map (experiment kind, title, accuracy, scored counts, elapsed
  time, and any experiment-specific metrics such as `bitDepthEst`, `lowHz` /
  `highHz`, `visualAngleArcMinutes`).
- A chronological `events` array with every `trial_started`, `guess_submitted`,
  and `trial_scored` event, each timestamped to the millisecond.

From the **All Outcomes** screen you can:

- Browse all saved sessions with a one-line subtitle per session.
- Tap a session to open the full detail view (charts + table).
- **Copy JSON** for any session to the clipboard for external analysis.
- **Clear all** sessions with the delete button in the app bar.

---

### Write to PDF

Two PDF export paths are available, both reachable from the **All Outcomes**
screen:

| Action | Scope | How to trigger |
|---|---|---|
| Single-session export | The open session's charts + summary metadata | PDF icon in the session detail app bar |
| All-sessions export | Every saved session, one page each | PDF icon in the All Outcomes app bar |

Each exported page contains:

1. Session metadata (start time, experiment title, accuracy, scored count,
   experiment-specific summary fields).
2. Experiment graphic — for Pitch Frequency Range this is the spectrum-bar
   visualization showing the submitted low and high frequency markers; for
   staircase experiments this is the per-trial level chart with the threshold
   line.
3. Reaction-time chart across all trials.

On Flutter Web the PDF is downloaded as a `.pdf` file. On other platforms it
is sent to the system print dialog.

---

## Getting started

```bash
flutter pub get
flutter run -d chrome        # web
flutter run -d macos         # desktop
```

Screen calibration (used by the E Rotation Trial for accurate arc-minute
measurements) is accessible from the home screen via **Calibrate Screen**.

---

## Architecture

The codebase is organized in layers. Individual modules under each folder may
grow or split over time; the boundaries below are the stable picture.

```text
App shell (routing, theme, home trial picker)
        │
        ├── Sight experiments ──► trial-specific logic and UI
        └── Sound experiments ──► trial-specific logic and UI

Shared foundation
        │
        ├── Trial framework (runner, state, event log, JSON export)
        ├── Staircase, outcomes derivation, shared charts / tables
        ├── Persistence (load, append, clear)
        └── Calibration helpers and calibration UI

Reporting surface
        │
        └── Saved-session browser, detail charts, PDF raster export
```

**Flow:** An experiment page constructs a `TrialRunner` with trial-specific
generators, scoring, and reducers. On completion it merges a summary map and
hands the report to the session store. The outcomes UI rebuilds charts from
stored events and summaries without knowing each experiment’s internals beyond
inferred kind and optional summary keys.

