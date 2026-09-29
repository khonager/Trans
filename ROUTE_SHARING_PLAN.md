# Plan together and route sharing — product plan

Status: **product rethink**. The route-pairing engine is useful and should stay.
The experience around it needs to be brought back into the normal Trans route
planning model before link sharing or more backend work is added.

This document replaces the old backend-first route-sharing plan.

## Product decision

The feature is **Plan with someone**. Route sharing is one action at the end of
that flow.

A joint plan is not a special kind of social post and it is not an optimization
report. It is two normal Trans routes that overlap for part of the journey:

- my route;
- the other person's route;
- the part we travel together;
- a small explanation of the extra time or transfers each person accepts.

The selected result must become fully usable in the same way as any route in
Trans. Users should not lose alarms, maps, alternatives, live refresh, saving,
or route tabs just because the route was found through Plan with someone.

## Verdict on the current implementation and old plan

The hard part is better than the current UI makes it look. The app can already:

- plan from two origins to one destination;
- use a typed place or a friend's shared location as the second origin;
- detect ride, wait, and walk segments that the pair can share;
- rank cached pairs locally by extra time and transfers;
- widen the search progressively;
- warn when a friend's shared location is stale;
- send a plain-text summary to a selected friend;
- keep a companion route out of journey detection when it is marked with
  `companionName`.

The current experience still feels separate from Trans for four reasons:

1. **Setup becomes a control panel.** A second tinted card, explanation,
   location picker, continuous slider, and three constraint descriptions are
   inserted inside the existing route card. It is visually heavy before the
   user has even searched.
2. **Results speak like the algorithm.** Values such as “minutes of travel per
   minute together” are useful for ranking and tests, not for the primary UI.
   The cards are much larger and more analytical than normal route cards.
3. **Selecting a result throws half the result away.** “Open my part of this
   route” opens only the local user's journey. The companion route and the
   shared-plan context are then difficult to get back to.
4. **The feature stops before it becomes useful.** The chosen plan cannot yet
   be opened as two routes, received as a real plan, adopted, refreshed as a
   pair, or shared outside the app without becoming plain text.

The old plan correctly identified structured payloads, passive companion
routes, stale snapshots, public-link privacy, and detection provenance. It put
them in the wrong order. Public links and link management do not fix the daily
Plan with someone loop and should not block it.

## Visual evidence from the current build

The current setup, joint result, and normal route result were captured at a
390 × 844 logical mobile viewport:

- [Current Plan Together setup](test/audits/route-sharing/01-current-setup.png)
- [Current joint result](test/audits/route-sharing/02-current-results.png)
- [Current standard route result](test/audits/route-sharing/03-standard-results.png)

The captures are evidence of structure and hierarchy, not full accessibility
proof. Square icon glyphs are a limitation of the headless test font, not the
app's production icons. Contrast, focus order, screen-reader output, dynamic
type, and physical device behavior still need dedicated checks.

## Product principles

1. **Extend the normal planner.** Use the same search card, result list, route
   tabs, detail screens, actions, tokens, and language.
2. **One extra required decision.** Compared with a normal search, the user
   should only need to add the other person's starting point. The default route
   preference is Balanced.
3. **Human outcomes first.** Lead with time together, each person's arrival,
   and meaningful sacrifices. Keep ranking ratios and raw scores internal.
4. **Choose first, share second.** Sending, copying, and linking belong to the
   selected plan, not to every search-result card.
5. **Useful without an account.** Manual two-origin planning, opening both
   routes, and copying a plan work locally. An account is needed only to pick a
   friend's shared location or send inside Trans.
6. **No background cost without user value.** Re-rank cached routes locally,
   refresh only selected routes, and never re-search continuously while a
   preference control is dragged.
7. **Foreign routes never become presence by accident.** Viewing or receiving
   another person's route is not the same as adopting it as your own.
8. **Privacy is visible at the action.** Before a plan leaves the device, the
   user can see which route, place names, and optional note will be included.

## Language and information architecture

Use one term for planning and another for distribution:

- **Plan with someone**: enter the two origins and find a paired journey.
- **Time together**: the overlap within a result.
- **Send plan**: send the selected pair to a Trans friend.
- **Share plan**: copy it or use a public link outside Trans.

Do not call search results “shared routes.” In the rest of the app, “sharing”
already means privacy levels, locations, messages, and exported content. A
result can instead be “a route with Alex” or “a plan together.”

Recommended English copy:

| Surface | Copy |
| --- | --- |
| Mode label | Plan Journey Together |
| Second origin | Friend start station/address |
| Friend shortcut section | Friends sharing a location |
| Advanced setting | Plan Journey Together balance |
| Search action | Find routes for us |
| Results title | Routes with Alex |
| Shared segment | Together 08:20–09:00 on RE 1 |
| Selected-plan action | Send plan to Alex |

All copy must move into the ARB localization files. The current hard-coded
English/German branches should be removed rather than expanded.

## Target journey

### 1. Enter Plan with someone

Keep the existing search-icon tap/swipe gesture. It is an intentional part of
the Trans interaction design, not a temporary discovery mechanism.

Refine the header animation so the moving icon and the word `Together` behave
as one reveal. As the icon travels horizontally, its edge reveals the text
behind it. The word must not fade or expand separately from the icon's actual
position. Tapping the icon may complete the same transition without a drag.

Completing the gesture reveals one additional, lightly theme-tinted `Friend
start station/address` field above `From`. Reversing the gesture or tapping the
icon again returns to normal planning without clearing the user's own origin,
destination, or time.

### 2. Set the other person's start

`Friend start station/address` uses the same height, shape, spacing, suggestion
component, and validation as `From` and `To`. Its light theme tint and
person/location icon distinguish the companion input; color must not be the
only indicator.

When signed in, friends who currently share a usable location appear as quick
choices above suggestions. A selected friend shows:

- avatar/name;
- “updated just now / 8 min ago”;
- a change action;
- a warning only when the location is old enough to matter.

Manual places remain available even when signed out or when no friend shares a
location. A friend's raw coordinate is a search input, not a value that should
silently enter a share payload.

### 3. Choose a route preference

Default to **Balanced** and keep the main planner free of preference controls.
When Plan Journey Together is active, add one slider to the existing advanced
settings surface:

> Plan Journey Together balance

The slider controls the trade-off between faster individual journeys and more
time together. Do not show the current ratio, maximum-time, or
maximum-transfer constraint list in the primary planner. Give the slider a
human-readable semantic value such as `Balanced` for assistive technology.

Changing the preference re-ranks the already fetched journey pairs. It starts
new transport requests only when the current result window cannot satisfy the
new choice and the user explicitly asks to look further.

### 4. Read paired results

Use the normal route-results shell:

- back button and title;
- horizontal sort/filter chips;
- compact list cards;
- pull to refresh;
- earlier/later or wider-search controls at the list edges;
- the same margins, radius, borders, typography, and tap behavior.

Each joint result card should answer only four questions at a glance:

1. When do we each leave and arrive?
2. How long are we together?
3. Where is the shared section?
4. What does this choice cost each of us?

Example primary content:

```text
40 min together                       Best match
Together 08:20–09:00 · RE 1

You     08:14–09:00   +5 min
Alex    08:10–09:00   no detour
```

Useful badges are “No detour,” “Arrive together,” “Most time together,” and
“No extra transfer.” Do not show the ranking ratio. It can remain in debug
logs and unit tests.

Useful local sort chips are:

- Best match;
- Least detour;
- Most time together;
- Earliest arrival;
- Fewest transfers.

These sorts reuse the same result pairs and add no transport API requests.

### 5. Open the selected plan

Tapping a result selects the pair and opens **the user's own route** using the
normal route detail UI. At the same time, create the companion route as a
linked route tab.

The two tabs keep the existing route-tab model but show ownership clearly:

- `You · Central` with the normal directions icon;
- `Alex · Central` with a person icon and Alex's name;
- a subtle shared group marker or matching accent so their relationship is
  visible.

The selected plan retains a route back to its paired result list. Closing the
results view does not discard the companion route. Closing one linked route
does not close the other; a “Close plan” action may close both after one
confirmation.

The companion tab is passive:

- route steps, map, live data refresh, and alternatives are available;
- alarms, leave reminders, saving as my route, and journey detection are off;
- “Use this route for me” explicitly adopts it, changes ownership, and then
  enables the local-route features.

The own tab keeps all normal Trans behavior:

- map;
- live refresh and platform updates;
- alternatives;
- save connection and leave reminders;
- wake alarms;
- journey detection and presence, once the route meets the normal detection
  rules.

### 6. Send or share the selected plan

The selected plan, not every candidate, exposes a standard share action. The
sheet is ordered from cheapest and most private to most infrastructural:

1. **Send to Alex in Trans** — when a friend was selected.
2. **Copy plan** — structured plain text plus a locally rendered paired route
   ticket.
3. **Share link** — later milestone; clearly labels expiry and visibility.

This order lets the feature become complete without waiting for anonymous web
rendering.

## Capability and ownership rules

| Capability | My selected route | Companion route | Received route before adoption | Received route after adoption |
| --- | ---: | ---: | ---: | ---: |
| View steps and shared segment | Yes | Yes | Yes | Yes |
| Map | Yes | Yes | Yes | Yes |
| Live refresh | Yes | Yes | Yes | Yes |
| Alternatives | Yes | View only | View only | Yes |
| Save / leave reminder | Yes | No | No | Yes |
| Wake alarm | Yes | No | No | Yes |
| Journey detection / presence | Eligible | Never | Never | Eligible |
| Send or copy onward | Yes | Only as part of the plan | Yes, with privacy checks | Yes, with privacy checks |

Do not use `companionName != null` as the long-term ownership model or only
safety boundary. A missing display name should not make a foreign route
eligible for detection.

Add an explicit route ownership value, for example:

```dart
enum RouteOwnership {
  mine,
  companion,
  receivedUnadopted,
}
```

`RouteTab` should also carry `jointPlanId` and `participantId` (or an equivalent
small reference), so linked tabs and their lifecycle do not depend on labels.

## In-app sending

### Message shape

Use the existing encrypted message content as a versioned envelope so old text
messages remain readable and a database migration is not required for the
first structured version:

```jsonc
{
  "v": 1,
  "type": "joint_plan",
  "text": "Optional note",
  "plan": {
    "createdAt": "2026-09-01T08:00:00+02:00",
    "destination": { "id": "…", "name": "Central", "type": "stop" },
    "when": "2026-09-01T08:12:00+02:00",
    "isArrival": false,
    "preference": "balanced",
    "participants": [
      {
        "role": "sender",
        "name": "optional",
        "origin": { "id": "…", "name": "West", "type": "stop" },
        "journey": { "snapshot": {}, "departure": "…", "arrival": "…" }
      },
      {
        "role": "recipient",
        "name": "Alex",
        "origin": { "id": "…", "name": "North", "type": "stop" },
        "journey": { "snapshot": {}, "departure": "…", "arrival": "…" }
      }
    ],
    "sharedSegments": []
  }
}
```

The production encoder should strip unused provider fields and enforce a size
limit. It should not encrypt an enormous provider response simply because
`rawSource` happens to contain one.

This uses the privacy level of the current private-chat implementation. The app
must not claim high-security end-to-end encryption; the current key derivation
does not justify that claim.

### Chat card

The recipient sees a compact card in the existing private chat:

- `Plan with Jamie to Central`;
- the recipient's own departure/arrival and lines first;
- time together;
- optional note;
- `Open plan`.

Opening uses the stored snapshot immediately, including offline. A background
refresh re-runs only the two route requests needed by the chosen pair. If the
exact route is no longer found, keep the snapshot visible and show
“Connection may have changed” with `Refresh` and `Find alternatives`.

Receiving a plan never publishes presence. `Open plan` creates a
`receivedUnadopted` route; `Use this route for me` is the explicit adoption
step.

### Fallback

If the installed recipient version does not understand the envelope, the
message still needs a short human-readable fallback summary. During rollout,
senders may fall back to the current text-only message when the structured send
fails.

## Copying outside Trans without a backend

Before public links, extend the existing local `RouteShareTicket` idea to a
paired ticket. It should show:

- destination and date;
- both participants' times;
- transit lines;
- the shared segment;
- “Check live times in Trans.”

Write both the image and accessible plain text to the clipboard/share target.
This costs no server storage, works without an account, and gives users a useful
way to share to any messenger while public links are still deferred.

## Public links — later, not part of the first complete release

Public links are worthwhile only after the local and in-app flows prove useful.
They require App/Universal Links, anonymous retrieval, web rendering, expiry,
revocation, and a visible privacy surface.

When implemented, keep the old plan's secure shape:

- `https://trans.khonager.de/r/<128-bit-random-token>`;
- no anonymous table access; retrieve through a rate-limited RPC;
- default expiry of **7 days**;
- sender name hidden by default;
- links listed under **Settings → Data & Privacy → Shared links**;
- revoke at any time;
- no viewer profile, cookie, or per-viewer log;
- route visible without login; login offered only for save, alarms, or sending
  onward.

A public link may include the sender's selected route. It must not publish a
companion's route or a location derived from their live sharing without an
explicit consent model. Directly sending a joint plan to that companion is a
different and narrower disclosure.

## Privacy rules

These rules apply to messages, tickets, and links:

1. Never include live positions, journey-progress snapshots, location history,
   private favorites, tickets, or privacy-level metadata.
2. If a start came from a friend's live position, store a resolved stop/place
   and a human-readable name. Do not serialize the friend's raw coordinate.
3. Show a preview before sending outside the intended companion.
4. Sender display name is optional in exported content and off by default for
   public links.
5. A received or companion route remains ineligible for detection until the
   local user explicitly adopts it.
6. Snapshots expire from the active-plan UI after the journey. Existing message
   retention still applies to copies inside chat.
7. Log payload versions and failures, never full route payloads or tokens.

## Processing and network budget

Plan with someone can feel richer without becoming expensive:

- Search the two origins in parallel.
- Pair and rank the current result window locally.
- Preference and sort changes re-rank cached pairs.
- Cache equivalent station/address searches and deduplicate identical
  journeys before pairing.
- Keep the existing progressive expansion; start wider searches only after an
  explicit `Look further` / earlier / later action.
- Refresh only the selected pair, not every result card.
- Platform enrichment remains read-only and on demand.
- Render copied tickets locally.
- Do not poll for collaborative edits, read receipts, or live plan state.

The following tempting features are deliberately deferred because they create
meaningfully more API or product complexity:

- three-or-more-person planning;
- automatic meeting-point discovery;
- live co-editing or voting;
- background continuous re-optimization;
- automatic rerouting of both people after disruption;
- asking a friend for location through a new permission workflow.

## Implementation milestones

### Milestone 1 — make search and results feel like Trans (local only)

- Keep the swipe/tap search-icon mode switch and make the moving icon reveal
  `Together` directly as it travels.
- Reveal one lightly theme-tinted `Friend start station/address` field above
  `From` and reuse normal suggestions.
- Keep friend quick choices and stale-location feedback.
- Move the single Plan Journey Together balance slider into advanced settings.
- Rebuild joint result cards from the standard route-result card shell.
- Remove score/ratio language from production UI.
- Add local sort chips that re-rank cached pairs.
- Move all strings into ARB localization.
- Cover 320–600 px widths, both themes, long names, German, and 200% text
  scaling.

No migration or new service is needed.

### Milestone 2 — complete the selected plan (local only)

- Add explicit route ownership and `jointPlanId`.
- Selecting a result opens both linked route tabs.
- Render the companion name/person icon in the tab strip.
- Preserve a path back to the paired result list.
- Keep the own route's full map/save/alarm/alternative/refresh behavior.
- Keep companion routes passive with an explicit adopt action.
- Add a plan-level copy/share sheet.
- Add a local paired route ticket and text export.

This is the minimum complete Plan with someone release.

### Milestone 3 — real plans in private chat

- Add the versioned encrypted message envelope.
- Add a structured plan card to `private_chat_sheet.dart`.
- Open the recipient's route first and the sender's route as passive.
- Refresh the chosen pair in the background and retain stale snapshots.
- Keep text fallback for older clients and failed structured sends.
- Add payload-size, privacy-redaction, encryption, compatibility, and
  round-trip tests.

No public route table is needed.

### Milestone 4 — validate and polish

- Test the complete flow on a narrow phone and a large/text-scaled device.
- Test with no account, no friends, no shared location, stale location,
  offline opening, changed route, cancelled route, and a failed send.
- Add semantics for the entry action, friend choices, preference selector,
  result trade-offs, linked tabs, ownership, and adoption.
- Verify all tap targets are at least 48 × 48 logical pixels.
- Verify focus order and screen-reader announcements on a physical device.
- Confirm only local/adopted routes can reach detection and presence.

### Milestone 5 — public links, only after usage feedback

- Add `shared_routes`, owner management, revocation, expiry, and token RPC.
- Add App/Universal Link routing.
- Add an anonymous web renderer.
- Add no-login viewing and contextual login prompts.
- Add consent rules before any companion route can appear in public content.

## Technical shape

Recommended new domain objects:

- `JointPlan`: inputs, participants, preference, candidates, selected option,
  and lifecycle.
- `JointPlanParticipant`: stable participant id/role, display label, resolved
  origin, and route ownership.
- `RouteOwnership`: mine, companion, or received-unadopted.
- `JointPlanMessageV1`: size-limited, redacted transport envelope.

Recommended component work:

- Extract the private normal `_JourneyCard` shell into a reusable route summary
  component rather than copying its styling into the joint screen.
- Make a compact `JointJourneySummaryCard` that composes that shell with the
  second participant and shared-segment summary.
- Reuse the normal sort chip, load trigger, route tab, active route detail,
  snackbar, sheet, and empty/error patterns.
- Keep ranking math in `joint_journey_planner.dart`; do not let score concepts
  leak into widgets.

The existing journey detection provenance work should remain. Replace its
dependency on `companionName` with explicit ownership when Milestone 2 lands.

## Acceptance criteria

Plan with someone is ready when all of the following are true:

- The icon gesture and tap affordance work in both directions, and the icon's
  movement visibly reveals or hides `Together` as one continuous animation.
- Manual planning works while signed out.
- The additional setup requires one extra origin; Balanced is a good default.
- Result cards look and behave like normal Trans route results.
- A card explains time together and each person's sacrifice in plain language.
- Sorting and preference changes do not issue unnecessary API calls.
- Selecting a result preserves and opens both routes.
- The user's route keeps all normal route functionality.
- A companion/received route cannot affect presence before explicit adoption.
- A selected plan can be copied outside Trans without backend infrastructure.
- A selected friend can receive and open a real plan from chat.
- Stored snapshots remain readable offline and visibly stale when necessary.
- No exported payload contains a friend's raw live coordinate.
- English and German use localization files, not widget branches.
- Narrow phones, dark/light themes, long names, and enlarged text do not clip
  or overflow.

## Tests to add or update

### Product flow

- The icon gesture reveals and hides `Friend start station/address` without
  clearing the other fields.
- Signed-out manual planning works.
- Friend selection fills the origin and shows freshness.
- Preference changes re-rank without transport calls.
- A chosen result creates two linked tabs and opens the local user's tab.
- Back returns to the same joint result list and scroll position.
- Closing one linked tab leaves the other usable; `Close plan` closes both.

### Ownership and detection

- Companion and received-unadopted routes are never candidates.
- Adoption changes ownership and makes the route eligible under normal rules.
- Ownership remains correct across tab copy, refresh, save, and app restore.
- Missing names cannot turn foreign routes into local routes.

### Sending and receiving

- Message envelope round-trips both routes and shared segments.
- Legacy text messages still render.
- Oversized or malformed payloads fail safely and show fallback text.
- Raw friend coordinates and private metadata are redacted.
- The recipient sees their own route first.
- Stale or unmatched snapshots still open with a clear warning.
- Opening does not publish presence; adoption can.

### Visual and accessibility

- Golden/widget coverage for 320, 390, and 600 logical-pixel widths.
- Long participant and station names.
- English and German.
- Dark and light themes.
- Text scale 1.0, 1.5, and 2.0.
- Semantics labels describe ownership, time together, and extra travel.
- Keyboard/focus order follows mode control → friend start → from → to → time →
  search → results; the advanced balance slider has a meaningful semantic
  value.

### Public links, when that milestone starts

- Anonymous table `select` is impossible.
- Unknown, expired, and revoked tokens return no payload.
- Default expiry is seven days.
- Public payloads omit sender name by default and never include companion live
  coordinates.
- Link opens read-only without login; account prompts are dismissible and
  action-specific.

## What not to build yet

Do not start `shared_routes`, anonymous web rendering, link analytics, group
planning, live collaboration, or meeting-point optimization before Milestones
1 and 2 are complete. They would make the feature larger without fixing why it
currently feels foreign or unfinished.

The best next implementation slice is Milestone 1 followed immediately by the
linked-route behavior in Milestone 2.
