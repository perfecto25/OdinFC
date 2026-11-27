# OdinFC — Muay Thai Kickboxing Simulator: Design & Build Plan

**Model tags:** 🟢 **Sonnet 5.5** = routine coding that follows this plan · 🟣 **Opus 5.5** = architecture, systems that interact, tuning, and hard debugging.
Rule of thumb: if Sonnet loops on a bug twice, switch to Opus for that problem.

## Context
OdinFC is a **full-simulation** Muay Thai / kickboxing game, 1 human vs 1 CPU, in a 3D arena styled after ONE Championship broadcasts. It must run natively on Linux and use the GPU (dev machine: AMD Radeon iGPU, HawkPoint/780M class → Vulkan via Mesa RADV).

Decisions:
- **Visual style:** stylized 3D (semi-realistic, light enough for an iGPU)
- **Arena:** Muay Thai rope ring and circular cage, selectable (generic branding)
- **Gameplay:** full simulation (per-body-part damage, stamina, cuts, 3×3 min rounds, 10-point-must judges)
- **Camera:** broadcast side cam by default, toggle to over-the-shoulder
- **Assets:** free placeholder rigged humanoids + Mixamo fight animations first, swap later
- **Language:** GDScript

## Engine: Godot 4 (latest stable 4.x)
- Native Linux, open source (MIT), no royalties, small footprint.
- Forward+ renderer on Vulkan (uses the GPU), falls back to the Compatibility (OpenGL) renderer.
- AnimationTree, skeleton retargeting (for Mixamo), Area3D hitboxes, and SDL gamepad support (PlayStation pad via InputMap).
- Install: official Linux x86_64 binary → `~/.local/bin/godot` (or Flathub `org.godotengine.Godot`).

## Project structure
```
odinfc/
  project.godot
  assets/            # models (.glb), animations, textures, audio, fonts
  data/
    moves/           # MoveData .tres — one per technique
    fighters/        # FighterData .tres — roster entries (stats, model, move list, specials)
    arenas/
  scenes/
    main_menu.tscn, fight.tscn, arenas/ring.tscn, arenas/cage.tscn, fighter.tscn, hud.tscn
  scripts/
    core/      game_state.gd (autoload), fight_manager.gd, round_timer.gd, judges.gd
    fighter/   fighter.gd, state_machine.gd, states/*.gd, body_damage.gd, stamina.gd, hitbox.gd
    input/     player_controller.gd, ai_controller.gd (same interface → swap human/CPU)
    camera/    fight_camera.gd
    ui/        hud.gd, menus
  tests/       GUT unit tests (damage, scoring, stamina, state transitions)
```

## Core systems

### 1. Data-driven moves (`MoveData` Resource) — 🟣 Opus to design the schema, 🟢 Sonnet to author the move files
Fields: name, animation, startup/active/recovery frames, stamina cost, damage, target zone (head/body/legs), reach, hitbox bone, guard break, counter bonus, and whether it can be parried.
Moves: jab, cross, lead/rear hook, uppercut, teep, side kick, round kick (low/body/high), straight knee, clinch knee, clinch control/sweep, guard (high/low), parry, and check kick.
Specials (a future roster feature) are MoveData with an extra input sequence and a meter cost, so no new code is needed.

### 2. Fighter + state machine — 🟣 Opus
States: Idle/Stance, Move, Attack, Block, Parry, Check, HitStun, Stagger, Knockdown, Clinch (neutral/dominant/controlled), KO.
- Fixed 60 Hz `_physics_process` timing, with frame data taken from MoveData, so the game is deterministic and testable.
- Hitboxes are Area3D shapes on BoneAttachment3D (fists, shins, knees), active only during a move's active frames. Hurtboxes cover head, body, and legs.
- Fighters always face each other and move on a 2D plane, so circling is possible.

### 3. Simulation model — 🟣 Opus
- **Per-zone damage:** head → knockdown/KO chance. Body → slower stamina recovery. Legs → slower movement, weaker kicks, possible fall.
- **Stamina:** spent by strikes and blocking, recovers when idle. When low, strikes get slower and weaker and the guard gets heavier.
- **Cuts:** heavy head damage (and elbows later) can open a cut, and a doctor check can stop the fight.
- **Knockdowns:** 10-count, recovery based on remaining head health. Three knockdowns in a round = TKO.
- **Clinch:** positional contest (stamina + strength). The dominant fighter can throw knees or attempt sweeps.
- **Scoring:** 3 judges, 10-point-must, Muay Thai weighting (kicks/knees/sweeps/damage > volume), small per-judge variance. Results: KO/TKO/UD/SD/Draw.

### 4. CPU opponent (`ai_controller.gd`) — 🟣 Opus
Utility-based AI over the same input interface as the player. It considers distance, both fighters' stamina, per-zone damage, and what the opponent is doing. Difficulty sets reaction delay, accuracy, defense rate, and aggression. Style profiles (pressure, counter-striker, kicker, clinch fighter) come later from FighterData.

### 5. Camera (`fight_camera.gd`) — 🟢 Sonnet
- **Broadcast:** side-on, zooms to keep both fighters framed, slight handheld sway, auto-cuts at knockdowns and between rounds.
- **Over-the-shoulder:** behind the player's fighter.
- Toggled with Tab or the touchpad.

### 6. Arenas — 🟢 Sonnet
Ring: 4 ropes, corner pads, ropes as collision boundaries. Cage: circular fence. Shared canvas floor, crowd placeholders, broadcast lighting. Generic "OdinFC" branding (no real promotion or sponsor logos).

### 7. HUD — 🟢 Sonnet
Bottom broadcast bar: portraits, names, round and clock, round dots. Top: per-fighter health (zone indicators) and stamina bars. Between-round stats panel.

### 8. Controls (InputMap) — 🟢 Sonnet
| Action | Keyboard | PS pad (future) |
|---|---|---|
| Move/circle | WASD | L-stick |
| Jab / Cross | J / K | □ / △ |
| Lead / Rear hook | U / I | L1+□ / L1+△ |
| Uppercut | O | R1+△ |
| Teep / Side kick | L / ; | ✕ / ○ (+modifier) |
| Round kick (low/body/high via W/S) | H | R2 |
| Knee | N | L2+✕ |
| Guard (hold) / Parry (tap) | Space | R1 |
| Clinch | C | L1+R1 |
| Camera toggle | Tab | Touchpad |

Every action goes through named InputMap actions, so gamepad support only needs bindings plus a rebind menu.

## Milestones

| # | Milestone | Model | Why |
|---|---|---|---|
| 1 | **Setup:** install Godot, create the project, verify the Vulkan renderer, greybox ring + two capsule fighters | 🟢 Sonnet | Scaffolding work |
| 2 | **Combat core:** state machine, MoveData schema, hitboxes/hurtboxes, all basic strikes + guard/parry (greybox), GUT tests | 🟣 Opus | Sets the architecture every later milestone builds on |
| 3 | **Simulation layer:** zone damage, stamina, knockdowns/10-count, rounds/timer, judges and scoring | 🟣 Opus (timer/UI wiring: 🟢 Sonnet) | Several systems interact, and balance needs reasoning |
| 4 | **Clinch system** + leg kicks/checks | 🟣 Opus | New interaction mode between two fighters, easy to get wrong |
| 5 | **CPU AI**, 3 difficulty levels | 🟣 Opus | Decision logic and tuning the fight feel |
| 6a | **Art pass:** import placeholder .glb fighters, retarget Mixamo animations into AnimationTree | 🟣 Opus | Retargeting and animation-sync bugs are hard to debug |
| 6b | **Cage arena, broadcast HUD, camera modes** | 🟢 Sonnet | Follows the clear spec above |
| 7 | **Polish:** hit-stop, camera shake, sound, main menu, fighter/arena select, settings | 🟢 Sonnet | Routine feature work |
| 8a | **PS controller** bindings + rebind UI | 🟢 Sonnet | InputMap already handles it |
| 8b | **Roster system:** FighterData, special moves, AI style profiles | 🟣 Opus for the design, 🟢 Sonnet to add each fighter | The schema matters; adding entries is routine |

Also 🟢 Sonnet: writing additional GUT tests, renaming and refactoring along existing patterns, and documentation.
Also 🟣 Opus: performance problems on the iGPU, physics glitches, and any bug whose cause isn't obvious.

## Notes and risks
- **Animations are the biggest risk.** Mixamo has boxing and kick clips but few true Muay Thai ones (teeps, clinch). Expect some Blender editing or keyframing for the missing moves.
- **Real-fighter likenesses** require permission or licensing. Build the roster so likeness packs are swappable data, and keep the default roster fictional.

## Verification
- `godot --path . --print-fps`: confirm the Vulkan/RADV renderer in the startup log, with a stable 60 fps on the iGPU.
- Headless GUT tests: `godot --headless -s addons/gut/gut_cmdln.gd`.
- AI/balance sims: `godot --headless --path . -s tools/sim_fights.gd -- --fights=20 --a=hard --b=medium --moves` (controllers: random/easy/medium/hard; `--moves` prints per-move hit/block/whiff rates and the AI's decision sources).
- Play vs a given CPU: `godot --path . -- --cpu=easy|medium|hard|dummy --arena=ring|cage` (F1 cycles opponents, F3 swaps arena, F4 hides the controls help).
- Animations: Mixamo clips live in `assets/mixamo/src/` (motion only, `mixamorig` skeleton). Techniques Mixamo lacks (round kicks low/body/high, teep, side kick, check) are generated by `godot --headless --path . -s tools/gen_anims.gd` into `assets/anim/generated/*.res` (key poses + IK, baked at 60 fps; meta `impact` = contact time). Preview any clip: `godot --path . -s tools/anim_sheet.gd -- --clip=<res path> --out=<png>`.
- In-game fighters use the Mixamo "Beta" character (`assets/mixamo/character.fbx`) via `scripts/fighter/fighter_model.gd`: the `CLIPS` table maps game states/moves to clips (Mixamo sections or generated), strikes are time-warped so each clip's impact lands on the move's first active frame. F5 shows the debug state labels.
- Visual check: `godot --path . -s tools/capture.gd -- --arena=cage --out=<dir>` saves screenshots of every camera shot and HUD state (needs a display). The sim also takes `--arena=cage`.
- Manual playtest per milestone: every move lands and can be blocked or parried, knockdown and count work, the round ends at 0:00, the judges' decision displays, the AI fights back at each difficulty, and the camera toggle works.
- Milestone 7 (polish): the game now opens on a main menu (`scenes/main_menu.tscn`: Fight setup with opponent/arena/corner colour/rounds/round length, Settings, Quit); any `--cpu/--arena/...` flag skips it. Esc pauses during a fight (resume/settings/restart/main menu). Backspace freezes the fight for a screenshot (`scripts/core/freeze_frame.gd`: no overlay; the next click of any other key or pad button / D-pad resumes and is swallowed; Print and modifier keys are ignored). Settings (volumes, camera shake, hit-stop, fullscreen) persist in `user://settings.cfg` via the `Settings` autoload. Sound is synthesised at startup by the `Sfx` autoload (no audio files; swap streams in `Sfx._build()` for recorded samples). Hit-stop and camera shake are driven from `FightManager._on_move_resolved`; hit-stop only skips `flow.tick()` in the scene, so sims/tests are unaffected.
- Milestone 8a (gamepad): `PadLayout` (scripts/input/pad_layout.gd) defines the pad scheme: D-pad/left stick move, R = guard (tap = parry), L/R are modifier layers on the four face buttons (bottom/right/left/top = Godot A/B/X/Y), Start = pause, Select/Back = camera, bottom button also skips the round break/result. Slots are rebindable in Settings > Controller layout (saved in `user://settings.cfg`). Verified on a DragonRise "SNES Controller" (USB 0079:0126; its D-pad reports as axes 0/1). Godot only delivers joypad events to a focused window.
- Milestone 8b (roster, in progress): a fighter is a `FighterData` resource (`scripts/fighter/fighter_data.gd`) in `data/fighters/<id>.tres`, loaded by `Roster` (sorted by ranking). Fields: bio (name, nickname, country, gym, record, ranking), body (height/reach/weight, stance), attributes 1..100 (power, speed, chin, cardio, clinch; 50 = base game), signature moves (`{move_id: {damage, speed, ai}}`), CPU difficulty 1..5 (1/3/5 = Easy/Medium/Hard presets, 2/4 interpolated) and AI style biases. `Fighter.apply_data()` gives the fighter its own scaled copy of the move set (the shared MoveLibrary is never modified) and sets clinch strength, footwork, chin (knockdown-chance multiplier) and cardio (stamina regen); height scales the model. AI style biases act as a prior on the softmax pick weight (1.3 = picked 1.3x as often), not on utility. Menu: Your fighter / Opponent (with tale of the tape) / CPU = "AI Fighter rating" (default) or a fixed level or dummy. CLI: `--p1=<id> --p2=<id> --cpu=rating`. Sim: `--fa=superbon --fb=haggerty --a=rating --b=rating`. Pre-fight page: fighters with a `weight_class` get a profile screen (`scripts/ui/fighter_profile.gd`: portrait, age, weight, height, class, fighting out of, bio if any) between fight setup and the fight; Superbon and Haggerty have one (reach is shown when `reach_cm` is set). Superbon's model: `tools/import_fighter.gd -- --id=superbon --model=~/dev/projects/image-blaster/worlds/superbon/output/superbon-fight/0-superbon-fight.glb --proportions=0.265:0.29,0.49:0.535,0.8:0.805,0.862:0.872 "--iris=-0.0314,1.6832,0.0808;0.0326,1.6838,0.0802"` (use the full path; generated from the user's ring photo and face close-ups: red shorts, no headband; proportions lengthen the legs and shrink the head, iris dyes the eyes brown; both values belong to this mesh only). The `superbon.glb` kept in assets is an earlier, non-T-pose take and will not import. Pad: the settings screen and fight help show the pad's printed button names (`PadLayout.button_names`); high kick is its own action on the left face button (SNES Y), uppercut on the top one (SNES X), lead hook on L+R+Y; older saved layouts are migrated by `PadLayout.upgrade`. The player's uppercut runs at 4/2/7 frames, half the base 9/3/14 (`FightManager.PLAYER_FAST_MOVES`); the CPU keeps the base timing because with the fast one it threw ~120 a fight instead of 13. Uppercut and rear hook are generated clips. Controls: movement is relative to the opponent (up = forward, left/right = sidestep) in every camera; double-tap up = `superman_punch` (lunging strike), double-tap down = `dash_back` (leap away), both `MoveData.travel` moves the AI does not use yet; high kick = Y or hold up + round kick; the CPU opponent moves at 90% footwork (`FightManager.CPU_FOOT_SPEED`). Look: fighters import with the source's full 4096 textures (BPTC), 40k triangles subdivided once to 160k (`--subdivide`), `--detail=0.3`, and a colour-detected skin treatment (`--pores`, `--sweat`, `--scatter`; scattering runs at quality 1 for frame rate, ~75 fps in a two-fighter 1080p ring scene on a Radeon 780M); gloves are black leather with a code-made grain and a corner-colour wrist tape lettered Fairtex Fighter (`tools/gen_glove_tape.gd` renders the mask; a real brand name, so swap it before distributing). Shoulders: the importer re-weights each joint along an armpit crease (`_shape_shoulders`) and irons the armpit smooth in the guard pose (`_relax_armpits`). Round kicks: the kicking-side arm swings from guard to hang in front on that side (`_swing_arm`), the guard arm turns with the torso, and the kicking foot points along the shin (`_point_foot`); the ring has an angled shadowed key, a rim light, two shadowed spots, SSAO and 4x MSAA. Gloves: every in-game fighter wears a code-built boxing glove (`scripts/fighter/glove_mesh.gd`) with the hand bone shrunk inside it. Stance: `FighterData.anim_set` picks clips in `assets/anim/generated/<set>/` over the shared ones; `muay_thai` (Superbon, Haggerty) is upright with hands high and is built by `tools/gen_anims.gd` (generated techniques, step-drag footwork, Mixamo punches and hit reactions re-seated on the stance; sweep, knockdown, get-up and result clips stay shared). Roster: Superbon (player default, own model, neutral 1..100 attributes until details arrive) and Jonathan Haggerty (own model from `~/dev/projects/image-blaster/worlds/haggerty/output/haggerty/0-haggerty.glb`, default leg thickness; 1..100 attributes are estimates from public info; real likeness = swap-in data pack, see risks). Buakaw was removed when Superbon came in; the old balance figures (hard v hard ~50/50, own ratings ~75% Buakaw) were for Buakaw v Haggerty. Gotcha: a signature "speed" of 0.9 on the knee (10 -> 8 startup frames) broke the matchup 58-2; keep frame changes on fast moves small.
