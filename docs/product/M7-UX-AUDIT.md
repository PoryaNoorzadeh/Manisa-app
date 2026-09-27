# M7 product experience audit

Status: UX direction approved by product mandate; this document is the implementation contract before UI work.

## Product promise

Manisa should let a Persian-speaking household add a device, understand its true state and control it without learning Matter, fabrics, endpoints or server concepts. Local network operation is the default mental model. The UI must never imply that an unknown or stale state is off.

## Existing experience audit

| Flow | Current issue | Product decision |
| --- | --- | --- |
| First home | Functional but generic | Explain the value in one sentence, then ask only for the home name |
| Add device | QR, preparation, Wi-Fi and progress exist | Keep the verified three-stage flow; use plain Persian, real progress states and a support escape hatch |
| Home | Home identity, rooms, every device detail, sensors, power, errors, scenes and schedules compete in one long page | Make Home the daily-control surface; move routines into their own destination and keep technical settings behind device menus |
| Device control | Multi-output identity is correct but cards can become very long | Lead with name/state/action; reveal dimmer, color, sensor and energy details in a predictable hierarchy |
| Rooms | Rooms are sections mixed into the dashboard | Treat spaces as a first-class way to browse, while keeping a compact home overview |
| Scenes | Safe execution/readback is strong; editor is dense | Preserve safety semantics; group selection, desired state and optional lighting settings |
| Schedules | Safe execution contract is strong; wording dominates the screen | Put the contract in a concise trust notice and make active state/time/day scannable |
| Recovery | Accurate but errors are spread across banner, cards and controls | Use one home-health summary plus local recovery actions beside the affected device |
| Settings | Home, rooms and device settings are fragmented | Create a calm settings destination for home identity, spaces, connectivity and support |

## Benchmark synthesis (patterns, not visual copying)

| Product | Pattern worth learning | Manisa adaptation |
| --- | --- | --- |
| Apple Home | Rooms and categories reduce search; scenes are distinct from accessories | Clear daily control and space grouping; no Apple-like tile imitation |
| Google Home | Favorites provide a fast personal start; all devices remain available | Home begins with status and favorites, while full inventory stays one tap away |
| SmartThings | Favorites, devices and routines have separate responsibilities | Three primary destinations instead of one overloaded page |
| Home Assistant | Areas and truthful entity state are powerful | Keep state honesty and room awareness, remove dashboard-building complexity |
| Aqara | Scene/automation concepts map to household language | Use «سناریو» and «زمان‌بندی» with examples; avoid rule-builder complexity in this milestone |

## Information architecture

1. **خانه** — home health, favorites, compact room/device overview and add-device action.
2. **کارها** — manual scenes and schedules. A future automation rule builder belongs here.
3. **تنظیمات** — home name, rooms, local connection explanation, support and app information.

Device-specific settings remain inside each device card/menu because users look for them in context. Essential actions must never rely on long-press or hidden gestures.

## Core flow contracts

### First run

Value statement → home name → empty home with one prominent add-device action.

### Add device

Scan or enter code → prepare/reset device → Wi-Fi credentials → event-based commissioning status → immediate first control. If commissioning succeeds but state read fails, say: «وسیله اضافه شد؛ وضعیت هنوز دریافت نشده».

### Daily control

Open app → see home health → tap favorite/device control → optimistic animation is allowed only while a command is pending → final state comes from device readback.

### Recovery

Unavailable is visually and verbally different from off. Preserve last confirmed state, disable unsafe repeated commands, retry connection automatically and expose one manual «تلاش دوباره» action. Never replay a failed write automatically.

### Scene and schedule

Choose outputs → set desired state → optionally set brightness/color → review → save. Execution reports each output independently. Schedules clearly state that they run on this phone while the app is active and only catch up within ten minutes.

## Iran-market constraints

- Persian-first RTL, Persian numerals, large readable labels and 48dp minimum targets.
- Android-first and resilient on modest devices; no ornamental animation that delays control.
- Do not ask for region/server selection for local control.
- Distinguish «اینترنت» from «شبکهٔ خانه» in all recovery copy.
- Avoid protocol jargon in primary flows; technical details are reserved for support.
- Do not claim offline/background behavior that hardware testing has not confirmed.

## Acceptance criteria

- A new user can add the first switch without knowing Matter terminology.
- A returning user can reach a favorite control in one screen and a non-favorite device in at most two taps.
- Off, unavailable, stale and pending are visually and semantically distinct.
- Scenes and schedules no longer compete with device controls on Home.
- Existing commissioning, readback, deletion, recovery and automation safety behavior remains intact.
- Text scaling to 200% does not hide primary actions.

## Sources

- Apple Home user guide: https://support.apple.com/guide/iphone/intro-to-home-iph22d98bbca/ios
- Google Home organization: https://support.google.com/googlehome/answer/17075254
- SmartThings app structure: https://news.samsung.com/global/samsung-smartthings-unveils-new-interface-offering-customers-a-more-dynamic-connected-home-experience
- Home Assistant dashboards/areas: https://www.home-assistant.io/dashboards/dashboards
- Aqara app feature overview: https://docs.aqara.com/docs/aqara-life/feature-overview/
