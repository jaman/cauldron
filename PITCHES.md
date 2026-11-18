# Cauldron Slate 01 — three games for the Cauldron + BEAM stack

Status: **pitches for a decision, not a plan with dates.** Three games, each chosen
because the combination of Cauldron and the BEAM is not the implementation detail but
the reason the game can exist. One is a 3D competitive game, one is a persistent
co-op world, one is a single-player stop-motion clay adventure.

The art in this document was made while writing it, through the NxDiffusion Studio's
MCP server, so the look is a test of the pipeline as much as an illustration. The
provenance is in the appendix.

---

## The bar

"AA" here means a game with a specific look and a full production around it: 8–20 hours
of authored content, a complete score and sound design, four front ends (terminal,
desktop window, browser, tablet), 60 frames a second, localisation, accessibility,
and enough netcode and tooling that it can be run as a service. It does not mean
photoreal graphics or a hundred hours of filler.

Each pitch is scoped twice:

* a **vertical slice** of 10–12 weeks that can be played by strangers, and
* a **1.0** of 14–18 months for a team of 9–12.

Each has a kill criterion. A pitch that cannot fail is a pitch nobody can decide.

## The short version

Three games:

* **HEAVY WEATHER** — 3D mech duels where the storm is the third fighter and every
  part you lose stays lost. 1v1 rollback, 2v2, a 12-mission campaign. The 3D/GPU and
  netcode showcase.
* **LOWTIDE** — a co-op salvage-survival game where the sea pulls back for twenty
  minutes and the whole harbour runs out to meet it. Persistent shared Cradle, ssh and
  browser, seasons. The BEAM showcase.
* **GREENWARE** — a stop-motion clay adventure where you fix a drying world by hand.
  Single-player, 10–12 hours, 60 mends, three endings. The claymation showcase.

If the studio can only build one: **GREENWARE**. It is the smallest, the most
distinctive, and the only one whose look has already been tested in this document. If
the goal is a long-lived service: **LOWTIDE**. **HEAVY WEATHER** is the highest ceiling
and the highest risk; it earns a greenlight only after a six-week determinism spike.

## Contents

1. [The bar](#the-bar) · [The short version](#the-short-version) · [The three at a glance](#the-three-at-a-glance)
2. [HEAVY WEATHER](#heavy-weather)
3. [LOWTIDE](#lowtide)
4. [GREENWARE](#greenware)
5. [Why these three](#why-these-three) · [If you can only build one](#if-you-can-only-build-one)
6. [The asset factory](#the-asset-factory) · [The production machine](#the-production-machine) · [The next thirty days](#the-next-thirty-days)
7. [Appendix — the art in this document](#appendix-the-art-in-this-document)

## The three at a glance

| | **HEAVY WEATHER** | **LOWTIDE** | **GREENWARE** |
| --- | --- | --- | --- |
| **Genre** | 3D competitive mech duel, "slow fighter" | 1–8 player co-op isometric salvage-survival | single-player stop-motion clay adventure |
| **Players** | 1v1 rollback, 2v2, local, bots | 1–8 online, persistent shared harbour | one |
| **Session** | 6–9 minutes, best of three | ~30 minutes (harbour + 20-minute tide) | 20–40 minutes |
| **Length** | 12-mission campaign, 40+ hours with ranked | 60+ hours, seasonal | 10–12 hours, three endings |
| **Lead front end** | window / browser; terminal as the purist mode | terminal over ssh; browser for reach | window / browser / iPad; terminal as a pixel cut |
| **Engine bet** | GPU 3D + rollback + one client for four front ends | many worlds + distribution + persistence + live code | custom pixels + the asset factory + pure-world saves |
| **Art pipeline** | Blender hard-surface + Studio textures | Studio pixel art (`assets.exs`), parallax, volumes | Blender puppets at 12 fps + Studio art department |
| **Biggest risk** | fixed-point determinism across architectures | live-ops and lighting | puzzle design with free-form clay |
| **Vertical slice** | 10 weeks | 12 weeks | 10 weeks |
| **1.0** | 14 months, 9 people | 18 months, 12 people | 15 months, 10 people |

---

# 01 — HEAVY WEATHER

![Heavy Weather key art](pitches/art/heavy-weather.png)

> *The storm is the third fighter.*

**Working title.** 3D mech duel. 1v1, 2v2, campaign. Six to nine minutes a match.
Window, browser, terminal, iPad. One client module.

*Anchors: Armored Core VI's weight, Nidhogg's readable duels, MechWarrior's part
damage. The difference: a best-of-three where the third round is a machine neither
player brought.*

## The pitch

The Low is a failed terraforming belt: a thousand kilometres of salt flats, sea walls
and turbine fields under a sky that never clears. The Company owns the weather. The
crews own the machines that walk through it.

You are a **dowser** — a pilot who can read a storm cell the way a sailor reads water.
Your rig is forty tons of salvage, hydraulics and a reactor that runs too hot. You
fight other dowsers over claims, over salvage, over the right to keep working. The
storms do not care who wins.

**The hook: every part you lose stays lost.** A rig is not a health bar. It is a
hierarchy of parts — sensor head, reactor torso, two arms, two legs — and each part
has its own armour and structure. Break an arm and its weapon goes with it. Break a
leg and the whole machine lists, drags, and cannot turn on the spot. Break the reactor
and you have five seconds to eject before the machine becomes a crater.

Between rounds, the arena is still there: the wreck of your arm, the cannon you tore
off your opponent's shoulder, the leg you sheared at the knee. You have twenty
seconds to bolt one of them onto your rig and go back out. **The match is a salvage
conversation.** By round three, both machines are hybrids of what they started as.

## The world

Forty years ago the Company seeded the Low with a weather engine it could not switch
off. The storms are the engine's exhaust. The people who stayed are the ones who
learned to work inside them: **weatherworks crews**, part miners, part firefighters,
part mercenaries. The Company still pays for the salvage, and still sends its own rigs
to collect debts.

Names the game uses like places: **Mother Serein**, the storm that never moves;
**Nine Bells**, the one that rings the turbine field; **the Widow**, the one that took
the last crew. Storms are the levels. Each has a personality you learn.

The campaign, *The Long Low*, is twelve missions across three acts. You start with a
debt, a borrowed MULE and a crew of three. You end with a choice about who the Low
belongs to. It is not an epic; it is a season of work, told in radio traffic, mess-hall
arguments and the state of your machine. Roughly 20,000 words, 90 minutes of score,
and a lot of silence broken by rain.

## The loop

**Moment to moment.** Movement is heavy and committed: a step is a decision, a turn
costs momentum, a sprint builds heat. Weapons are grouped by what they ask of you:

* **Direct** — cannon, rail, plasma. Line, lead, punish.
* **Indirect** — mortar, missile, mine. Deny space, force movement.
* **Contact** — flail, drill, ram. Trade armour for position.
* **Support** — smoke, beacon, repair, net. Change what the storm means.

Heat is the second clock. Weapons, sprinting and venting all move it. Overheat and
you shut down for two seconds — an eternity. Vent deliberately and you make a steam
cloud that blinds sensors, yours included. The storm is the third clock: a 45-second
cycle of **gathering**, **breaking** and **clear**. In the break, lightning finds the
tallest metal on the field, which is usually a mech. You can plant a rod to steal it.

**A round.** Ninety seconds, or until a rig is disabled. Best of three. No respawns.
Between rounds: twenty seconds of salvage and refit.

**A match.** Six to nine minutes, including the refit. A match should end with both
players able to say what they lost and why.

**A season.** Ten weeks, placements, divisions, a new storm and a new arena each
season, daily contracts, a replay theatre, and a weekly "storm front" modifier that
changes one rule for everyone (no radar; the sea is rising; every rig starts at
half armour).

## Depth

The depth is in three places, in this order:

1. **The refit.** A best-of-three is a small drafting game. Do you take the arm you
   lost, or the arm your opponent is not expecting? Do you give up a leg for a heavier
   torso? Every round changes the matchup.
2. **The storm.** Wind pushes projectiles and mechs; rain shortens lock-on and hides
   heat plumes; lightning is a resource and a threat. The arena is not a backdrop, it
   is a participant with a timetable.
3. **The chassis.** Eight rigs at launch, each a job that learned to fight:
   **MULE** (biped, balanced, salvage claw), **KILN** (quadruped, heat, mortar),
   **HERON** (reverse-joint, tall, rail), **TOAD** (tracked, low, mines),
   **WIDOW** (six legs, climbing, ambush), **CHOIR** (support, drones, repair),
   **ANVIL** (brawler, shield, ram), **MOTH** (light, jump jets, recon). Each has a
   different silhouette, gait, heat curve and refit grammar. A player should recognise
   a rig by its footsteps before it is on screen.

Around that: a mech lab (paint, decals, wear; no stats behind cosmetics), pilot
skills that are sidegrades rather than power, a training mode with a frame-data
readout, and a replay theatre that lets you scrub to the exact frame a limb came off.

## Content and length

| | At 1.0 |
| --- | --- |
| Campaign | 12 missions, 3 acts, 3 boss rigs, ~8 hours first pass, 20 hours to master |
| Rigs | 8 chassis, 24 weapons, 6 utility systems |
| Arenas | 12, each with its own storm table and 3 weather states |
| Multiplayer | 1v1 ranked, 2v2, local versus, bots at five skill levels |
| Progression | 10-week seasons, 40 cosmetic unlocks, daily contracts |
| Replay | Every match recorded; shareable; spectate live with a 10-second delay |
| Total | 40+ hours for a competitive player; 12–15 for a campaign player |

## Multiplayer and the BEAM

**1v1 is peer-to-peer rollback.** Each machine runs the same pure world at 30 Hz; the
renderer interpolates to 60–120 Hz. `Cauldron.Link` carries the rollback messages over
one TCP connection, `Cauldron.World.Rollback` keeps a seven-frame window and a
two-frame input delay, and `Cauldron.Game.checksum/1` catches desyncs. That is enough
for roughly 150 ms of round-trip latency without a server in the middle.

**2v2 and ranked validation are server-side.** A normal `Cauldron.World` on a regional
node holds four players, runs at 30 Hz, and sends authoritative snapshots. Ranked
1v1 can be relayed through the same node for validation while still using rollback
between the two clients.

**Why the BEAM is the right host.** Every match is an isolated process tree: a crash
is one match, not a region. A balance patch is a hot code load, not a maintenance
window. Regional matchmaking is a distribution problem the runtime already solves.
A tournament is 400 worlds on one box. The lobby, the replay store, the spectate feed
and the season clock are ordinary OTP services, not a second architecture.

Targets for the slice: 1,000 concurrent 1v1 matches on one 32-core node; 99.9% of
matches with zero desyncs; p95 input-to-photon under 100 ms at 60 ms RTT.

## Look

Hard-surface industrial brutalism, wet and rusted. Cold teal storm light against
sodium-orange cockpit lamps; no clean science fiction. Rigs are built from parts that
were designed for jobs, not war: a crane arm, a firefighting tank, a mining drill.
Decals are corporate, hand-painted over, faded. Rain is a character: it streaks the
camera, pools in footprints, and turns every light into a smear.

The camera sits low and behind the shoulder, 55–60° field of view, so a forty-ton
machine feels forty tons. A tactical overlay (hold a button) pulls to a storm map:
wind vectors, lightning timers, part damage. Ray-traced shadows and reflections on the
Metal path; a "storm grain" post pass that can be turned off.

In the terminal, the same scene is captured from the GPU at 960×540 and sent through
kitty, iTerm2 or sixel at 30 fps; the HUD is drawn at the terminal's pixel density.
The window is the reference experience, the terminal is the same game with the lights
off.

## Sound

Servos, hydraulic hiss, the whine of a reactor under load, rain on metal, thunder as
a physical event with a delay based on distance. Every weapon has a distinct attack
and release; every part has a failure sound. The score is low brass, taiko, distorted
cello and a single detuned piano, in three layers (gather / break / clear) that switch
on bar lines through `Cauldron.Audio.Music`. Lightning is scored: the music listens to
the storm table, not the other way around.

## How it is made

* **Blender** for every rig: a kitbash library of industrial parts, hard-surface
  modelling, PBR materials, decals, and a simple part hierarchy (no character rigs, no
  skinning — a deliberate cost saving). Export glTF, instance in `cauldron_3d_scene`.
* **The Studio** for concept art, texture sheets, decals, skyboxes, campaign
  storyboards, key art and marketing. `make_3d` for props and wreckage; `edit_image`
  to keep a rig's livery consistent across angles.
* **ACE-Step** for the score as stems (brass, percussion, drone), `make_sfx` for the
  weapon and servo library, then `Cauldron.Audio.Music` layers at runtime.
* **The engine** does the rest: `cauldron_gpu` for Metal/Vulkan, `cauldron_3d_scene`
  for instances and lights, `Cauldron.Link`/`Rollback` for netcode, `Cauldron.Replay`
  for the theatre, `Cauldron.Robot` for bots, `cauldron_native` for iPad.

## On Cauldron

| Need | Module |
| --- | --- |
| Deterministic world, fixed tick | `Cauldron.Game`, `Cauldron.World` |
| Rollback netcode | `Cauldron.Link`, `Cauldron.World.Rollback` |
| Replays, spectate, frame data | `Cauldron.Replay`, `Cauldron.Replay.Viewer` |
| Bots, training | `Cauldron.Robot` |
| Parts, state machines, hit-stop | `Cauldron.States`, `Cauldron.Effects`, `Cauldron.Impact` |
| 3D scene, GPU, capture | `cauldron_3d_scene`, `cauldron_gpu` |
| Browser 3D | `cauldron_3d_net` |
| iPad / iPhone | `cauldron_native` |
| Spatial audio, music layers | `Cauldron.Audio`, `Cauldron.Audio.Music` |
| Saves, cosmetics, ledger | `Cauldron.Save`, `Cauldron.Ledger` |

## What the engine does not have yet

1. **Fixed-point determinism.** This is the one that decides the project. Floats are
   not bit-identical across ARM and x86 once trigonometry and square roots are
   involved, and `Cauldron.Game.checksum/1` will find it. The simulation needs
   integer/fixed-point maths and lookup-table trig; rendering can keep floats. Cost:
   3–4 weeks, and a test that runs the same replay on both architectures.
2. **2v2 rollback.** `Cauldron.Link` is two worlds. Four players on two machines is a
   spike, not an assumption. Fallback: 2v2 is server-authoritative.
3. **A matchmaking and season service.** Lobbies, ratings, parties, region selection,
   season clocks. Build on `Cauldron.Worlds`, `Cauldron.Sessions` and `Cauldron.Chat`;
   roughly 6 weeks.
4. **Terminal 3D throughput.** Measure GPU capture → encode → kitty at 960×540/30 fps
   before promising it. If it costs more than 8 ms a frame on the render node, the
   terminal mode runs at 20 fps or 640×360.
5. **A 3D collision/arena authoring path.** `cauldron_3d` has hulls, BSP and walk grids;
   a mech needs a simpler capsule/box sweep and part hitboxes. Game-side, ~3 weeks.

## The vertical slice (10 weeks)

**One rig, one storm, one arena, two players, one reason to rematch.**

* MULE vs KILN on the sea-wall arena, best of three, refit between rounds.
* Two weapons each, four part types, limb loss, reactor ejection.
* The storm cycle and lightning, wind on projectiles, rain on sensors.
* 1v1 rollback over a simulated 80 ms link, with a desync counter on screen.
* Window and terminal builds of the same client module; one 60-second music cue.
* A single-player mission against a bot, to prove the campaign camera and tone.

Out of scope: 2v2, ranked, cosmetics, the other six rigs, the story.

**Team:** 1 designer, 2 engineers, 2 artists, 1 audio, 1 producer/QA (7).
**Exit test:** ten strangers play ten matches; eight ask for a rematch; no desyncs;
median match length 7–9 minutes.

## 1.0

Fourteen months after the slice, nine people. Eight rigs, twelve arenas, twelve
missions, 1v1 ranked and 2v2, two seasons of cosmetics planned, localisation into
five languages, accessibility (colour-blind palettes, remapping, reduced shake,
telegraph scaling in campaign only), and a replay theatre.

## Risks

| Risk | Mitigation | Kill criterion |
| --- | --- | --- |
| Float desync | fixed-point sim; replay on ARM and x86 | any desync in 1,000 ranked matches after the fix |
| Slow game feels unresponsive | 30 Hz sim, 120 Hz render, input buffering, generous cancel windows | playtest: players cannot feel the difference between 30 and 60 Hz sim |
| Content cost of eight rigs | six at launch, two post-launch; share 70% of parts | rig #5 costs more than 3 weeks |
| Terminal 3D is a novelty | window/browser are the lead; terminal is a mode | capture path over 8 ms/frame |
| P2P cheating | server-validated replays, statistical bans; ranked relay | a cheat survives two weeks in the wild |

## Why it wins

It is a fighting game for people who do not have the hands for a fighting game, and a
mech game for people who are tired of twitch. The refit is a genuinely new axis: a
best-of-three where the third round is a machine neither player brought. The storm
gives every match a shape without a designer scripting it. And it is the cleanest
demonstration of the whole stack: 3D, GPU, rollback, replay, four front ends, one
world.

---

# 02 — LOWTIDE

![Lowtide key art](pitches/art/lowtide.png)

> *The sea gives back what it took. For twenty minutes.*

**Working title.** 1–8 player co-op isometric salvage-survival. Persistent shared
harbour. Seasons. Terminal-first, browser for reach, desktop and tablet beside.

*Anchors: Deep Rock Galactic's co-op shape, Dredge's tone, Barotrauma's tension. The
difference: the tide is the map, and the harbour is the progression.*

## The pitch

Forty years ago the sea drowned the city of **Vessel** in a single night. It did not take
it for good. Every two hours the water pulls back for twenty minutes, and the streets
come up black and streaming and full of things worth carrying home.

You live on the **Cradle**, a floating harbour welded out of things that floated. You
are a **wader**: part diver, part scavenger, part undertaker. You go down into the city
with three other people, a lamp, a cutting tool and a rope, and you come back before
the sea does.

**The hook: the map is the clock.** Every shard shares one tide table. When the water
returns, the whole coastline goes under at once, and whatever is below stays below
until the next tide. There is no instance timer on your screen; the water is the timer,
and it is already moving. A dive is twenty minutes of "one more room" against a wall
of water you can see coming from the top of the cathedral.

## The world

**Vessel** was a port that believed it would outlast the sea. It built a sea wall, then
a higher one, then a cathedral on the highest ground. The water came in under the wall,
not over it. What is left is a city in a bowl: eight districts, each with a landmark
that survived and a hundred rooms that did not.

**The Cradle** is home. It began as a ferry and a crane lashed together; players have
added the things a harbour needs. A lamp room, a drydock, a kitchen, a clinic, a radio
room, a school. Every building is a tiered upgrade with a visible effect on the
harbour: the lamp room lights the whole Cradle at night; the drydock lets a boat be
repaired between tides; the kitchen makes the survivors stay.

**The Aunt** is the lighthouse on the point, older than the city, still turning. Its
lamp is the only thing that keeps **the Undertow** from coming up the channel. Keeping
it lit is a shared job: oil, wick, winding, glass. If the lamp goes out during a tide,
something comes in with the water, and the next dive is different.

**The drowned** are not zombies. They are the city's grief with mud on it: figures
that assemble out of silt and drift toward noise, carrying the object they died for.
They can be avoided, distracted, or (rarely) put to rest by returning the object to
the Cradle's **Ledger**, a wall of names recovered one at a time. The game is not
about killing them. It is about what you carry and what you leave.

## The loop

**Harbour (10–25 minutes).** Read the tide table. Take a contract from the board:
salvage quota, a rescue, a survey. Spend **salt**. Repair a lamp, reinforce a hull,
teach a survivor a trade. Talk. The Cradle is the only place the game is safe, and it
is the place the game is about.

**Dive (20 minutes).** Row or motor out. Choose a district. The water is at your knees,
then your waist; the streets are canyons of mud and furniture. Explore, cut, carry,
rescue. The dive is a single shared world: players can split up, and the game will let
them, but the best stories happen when they do not.

**The tide.** At T-4 the horizon changes. At T-2 the water is at your chest. At T-0 it
is a wall moving faster than you can run in mud. You can reach high ground, a boat, a
tower, or a rope left by a friend. Anything you are carrying when the water takes you
is lost; you wake on the Cradle with a scar and a story. No gear is lost, no character
is deleted. **The punishment is the story, not the grind.**

**Debrief.** Sell, donate, unlock, argue. The Cradle's stores fill; the Ledger grows;
the next tide is in ninety-eight minutes.

**Season (6 weeks).** Three districts open across a season, a king tide every third
week, a narrative chapter told through found objects and the radio, a leviathan hunt
that needs the whole shard, and a cosmetic pier. At the end the sea takes one district
back and gives another. The map remembers.

## Depth

Three resources, always in tension:

* **Light.** The lamp is oil, wick and glass. It reveals salvage, inscriptions and
  safe paths; it also tells everything where you are. Douse it and you can hide, but
  the dark is not empty. A wader's lamp is the most personal thing they own.
* **Noise.** Cutting, running, fighting, dropping a crate. Noise travels through
  water and mud; the drowned follow it. You can make noise deliberately, to pull
  something away from a friend.
* **Weight.** Every salvage item has a weight. Loaded, you are slower, louder, and you
  cannot climb. The best item in the room is often the thing you have to leave.

Around that:

* **Roles**, not classes. **Lantern** (light, marks, reveals), **Cutter** (opens,
  breaches, fights), **Winch** (carries, lifts, anchors), **Medic** (revives, treats,
  reads the drowned). Each has three tools and a shared pool of perks; any team can
  take any mix.
* **Salvage** with provenance. 120 items at 1.0, each with a use and many with a
  story: a wedding ring is worth more to a survivor than to the market; a ship's bell
  opens a room in the cathedral.
* **The Cradle** as a shared project. 12 buildings, three tiers each, paid for by
  everyone and useful to everyone. A shard's Cradle is its biography.
* **Survivors.** 20 at 1.0, each with a request, a skill and a reason to stay or go.
  They are not a gacha; they are the harbour's memory.
* **Weather.** Fog, rain, a red tide, a storm surge. The tide table tells you what is
  coming; the dive tells you what it means.
* **Wreckers** (optional). A crew can fly a wrecker flag and take salvage from other
  players. No gear loss, no spawn camping; a social risk, not a second game.

## Content and length

| | At 1.0 |
| --- | --- |
| Districts | 8, each with 2–4 landmarks and 20–30 hand-built interiors |
| Salvage | 120 items, 30 blueprints, 12 relics |
| Creatures | 12, plus the leviathan (server event) |
| Survivors | 20 with personal arcs |
| Cradle | 12 buildings × 3 tiers |
| Narrative | 40,000 words, 5 seasonal chapters |
| Play | 60+ hours for a wader; a season is 20–30 hours |
| Modes | co-op 1–8 (4 ideal), solo with NPC crew, optional wreckers |

## Multiplayer and the BEAM

Two kinds of world, deliberately:

* **The Cradle** — one persistent `Cauldron.World` per shard, ticking slowly (or on
  input), holding residents, stores, the lamp, the tide clock and the board. It
  outlives every dive and every player.
* **A dive** — one `Cauldron.World` per expedition, 30 Hz, 1–8 players, 20 minutes,
  then it is gone and only its results and its replay remain.

`Cauldron.Worlds` starts dives on demand and the sweeper stops the ones nobody is in.
`Cauldron.Distribution` spreads Cradles across nodes; `Cauldron.Beacon` finds a nearby
node on a LAN; `Cauldron.Net` and `cauldron_2d_net` serve the browser; `Cauldron.Chat`
gives proximity and party chat; `Cauldron.Robot` can fill an NPC crew or a missing
role.

**The ssh front end is the identity.** `ssh play@lowtide.game` gives an account, a
character, sound through a tunneled port, and the game. No download, no launcher, no
store. A four-player dive can start from four terminals in four cities in under a
minute. `Cauldron2D.Drafter.Server` already serves accounts, sound and a beacon; this
game is the reason to polish it into a product.

**Persistence.** `Cauldron.Save` keeps a state under a slot on the local disk; it is
a save file, not a shard store. A shard needs a shared world store: Cradle state,
ledger, survivors, season clock. Put it behind an Ecto/Postgres service
with a write-behind journal; the world stays pure and replayable. This is the single
largest server-side build.

**Live-ops.** Hot code reload for balance and events; a GM console that can call a
king tide, spawn the leviathan, or open a district; a public tide table page that
shows every shard's next low tide. A season is data, not a deploy.

**Scale targets.** 200 Cradles per node, 8 players each, 5,000 concurrent players
across 20 nodes; dive tick under 8 ms p95 with 8 players, 40 creatures and 200
interactables; world save every 30 seconds and on leave; a crash loses at most one
dive, never a Cradle.

## Look

Painterly 16-bit at 320×200 logical resolution, 48 colours, isometric at eight
facings. Deep teal and slate for the water and the sky; bone, sodium amber and rust
for everything people made; a single red that only appears when the tide turns. Rain,
fog and lamplight do most of the work. The camera is close enough that a character is
40 pixels tall and a building fills the screen; the harbour is a wide establishing
shot with parallax.

The terminal shows the same frame at three times scale through kitty, iTerm2 or sixel;
the browser draws the scene data at 2×; the window and tablet at 4×. The HUD is
diegetic: a tide clock that is a real clock, a lamp gauge, a rope-and-paper map.

## Sound

Four layers, switched on bar lines: **harbour** (accordion, brushed drums, a warm
bass), **dive** (low strings, prepared piano, water), **threat** (a single sustained
tone and a pulse that gets faster), **leviathan** (choir and sub-bass). Diegetic
foghorn, bell, pump, creak, rain on a hundred surfaces. Spatial events are placed in
the world through `Cauldron.Audio`'s listener; a friend's lamp is audible before they
are visible. ACE-Step writes the themes; `extract_stem` and `cover_music` give the
season its variants.

## How it is made

* **`assets.exs`** drives the whole 2D art set through the Studio: district tilesets,
  24×40 characters, creatures, props, portraits, UI. Every asset is finished by
  `Linocut.Pixelate` to one palette per district. A cast LoRA for the recurring waders
  keeps the characters themselves; a shared style prompt and the district palettes keep
  the eight districts in one hand. A per-game style LoRA is the planned upgrade
  (`GAMES_OVERHAUL.md` B).
* **Animation from video** (`Wan VACE` through the same manifest) for creatures,
  water and the leviathan; short loops, background removed per frame, finished on one
  grid. Characters are mostly 8-frame loops and can be edited from one pose.
* **Parallax** from painted layers; seamless tiling is the known gap, so the game
  mirrors and blends for now.
* **Blender** for the Cradle's boats and the big props, rendered as isometric
  turnarounds and finished as pixel art; it is cheaper to model a boat once than to
  paint eight facings.
* **ACE-Step** for the score, `make_sfx`/Stable Audio for the foley, then
  `Cauldron.Audio.Music` for the layers.
* **The engine**: `cauldron_2d` isometric, `Cauldron2D.Parallax`,
  `Cauldron2D.Projection.Volume` for lamplight, `Cauldron2D.Grid.FOV` for what the
  lamp reveals, `Cauldron2D.Route` for the drowned, `Cauldron2D.Particles.Emitter` for
  rain and mud, `Cauldron2D.Screen`/`Menu` for the Cradle UI.

## On Cauldron

| Need | Module |
| --- | --- |
| Many worlds, on demand, swept | `Cauldron.Worlds`, `Cauldron.Worlds.Sweeper` |
| Cluster, handoff, presence | `Cauldron.Distribution`, `Cauldron.World.Presence` |
| ssh accounts and sound | `Cauldron2D.Drafter.Server` |
| Browser | `cauldron_2d_net`, `Cauldron.Net` |
| Chat and party | `Cauldron.Chat`, `Cauldron.Client.Party` |
| Bots / NPC crew | `Cauldron.Robot` |
| Deterministic replay of a dive | `Cauldron.Replay` |
| Music layers, spatial sound | `Cauldron.Audio`, `Cauldron.Audio.Music` |
| Saves | `Cauldron.Save` + a shared world store |
| Lamplight | `Cauldron2D.Projection.Volume` + lighting |

## What the engine does not have yet

1. **Lighting.** The heart of the game. `Volume` already tints what is seen through a
   shape, at under 1 ms for the built-in shapes; what is missing is a light that
   changes what a surface *is*, not just what colour it is seen through. Build the
   baked per-cell light first (cheap, static), then the live lamp (NIF, per pixel).
   Budget 5–6 weeks, and it pays for every later Cauldron game.
2. **Dialogue.** Survivors, the radio, the drowned. Build the graph walker from
   `ENGINE_ADDITIONS.md` §6 with game-defined conditions and effects. 3 weeks.
3. **Shared world persistence.** A durable Cradle store with a journal and a snapshot;
   per-player saves are not enough. 4 weeks.
4. **Eight-player smoothing.** Interpolation, interest management, and a join-in-
   progress handshake for a 30 Hz dive. 2–3 weeks.
5. **Tide and water.** A game-side water volume with a rising height, currents and a
   wall-of-water event; the projections can draw it, but it needs its own renderer and
   collision. 4 weeks.
6. **Live-ops tools.** GM console, season data, tide-table page, replay inspection.
   6 weeks.

## The vertical slice (12 weeks)

**One Cradle, one district, four players, one tide.**

* The Cradle: lamp room, board, stores, three survivors, the tide clock.
* Saltmarket: 12 interiors, mud streets, a flooded cellar, a bell tower with a view of
  the coming water.
* Four players over ssh and browser, drop-in, 20-minute tide, extraction.
* Eight salvage types, three creatures, lamp oil and noise, one rescue arc.
* One four-layer music cue and a full foley pass for water and mud.

Out of scope: seasons, the leviathan, the other seven districts, wreckers.

**Team:** 1 designer, 3 engineers, 2 artists, 1 audio, 1 producer/QA (8).
**Exit test:** twenty four-player sessions; 60–70% extraction; every group can tell a
story about a tide; the Cradle is still standing the next day.

## 1.0

Eighteen months, twelve people. Eight districts, 120 items, 20 survivors, 12
creatures, four seasons written, a public tide table, a GM toolkit, localisation into
six languages, accessibility (high-contrast lamp mode, no-flash tide, readable fonts,
full remapping), and a Cradle that a shard can keep for years.

## Risks

| Risk | Mitigation | Kill criterion |
| --- | --- | --- |
| Live-ops is a second product | one shard type, one season engine, one GM console; hire for it | a season cannot be run by one person in a week |
| Lighting costs too much | bake first; live lamp only in a small radius; volumes elsewhere | lamp over 8 ms/frame at 320×200 |
| Content treadmill | procedural interiors from hand-built rooms; district kits; seasonal reuse | district #3 costs more than 6 weeks |
| 8-player net is mushy | 4 is the design target; 8 is a stretch; authoritative world | 8-player dive tick over 12 ms p95 |
| The tide is annoying, not tense | tune the clock with playtests; always a visible escape; no gear loss | players ignore the tide table |
| ssh onboarding scares people | browser client is equal; ssh is the delight, not the requirement | under 30% of browser players try ssh |

## Why it wins

It is the only one of the three where the BEAM is the game's selling point rather than
its plumbing: a persistent harbour, a tide that everyone shares, a city that remembers
what was recovered, and an ssh address you can give a friend. It is also the most
Cauldron-native game on the list — isometric pixels, spatial sound, many small worlds,
a shard that lives for years. If the studio wants a game with a long tail and a
community, this is the one.

---

# 03 — GREENWARE

![Greenware key art](pitches/art/greenware.png)

> *A stop-motion adventure about putting things back together.*

**Working title.** Single-player 2D stop-motion clay adventure. Tactile puzzles.
10–12 hours, five acts, three endings. Desktop, browser, tablet, terminal.

*Anchors: The Neverhood and Armikrog for clay, Unravel for handmade warmth, a good
point-and-click for pacing. The difference: you mend the world instead of clicking it.*

## The pitch

**Greenware** is the potter's word for clay that has been shaped but not fired: soft,
fragile, full of possibility. It is also the name of the figure you play: a small,
faceless puppet who wakes on a workbench in a world made of clay, with a brass key in
its chest and no memory of who made it.

The world is called **the Bake**. It is a handmade place: hills of pressed clay,
cardboard skies, a garden that grows in stop-motion, a fairground of broken toys. On
the horizon is **the Kiln**, cold for the first time anyone can remember. The world is
drying out. Things are cracking. The Mender, who used to fix them, is gone.

You can fix things. You have hands.

**The hook: everything is soft.** You do not find a key; you shape one. You do not
find a bridge; you build one out of clay and wire and hope it holds. You do not solve
a character; you give them a face, and then live with the face you gave them. The
game's verb is not *use* or *shoot*. It is **mend** — and the world remembers every
mend you make.

## The world

The Bake is a tabletop world, and the game never lets you forget it: a thumbprint in
a wall, a seam where two hills meet, a hair caught in the varnish, the edge of the
set visible when the camera moves. It is not a metaphor. It is a place someone made,
and the someone is missing.

Five regions:

1. **The Workshop** — the hub. A warm room, a workbench, a wall of tools, the Cat.
   The Mender's letters are here, one per act.
2. **The Garden** — a green place growing too fast. A gardener made of seedlings, a
   bird with one wing, a well that is also a mouth. Water is the enemy and the cure.
3. **The Cellar** — damp, dark, full of things put away and forgotten. The Cracked
   Choir, a chorus of broken plates that can only sing when mended. The first fired
   thing, and the first thing that cannot be changed.
4. **The Fair** — a carnival of broken toys, a ferris wheel that needs a hub, a hall
   of mirrors that shows you the face you have not got. The Boy, who is either a child
   or a very good drawing of one.
5. **The Kiln Road** — ash, heat, the Potter's house, the truth about the Mender and
   about you. The last choice.

The cast is 25 puppets: the Cat (a real, stop-motion cat, and the best character in
the game), the Green Man, the Boy, the Choir, the Potter (heard, not seen), and a
dozen small characters whose problems are the puzzles. Almost none of them are
villains. The antagonist is drying out.

## The loop

A scene is a diorama. You walk left and right, pick things up, talk, and look. When
something is broken, the camera moves in, the world desaturates slightly, and the
**mending view** opens: a close-up of the broken thing, a tray of tools, and your
hands.

You work the clay directly. Push with a thumb. Carve with a pin. Add wire for
strength. Wet it to make it stick; heat it to make it hold; smooth it; colour it;
press a pattern into it. The clay has a state — wet, leather-hard, fired — and it
changes as you work. A timer is always running: the clay is drying.

When you are done, the game does not say "correct". It tests the thing against the
world: does it span the gap? Does it hold water? Does it fit the socket? Does it
stand? Does it ring? Does the Cat sit on it? The mend either works or it does not,
and either way it is now part of the world. You can come back and mend it again.

**A scene** is 5–15 minutes: explore, find the break, understand what the thing is
for, mend it, live with the result. **An act** is 8 scenes and a set-piece: a flood,
a fire, a fall, a song. **The game** is 10–12 hours, and the last hour is a
conversation with the person who made you.

## The mend system

This is the game. It needs to be good enough to carry 60 puzzles, so it is worth
describing precisely.

**The clay body.** Every mendable object is a small 2D height field — 64×64 or 96×96
cells at 8 bits — plus a material state and a set of marked regions (a socket, a
crack, a lip, a hole). The height field is the visible surface; the regions are what
the world tests.

**The tools.** Eight, each a different verb on the field:

| Tool | Verb | What it is for |
| --- | --- | --- |
| Thumb | push / pull | move clay, make a bulge, close a crack |
| Pin | carve | make a hole, a groove, a notch, a mouth |
| Wire | armature | add strength across a span; visible if the clay is thin |
| Paddle | flatten | make a surface, a plate, a wing |
| Sponge | smooth | remove tool marks; make a thing feel finished |
| Water | wet | soften, make sticky, slow drying |
| Heat | harden | leather-hard to fired; strong but brittle |
| Pigment | colour | mix a colour; some colours do something |

**The materials.** Wet clay bends and sticks but will not hold a shape. Leather-hard
holds a shape and can be carved. Fired is strong, rings, and cannot be changed; it
also cannot be glued to anything wet. Wire makes a thin thing stronger; a fired thing
is brittle where it is thin. Colour is a material too: red clay warms, white hardens,
black conducts the hum, blue cools (and slows drying).

**The predicates.** The game checks the world, not the player:

* `spans?(field, gap)` — a bridge.
* `holds?(field, water)` — a dam, a cup, a gutter.
* `fits?(field, socket)` — a key, a peg, a joint.
* `stands?(field, weight)` — a leg, a table, a tower.
* `rings?(field, note)` — the Choir; a cracked plate tuned by filling the crack.
* `has_face?(field)` — the Boy; the face you give changes his dialogue and the ending.
* `conducts?(field)` — the hum; a wire and black clay.
* `cat_approves?(field)` — the Cat sits on it. This is a real predicate. It is also
  the tutorial for "the world tests the thing, not you".

**The pressure.** Clay dries while you work. The timer is visible as the surface
going from glossy to matte. You can re-wet, but water softens what you have already
built. The best mends are made in the first two minutes. There is no fail state: a
bad mend is a bad object in the world, and you can try again — but the scene has
moved on, and someone saw.

**Why it is not a physics toy.** Free-form sculpting is delightful for ten minutes
and unshippable for ten hours. The height field is small, the tools are discrete, and
the predicates are authored per puzzle. The player has real agency inside a designed
space, the way a good lockpick minigame does. The authoring cost is a puzzle spec,
not a simulation.

## Content and length

| | At 1.0 |
| --- | --- |
| Acts | 5 |
| Scenes | 40 hand-built dioramas |
| Puzzles | 60 mends, 15 of them optional |
| Puppets | 25, with 8–14 animations each |
| Sets | 40, with 3–5 parallax layers each |
| Words | 25,000, plus the Mender's letters (voiced) |
| Endings | 3, plus a New Game+ that keeps your mends |
| Play | 10–12 hours; 15 with the optional mends and the Mending Room |
| Extras | art book, commentary, the Mending Room (a shared daily mend), photo mode |

**The Mending Room** is the long tail: a daily broken object, generated from a kit,
with no story attached. Mend it, photograph it, send a postcard. No leaderboard, no
score; a quiet reason to come back. It is also the game's demo — and, because every
mend is a replay, a quiet kind of multiplayer: the same object for everyone, and a
handful of other people's mends to watch as ghost hands.

## Single-player, and the BEAM anyway

This is a single-player game. It does not need a cluster, and pretending otherwise
would be dishonest. What it does need is a world that is pure and testable, because a
puzzle game lives or dies on regression: every mend must still work after every
change.

* **The world is pure.** A scene is a value; a mend is an event; a save is a snapshot
  plus the mends. `Cauldron.Test` drives a scene with no clock and no window, which is
  how 60 puzzles are regression-tested on every commit.
* **`Cauldron.Replay`** records a playthrough for QA and for the speedrun mode. A
  tester's bug report is a replay, not a description.
* **The Mending Room is asynchronous multiplayer without a lobby.** One broken object a
  day, the same seed for everyone; each mend is a replay; a handful of other players'
  mends are shown as ghost hands. `Cauldron.Replay` and a small Phoenix service; no
  chat, no scores, no pressure.
* **One client module** runs the game in the window, the browser, the iPad and the
  terminal. The terminal is a real target: the mending view works with a mouse,
  `Cauldron2D.Drafter` already routes pointer coordinates into a `:picture` scene, and
  a 480×270 clay cut is legible on a good terminal.
* **`Cauldron.Save` and `Cauldron.Scores`** keep the local records; the Phoenix service
  only shares a mend or a postcard, never the player's save.
* **`Cauldron.Audio`** for the foley; the music is authored, not adaptive.

The BEAM is not the selling point here. The asset pipeline and the look are.

## Look

Stop-motion, 12 frames a second, photographed like a miniature: shallow depth of
field, practical lights, a slightly warm grade, dust and fingerprints. Colours are
earthy and saturated: terracotta, ochre, moss, bone, a carnival red that only the Fair
uses, and ash grey for the last act. Every set is a physical object; every character
is a puppet with a visible seam and a replaceable face. The camera is locked to the
diorama, with slow push-ins and the occasional rack focus.

**The boil.** Every frame is jittered by a pixel or two, the exposure flickers, a hair
moves. This is not noise for its own sake: it is the signature of stop motion, and it
is also what hides the small inconsistencies of a hand-made production. A clean digital
render of a clay puppet looks like a toy; a boiled one looks alive.

In the terminal, the same scene is shown at 480×270, 12 fps, with the mending view at
full pane resolution; the pixels are the point.

## Sound

Foley first. The sound of a thumb pressing clay, a pin scratching, a wire clicking, a
plate ringing, a kiln breathing. The score is handmade too: music box, thumb piano,
bowed saw, detuned upright piano, a clay ocarina, and a small choir for the Choir.
The main theme is a 5/4 lullaby that changes instrumentation in every act. The
Mender's letters are read by a warm, tired voice; the Cat is a real cat.

## How it is made — and why the clay is not AI video

This is the part that makes the extra credit real.

**Blender is the stage.** The 25 puppets and 40 sets are modelled and rigged in
Blender at 1:12 scale, with plasticine shaders (subsurface scattering, procedural
fingerprints, bump, dust), replaceable faces and hands, visible armatures, and
practical set lights. Animation is keyed on twos at 12 fps — the way stop motion is
actually shot. Each scene is rendered as 3–5 alpha layers (background, mid, character,
foreground, effects) at 2K, then composited, graded and boiled. A 4-second loop is 48
frames; 25 puppets × 12 loops × 48 frames is about 14,000 frames, and a single machine
renders that in days, not months. The look is consistent because the puppets are real
objects.

**The Studio is the art department.** It makes the concept art (`clay` style), the
turnarounds that the modeller works from, the texture sheets (pressed linen, wood,
paper, paint), the storyboards, the UI, the key art and the marketing. It writes the
music (ACE-Step) and the sound effects (`make_sfx`), and it voices the letters. It is
also the fastest way to explore a set before anyone builds it.

**Why not generate the frames?** Because a 12-hour game needs 14,000 frames that are
the same puppet from the same angle with the same fingerprints, and video models are
not yet reliable at that over a whole production. They are excellent for **previs**:
a 5-second test of a scene's timing, a mood clip for the pitch, a storyboard in
motion. They are not the final camera. This is not a limitation we are working around;
it is the correct division of labour, and it is why the claymation look can be
sustained for a whole game.

**The frame budget.** 40 scenes × 20 assets = 800 renders, plus about 14,000 animation
frames at 2K. Four alpha layers at 4–8 seconds a frame is roughly 100 hours of machine
time for a full pass — about a week with retries, and less with a second machine. The
whole game's footage is weeks, not years. The expensive part is the animation and the set dressing, which is
where the artists should be.

## On Cauldron

| Need | Module |
| --- | --- |
| Scenes, layers, parallax | `cauldron_2d`, `Cauldron2D.Parallax` |
| Sprite strips, frames, atlas | `Cauldron2D.Atlas`, `Cauldron2D.Picture`, `Linocut` |
| The mending view | a game `:picture` scene, `Cauldron2D.Raster`, a height-field module |
| UI, menus, title | `Cauldron.Front`, `Cauldron.Menu`, `Cauldron2D.Screen` |
| Dialogue and letters | `Cauldron.Dialogue` (to build) |
| Save, undo, replay | `Cauldron.Save`, `Cauldron.Replay`, `Cauldron.Test` |
| Sound and music | `Cauldron.Audio`, `Cauldron.Audio.Music` |
| Window, browser, iPad, terminal | `cauldron_2d_wx`, `cauldron_2d_net`, `cauldron_native`, `cauldron_2d_drafter` |
| Asset generation | `cauldron_2d_assets`, the Studio MCP |

## What the engine does not have yet

1. **A clay canvas.** A small deformable height field with tools, undo, drying and
   predicates. Game-side, but it needs a fast raster path; prototype in Elixir at
   96×96 and move the inner loop to a NIF only if it misses 60 fps. 3–4 weeks.
2. **Pointer-first UI.** The terminal already routes the pointer; the browser and
   window clients need a shared pointer cursor and drag model for the mending view.
   2 weeks.
3. **Dialogue.** `ENGINE_ADDITIONS.md` §6, again — a graph walker with game-defined
   conditions. 2–3 weeks.
4. **Saving deformations.** A height field is 9 KB per object; a scene with ten mends
   is 90 KB. Compress (RLE) and store the deltas, not the field. 1 week.
5. **Accessibility for a dexterity game.** A "guided mend" mode that offers three
   valid strokes, full remapping, no timers, and a colour-blind palette. 2 weeks.
6. **A Blender-to-Cauldron pipeline.** A small exporter for layer stacks, frame
   strips, pivots and scene metadata; a manifest the atlas loader reads. 2 weeks.

## The vertical slice (10 weeks)

**The Workshop and the Garden, six scenes, one puppet, three mends.**

* Greenware and the Cat, animated at 12 fps in Blender, in three sets.
* The mending view with thumb, pin, wire, water and heat; three predicates: span,
  hold water, cat approves.
* The first Mender letter, voiced; one 5-minute music cue; a full foley pass.
* Window and browser builds; a terminal cut of one scene.

Out of scope: the Cellar, the Fair, the Kiln Road, the endings, the Mending Room.

**Team:** 1 designer, 2 engineers, 2 artists/animators, 1 Blender TD, 1 audio, 1
writer, 1 producer/QA (9).
**Exit test:** ten strangers play the slice; eight make a mend they did not expect to
work; six ask what happens to the Cat; the clay canvas is fun with a mouse and with a
keyboard.

## 1.0

Fifteen months, ten people. Five acts, 40 scenes, 25 puppets, 60 mends, three endings,
25,000 words, a 45-minute score, localisation into six languages, an art book, and a
Mending Room that can run for years, with a shared daily mend and ghost hands.

## Risks

| Risk | Mitigation | Kill criterion |
| --- | --- | --- |
| Free-form clay is not fun | constraints, predicates, authored puzzles; prototype in week 2 | the canvas is not fun after three iterations |
| 60 puzzles is a lot of design | a puzzle grammar (span, hold, fit, stand, ring, face) and a kit of parts | puzzle #10 takes more than a week |
| Blender throughput | layered renders, 2K not 4K, twos at 12 fps, a second machine | a scene takes more than 5 days |
| The tone is twee | the Cat, the Choir, the fired things, the ending; let the world be sharp | playtesters call it "cute" and nothing else |
| Accessibility | guided mend, no timer, remapping, high contrast | a player who cannot draw cannot finish act 1 |
| Cost of 25 puppets | 12 at launch, 13 in the back half; reuse parts and faces | puppet #10 costs more than 2 weeks |

## Why it wins

It is the only one of the three that could be a poster. The claymation look is
immediately legible, instantly different from every other game on a shelf, and it is
made by a pipeline that is already in the building: Blender, a GPU, and a Studio that
can concept, texture, score and sound it. The mechanic is the look — you mend clay —
and the story is the mechanic: a world that is drying out, and a creature made to fix
things who has to decide what is worth keeping. It is the smallest of the three and
the one most likely to be remembered.

---

# Why these three

They are three different answers to the same question: **what is the BEAM for?**

| | The BEAM is… | The game that proves it |
| --- | --- | --- |
| **HEAVY WEATHER** | a way to run thousands of isolated, deterministic worlds with low latency and one client for every screen | a fighting game you can play in a terminal and a window, with rollback and replays |
| **LOWTIDE** | a way to keep a world alive for years, across machines, while people are in it, and to change it without stopping | a harbour that outlives every dive, on a shard you can ssh into |
| **GREENWARE** | a way to keep a pure world testable and portable while the content is handmade | a puzzle game whose 60 mends are regression-tested on every commit, on four screens |

That is the test we applied to every idea we rejected.

## What we are not pitching

* **An open-world RPG.** The content cost is a studio, not a game. Cauldron's maps are
  excellent; its dialogue and cinematics are not there yet; and nothing in the pitch
  would use the BEAM for anything but hosting.
* **An MMO.** The interesting part (thousands of players in one world) is the part that
  fights the engine's world model and the team's live-ops capacity. LOWTIDE gets the
  social persistence without the single-shard tyranny.
* **A battle royale or a live-service shooter.** The netcode and anti-cheat cost would
  eat the art budget, and the market is not asking for another one.
* **A 3D tech demo.** The 3D showcase already exists. A pitch has to have a verb.
* **A roguelike deckbuilder.** It would be cheap and good, but it would use none of the
  things that make this stack unusual.

The common thread in the three we kept: a strong verb, a visible clock, and a reason
to come back tomorrow. **Mend. Salvage. Refit.** Each is one word a player can say
before they understand the rules.

## If you can only build one

| | HEAVY WEATHER | LOWTIDE | GREENWARE |
| --- | --- | --- | --- |
| Clarity of the verb | 4 | 4 | 5 |
| Depth and replay | 5 | 5 | 3 |
| Fit with the engine | 4 | 5 | 3 |
| Fit with the BEAM | 3 | 5 | 2 |
| Distinctiveness of the look | 3 | 4 | 5 |
| Production risk (5 = low) | 2 | 2 | 4 |
| Reach beyond the terminal | 3 | 3 | 4 |
| Cost efficiency | 2 | 2 | 4 |

**Recommended order.**

1. **GREENWARE first.** It is the smallest, the most distinctive, and the only one
   whose art has already been tested in this document. Ten people, fifteen months, a
   look nobody else has, and a mechanic that is the look. It establishes what a
   Cauldron game *looks* like. Ship it, then use it as the studio's calling card.
2. **LOWTIDE in pre-production from month six.** It is the long-lived game, and the one
   where the BEAM is the selling point. It needs the lighting work and the live-ops
   discipline, so it should not be the first thing the studio runs. Start the paper
   prototype now; greenlight after GREENWARE's slice.
3. **HEAVY WEATHER as a six-week spike, not a greenlight.** Build the fixed-point
   world, the rollback over a simulated 120 ms link, and the GPU→terminal path. If all
   three pass, it is the highest-ceiling game on the list and the best esports story.
   If the determinism does not hold, stop; do not spend a year finding out.

If the goal is a long-lived service rather than a portfolio, swap 1 and 2: LOWTIDE is
the better business, GREENWARE is the better statement.

## The asset factory

The pipeline that made the art in this document is the same one the games will use.
It has three doors:

**1. The Studio, for 2D.** A game writes an `assets.exs` (`Cauldron2D.Assets.Manifest`)
with a project, a model, a shared style, a background, a palette and one prompt per
asset. `mix cauldron.assets` queues the work through the Studio's MCP server, waits,
finishes every candidate with `Linocut.Pixelate` (background keyed out, pixel grid
found, palette, dither, outline, fit), and writes a sheet. A human picks; the choice
is locked in `assets.lock.exs`; the build is reproducible forever.

**2. The Studio, for motion and 3D.** The same manifest can ask for an animation from
video (`Wan VACE`: a chosen picture set moving, background removed per frame, frames
kept as one strip) or an animation of a rigged character (`make_rig` + `make_motion` +
`make_animation`), or a 3D model (`make_3d` with TRELLIS.2 or whichever the Studio lists), or a
turntable of it rendered by the GPU. This is how a ship, a turret or a creature gets
eight facings without eight paintings.

**3. Blender, for the things that must be consistent.** Hard-surface rigs for HEAVY
WEATHER; clay puppets and sets for GREENWARE; boats and big props for LOWTIDE. Blender
is also the renderer for GREENWARE's 12 fps footage and for the turnarounds that feed
the pixel pipeline.

The Studio's tools, and what each is for:

| Tool | Use |
| --- | --- |
| `generate_image`, `edit_image`, `vary_image` | concept, key art, textures, decals, UI, storyboards; `from:` keeps a character themselves across poses |
| `make_video` (Wan VACE) | creature loops, water, weather, previs, cutscene tests |
| `make_3d`, `make_rig`, `make_motion`, `make_animation` | props, ships, turrets, clay maquettes, puppets, turntables |
| `compose_music`, `cover_music`, `extend_music`, `extract_stem` | themes, seasonal variants, stems for adaptive layers |
| `make_sfx` | weapon, servo, water, clay, foley libraries |
| `create_cast_member`, `train_cast_lora` | a character or a place that stays itself across a hundred pictures |
| `create_storyboard`, `make_keyframe`, `make_clip`, `assemble_film` | campaign cinematics, trailers, the pitch film |
| `get_result`, `wait_for_jobs`, `search_library` | look at what came back; keep the good takes; never trust a prompt without looking |

Two rules learned from making the art here:

* **One style, one seed family, one model per asset family.** The clay key art is
  `flux2_klein_4b` with the `clay` style at seed 43003; changing the model between
  shots is how a set stops looking like a set.
* **Look at every result before it enters a manifest.** The first two key-art jobs in
  this session were stopped by the Studio's memory guard; they were retried smaller
  and one at a time. That is normal. A pipeline that cannot survive a failed job is
  not a pipeline.

### Licences

`flux2_klein_4b` is marked commercial-use-allowed by the Studio. `flux2_klein_9b`,
`flux_dev`, `qwen_image`, `sd35_*` and the audio/3D models carry their own terms; the
Studio reports each model's `commercial` field, and the `studio-licensing` skill is the
checklist. The rule for production: **no asset ships without its model, seed, prompt
and licence recorded in the manifest.** The appendix does that for this document.

## The production machine

**Vertical slice, then content.** Every pitch is scoped as a slice that can be played
by strangers before a full team is hired. The slice is the greenlight; the full game
is a content schedule, not a second prototype.

**The world is the test.** Because a Cauldron world is pure, every mechanic has a
headless test: `Cauldron.Test` joins players, holds inputs, ticks the world and reads
views and events. A bug report can be a replay. A balance change can be a test. A
speedrun can be a regression suite. This is the quiet advantage of the stack, and it
should be used from week one.

**Bots are QA.** `Cauldron.Robot` fills lobbies, soaks servers, and plays the campaign
at five skill levels. A four-player LOWTIDE dive with two bots is a test that runs
every night. A HEAVY WEATHER match with a bot is a frame-data test.

**Live code is a feature.** A season in LOWTIDE should be data and a hot load, not a
deploy. A balance patch in HEAVY WEATHER should not stop a tournament. The BEAM makes
that ordinary; the production plan should make it a habit.

**The content pipeline is an editor, not a spreadsheet.** The easel (terminal and
browser), the sector map editor, `mix cauldron.sfx`, the Livebook atlas editor and
`assets.exs` are the tools the team will actually use. Budget time to make them good;
they pay back on every asset.

**Accessibility and localisation are schedule items, not polish.** Remapping, subtitles
for the radio and the letters, a no-flash tide, a guided mend, colour-blind palettes,
and text that fits the panel. Six languages for the chosen game.

## The next thirty days

Whatever is chosen, the first month is the same shape:

1. **A look test.** One hero asset, one animated loop, one music cue, one UI screen, on
   the real target (terminal, window, browser). For GREENWARE: a Blender puppet, 48
   frames, boiled; for LOWTIDE: a district corner with a lamp and rain; for HEAVY
   WEATHER: one rig in one storm, captured to the terminal.
2. **A verb test.** The smallest playable version of the core verb: a mend, a dive, a
   refit. Two weeks, one programmer, one designer, grey boxes, a stopwatch.
3. **A tech spike** on the risk that would kill it: fixed-point rollback (HEAVY
   WEATHER), lighting at 320×200 (LOWTIDE), the clay canvas (GREENWARE).
4. **A licence and pipeline check** for every model the look depends on.
5. **A playtest with ten strangers**, and a decision: greenlight, iterate, or stop.

## Appendix — the art in this document

All images were made during this session through the NxDiffusion Studio MCP server,
project **cauldron-pitches**, model **flux2_klein_4b** (4 steps, commercial use
allowed), and are concept art, not in-game captures.

| File | Prompt summary | Style | Seed | Size |
| --- | --- | --- | --- | --- |
| `heavy-weather.png` | a colossal rusted walking war machine in a storm sea; a second mech in the distance | none | 41001 | 896×512, cropped |
| `lowtide.png` | an isometric drowned city at low tide, lantern-carrying salvagers on a boardwalk | none | 42002 | 896×512, cropped |
| `greenware.png` | a faceless clay mender repairing a cracked miniature house | `clay` | 43003 | 1024×576 |
| `greenware-workshop.png` | the same scene, a wider take | `clay` | 43003 | 1024×576 |

A second take of the same prompt, seed and style — the same puppet, the same
fingerprints, a different composition. This is the kind of variation a set can be
chosen from:

![A second take of the Greenware key art](pitches/art/greenware-workshop.png){width=66%}

The first pass at 1024×576 with two candidates each was stopped twice by the Studio's
memory guard (the machine was under memory pressure); the jobs were retried one at a
time at 896×512. The clay images, made when the queue was otherwise empty, came back
at the larger size. Recorded here because a pipeline that cannot survive a failed job
is not a pipeline.

Sound tests: [`greenware-theme.mp3`](pitches/audio/greenware-theme.mp3) (ACE-Step, 45 s,
92 bpm, A minor, seed 5101) and [`clay-press.mp3`](pitches/audio/clay-press.mp3)
(Stable Audio, 3 s, seed 6101). Mood tests, not final assets.

The clay images used the Studio's `clay` style (*"claymation scene of {prompt},
handmade plasticine figures, fingerprint texture, miniature set, stop motion"*). It is
a starting point; the production look is Blender, as GREENWARE describes.

