# Fleet Operations Command

![Fleet Operations Command](assets/fleet-operations-command.png)

**Protect. Recover. Restore. Return.**

Fleet Operations Command (FOC) is a player-first fleet readiness, patrol, and distress-response console for **X4: Foundations**. It turns large-empire fleet management into clear, bounded decisions while keeping the player in command.

[![Steam Workshop](https://img.shields.io/badge/Steam-Workshop-1b2838?logo=steam)](https://steamcommunity.com/sharedfiles/filedetails/?id=3793624775)
![Release](https://img.shields.io/badge/release-v1.19-blue)
![Game](https://img.shields.io/badge/game-X4%3A%20Foundations-orange)

## Current release

- Public version: **1.19**
- Governed runtime identity: **Build 020 / extension version 119**
- Release archive: [`dist/FOC_v119_GA.zip`](dist/FOC_v119_GA.zip)
- Release SHA-256: `5D8870D3E21ABF6D84D4E64BFD3E9D8BEC802475301218D0ADD200D28A47C676`
- Steam Workshop: [Fleet Operations Command](https://steamcommunity.com/sharedfiles/filedetails/?id=3793624775)

This repository contains the same six runtime files as the tested and accepted GA release. Publication files, documentation, and artwork are outside the installable `jk_foc` folder.

## Features

- **One-button patrol deployment** — configure a complete plan and send only the selected fleet.
- **Flexible patrol doctrine** — choose Home, range, sector scope, patrol pattern, distress classes, urgency, hull thresholds, and return behavior.
- **Native X4 orders** — uses Patrol, Protect Position, and Attack orders with native readback before reporting success.
- **Bounded distress response** — reacts to fresh attacks while enforcing range, readiness, ownership, lock, mission, manual-order, and identity safeguards.
- **Fleet readiness clarity** — separates proven captain vacancies from unknown evidence.
- **Captain Academy** — maintains a bounded trainee roster, uses native seminars, and requires approval for exact trainee-to-ship assignments.
- **Preview before action** — evaluates doctrine and response eligibility before mutation.
- **Evidence-preserving activity** — reports what was requested, accepted, blocked, and returned by X4.
- **Large-empire bounds** — capped sampling, bounded results, duplicate suppression, and a single 30-second automation scheduler.

## Player authority

FOC is advisory and approval-driven by default. Full Automation is an explicit mode and uses the same safety gates as manual dispatch.

FOC does not purchase ships, spend credits, move cargo, replace captains without approval, override player-piloted ships, or bypass mission and story protection. Missing or uncertain evidence blocks action instead of being treated as safe.

## Installation

### Steam Workshop

Subscribe on the [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3793624775), allow Steam to download the extension, then enable **Fleet Operations Command** in X4's Extensions menu if needed.

### Manual installation

1. Close X4: Foundations.
2. Download [`FOC_v119_GA.zip`](dist/FOC_v119_GA.zip).
3. Extract the lowercase `jk_foc` folder into the game's `extensions` directory.
4. Confirm the final path ends with `X4 Foundations/extensions/jk_foc/content.xml`.
5. Start X4 and enable Fleet Operations Command if needed.

See [Installation and updates](docs/INSTALLATION.md) for more detail.

## Quick start

1. Open Fleet Operations Command from the in-game interface.
2. Select **Fleets** and choose a player-owned combat fleet.
3. Choose its Home point.
4. Configure patrol coverage, distress rules, thresholds, and return behavior.
5. Review the summary, then select **Send This Fleet on Patrol**.
6. Check **Activity** for native order readback or a precise blocker.

See the [Quick-start guide](docs/QUICK_START.md).

## Repository layout

```text
jk_foc/       Installable X4 extension source
dist/         Exact GA installation archive
assets/       Project artwork
docs/         Public installation and operator documentation
```

## Support

When reporting a problem, include:

- the visible FOC result or blocker;
- the affected fleet and action;
- what you expected to happen;
- whether another mod recently changed the affected ship; and
- the relevant portion of the X4 debug log.

Use the repository's [Issues](https://github.com/razoreqx1/FOC/issues) page after checking for an existing report.

## Credits

- Created by **RazorEQX**
- Development support: **Scout AI Development Partner**
- Ship-tracking collaboration: **UPB**

Fleet Operations Command is an independent community extension for X4: Foundations and is not affiliated with or endorsed by Egosoft.

## Rights

Copyright © 2026 RazorEQX. No open-source license has been granted. The source is publicly viewable, but reuse, redistribution, or derivative publication requires permission from the copyright holder.
