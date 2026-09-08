# 3D Player Controller for Godot 4.8+

A feature-complete, modular 3D character controller built for **Godot 4.8+** using [CharacterBody3D](https://docs.godotengine.org/en/stable/classes/class_characterbody3d.html), [AnimationTree](https://docs.godotengine.org/en/stable/classes/class_animationtree.html), and Root Motion. Includes a full locomotion finite state machine, first- and third-person camera system, equipment and combat system, stamina mechanics, radial inventory, and contextual multi-platform input hints.

> [!NOTE]
> **Plugin Activation vs Scene Usage**:
> All core scripts use `class_name` (`Player`, `NodeStateMachine`, `Inventory`, `RadialMenu`, `Equipment`, `Camera`, `HeldObject`, etc.).
> - **Direct Usage**: You can instantiate `res://addons/3d_player_controller/scenes/player.tscn` directly into your scenes without enabling anything in Project Settings.
> - **Enabling the Plugin**: Enabling **3D Player Controller** in **Project Settings > Plugins** registers the addon and custom editor utilities.

---

## Features

### 1. Locomotion Finite State Machine (`NodeStateMachine`)
Organized state machine architecture separating primary lower-body locomotion states from upper-body actions:
- **Standing / Walking / Running**: Smooth acceleration, deceleration, and camera-relative motion.
- **Sprinting**: High-speed locomotion linked to stamina consumption.
- **Jumping & Falling**: Air control, coyote time, and smooth landing blending.
- **Crouching & Sliding**: Crouch walking and momentum-based sprinting slides.
- **Climbing**: Raycast-assisted wall detection, ledge hopping, and wall climbing. Walls become slippery during rain (BotW style): the climber periodically slides down, sprint climbing is blocked, and the climb animation slows (tunable via the `Rain Slipping` export group).
- **Hanging & Shimmy**: Braced and free-hang wall gripping with directional shimmy.
- **Swimming & Fast Swimming**: Water volume detection (`WATER` group), buoyancy, and surface swimming. Hard water entries spawn a one-shot droplet/foam splash (`water_splash.tscn`, tunable impact threshold). Swimmers ripple the water through WeatherFX's `WaterRipples` node on the water area (it renders every body in the water into the ripple simulation), so the controller knows nothing about the water shader.
- **Diving**: Hold crouch while swimming to dive below the surface; hold jump to ascend and surface. The player model pitches around a hip pivot to follow the swim direction (camera stays level), gentle buoyancy floats you back to the surface when shallow, and stamina drains constantly underwater as a breath meter — exhaustion respawns you at the last safe shore. A fullscreen underwater filter (tint + wavy refraction + vignette) activates whenever the camera submerges. Contextual HUD controls swap between `Dive`/`Climb Out` and `Dive Deeper`/`Surface` automatically.
- **Paragliding**: Deployable glider with steering control and mid-air cancel. Thermal updrafts grant an immediate `+6 m/s` catch boost on entry (BotW standard) plus continued lift and stamina recovery; all glide/dive/updraft physics are exported tunables on the `Paragliding` state node.
- **Riding** (`Riding`): one state for anything the Player gets on. A rideable (a skateboard, a vehicle, a horse) calls `player.mount(self)`; the state hands it the Player, forwards input events and the physics tick, plays the animations it asks for, and `player.dismount()` gets off. The state does the Player's side of getting on and off (the get-on and get-off clips, the camera, the crosshair, the collision shape and the step-up ray), so a rideable never sets Player flags. Skateboarding lives in the `tcps` addon and driving in the `gta` addon, each with its own camera that the state makes current while ridden.
- **Flying**: 3D spatial flying with vertical ascending/descending.
- **Sitting & Ragdoll**: Physical bone ragdoll simulation with get-up recovery.

**State node API** — `state.gd` (`NodeStateMachine`) is both the machine node and the base class of every state node under it:
- `start()` / `stop()` on the base enable/disable the state node and set/clear `player.current_state` (`States.NONE = -1` when no state is active). States extend them with `super.start()` / `super.stop()`; a node's `state` is derived from its name (`Standing` -> `States.STANDING`). `travel(from, to)` calls them directly.
- `action(keyboard, pad)` resolves a state's exported action pair for the current input type (`Controls.InputType.KEYBOARD_MOUSE` vs controller/touch).
- The base connects `Player.locomotion_node_changed` once; states override `_on_locomotion_node_changed(state_path)` (early-returning unless `process_mode == PROCESS_MODE_INHERIT`) to react to animation hand-offs (slide end, climb-on, hops, attacks) instead of polling the AnimationTree. Read `player.current_locomotion_node` / `player.current_locomotion_path` rather than the playback objects. `whistled(player)` is emitted on the authority when the `whistle` action is pressed on foot (a rideable's `ride_input` gets it first while riding); the game decides who answers, for instance the world's horse.
- `get_contextual_controls(input_type)` returns only state-specific labels; the base adds the shared `Perspective` / `Screenshot` / `Pause Menu` labels.
- Standing re-derives its grounded locomotion from `Inventory.equipment_changed` and `Player.exhausted_changed`; only the exhausted idle/moving swap (held analog input) is polled.
- Timers are `Timer` children (physics-time): `Pushing.stop_grace_timer`, `Climbing.rain_slip_timer`, `Attacking.boxing_inactivity_timer`, `Attacking.attack_timeout_timer`; Flying's double-tap uses a `SceneTreeTimer`.
- An exhausted Player cannot start an attack from Standing or Crouching: the HeavyBreathing idle has no transition into the attack animations, so the swing would never play. As a backstop, Attacking returns to Standing after `attack_timeout` (1 s) if no attack animation has started, so `is_attacking` can never stay set on a swing that did not happen.
- `Player.lethal_fall_speed` (15 m/s) is the shared ragdoll landing threshold for jumping and falling; `Player.wall_leap_horizontal_speed` / `wall_leap_vertical_speed` tune the climbing/hanging back-eject (`Player.leap_off_wall()`), and `Player.face_wall(delta)` / `clear_ledge_visuals()` are shared by the wall states.

- **Swimming ledges**: while swimming, `Swimming` moves the `LedgeDetectionHorizontal` ray to `LEDGE_RAY_DEPTH` (0.3 m) below the water surface and restores its scene height on exit, so rims flush with the water still register and jump at `SwimmingAtEdge` mantles out.

### 2. First & Third Person Camera (`Camera`)
- Dynamic toggle between **First-Person** and **Third-Person** perspectives.
- SpringArm collision avoidance preventing clipping through geometry.
- Configurable mouse sensitivity, gamepad stick sensitivity, and axis inversion.
- Smooth rotation interpolation and camera smoothing.
- Interaction targeting: each physics frame the camera's `CameraRayCast` resolves the nearest ancestor of the hit collider that implements `display_menu(player)`, stores it in `looking_at`, and emits `looking_at_changed(previous, current)` only when it changes. The camera calls `hide_menu()` on the previous target and `display_menu(player)` on the new one, so any scene using the player gets prompts without extra code; pressing `action` calls `equip(player)` on look-at targets that implement it (the project's skateboard and push button). `Equipment` is not one of them any more: pickups are walk-over areas, below. The ray ignores every area in the `WATER` group, so you can look at a boat or a prop floating in a pool from the water.
- Input is handled in `_unhandled_input`, so UI controls consume clicks and scroll first.
- While riding, the `Riding` state makes the rideable's `camera` current and this one waits; it comes back on dismount.

### 3. Equipment, Combat & Interactions (`Equipment`, `HeldObject`)
- **Weapon Classes**: 1H Swords, 2H Greatswords (with tree-logging animation), Sword & Shield, Daggers, Axes, Staffs, and Rifles.
- **Spell animation states**: the Shield group holds `ShieldPowerUp`, `ShieldSpellCast` and `ShieldSpellCasting` (Mixamo *Sword And Shield* spells), the GreatSword group holds `GreatSwordPowerUp`, `GreatSwordSpellCast` and `GreatSwordSpellCasting`, and the top level holds the one-handed standing casts `SpellCastForwards`, `SpellCastSweepingSideways`, `SpellCastSweepingUpwards` and `SpellCastUpwards` beside `StandingLocomotion`. Enter any of them with `travel_locomotion("Shield/ShieldSpellCast")`, `travel_locomotion("GreatSword/GreatSwordPowerUp")`, `travel_locomotion("SpellCastUpwards")` and so on. The one-shot casts and power-ups return to their locomotion on their own when the clip ends; the looping `...SpellCasting` channels stay until code travels back (or on to `...SpellCast` to land the spell). Nothing drives them yet: wire them from `Abilities` (`cast_started`, `ability_activated`) when a spell needs a pose.
- **Bow & Arrow Mechanics**: Aiming, string draw, charge timing, arrow trajectory, and projectile firing.
- **Pickups**: an `Equipment` in the world is a GTA-style pickup. Give it a child `Area3D` named `PlayerDetection` (a half-metre sphere works; bigger and neighbouring pickups are taken in the same step) and connect its `body_entered` to `_on_player_detection_body_entered` in the scene; the first Player to walk over it gets a copy through `equip(player)` (which now returns whether it equipped) and the area stops monitoring, so it is taken once with no prompt or button. A Player already carrying that type walks through without spending it.
- **Object Manipulation**: Pick up, carry, aim, rotate, and throw `RigidBody3D` objects or companion bodies. The throw charge bar is the `%ThrowChargeBar` node in `controls.tscn` (exported to `HeldObject.throw_charge_bar`); the optional `connector_scene` (a `PackedScene`, so exporters ship it) is instanced once on ready. In third person the `ItemSpringArm` follows the camera's yaw but clamps its pitch (`Camera.held_pitch_min` / `held_pitch_max`) and shortens against the world (the Player is excluded), so a held object never ends up in the ground or inside the Player however you look; a released body keeps ignoring the Player's collision for `HeldObject.RELEASE_GRACE` (0.3 s), so a throw leaves cleanly instead of being shoved out by depenetration.
- **Hit Detection & Combos**: Multi-hit attack combos and damage dispatching. `HitDetection` uses `Area3D` hitboxes, not shape queries: unarmed attacks use the `LeftHandHitbox`/`RightHandHitbox` bone attachments in `player.tscn`; a melee weapon must have a child `Area3D` named **`Hitbox`** (with its `CollisionShape3D`). Hitboxes only `monitoring` during attack locomotion nodes, and any ancestor of a hit body that defines `register_weapon_hit(equipment: Node, hit_node: Node)` is notified once per swing. Hits carry no knockback impulse. For props, give the weapon a child `AnimatableBody3D` named **`WeaponBody`** (`sync_to_physics` off, a shape along the blade, on the `Weapons` layer masking `Hittable`; `HitDetection.WEAPONS_LAYER` is 10): the equipped copy gets a collision exception with its Player and ragdoll bones, and `HitDetection` puts it on its layer only while a swing node plays, on every peer, so the server's copy of a remote Player pushes the props it simulates. `HitDetection` emits `weapon_hit(equipment, target)` once per target per swing; `player.tscn`'s `WeaponAudio` node (`EquipAudio`, `StowAudio`, `AttackAudio`, `HitAudio`, on the `SFX` bus) plays the TomMusic sword unsheath and sheath when equipment joins or leaves the loadout, *Sword Attack 1-3* on every weapon swing node (on every peer, from the replicated locomotion node), and *Sword Impact Hit 1-3* when a weapon lands on something with `take_hit` (relayed to peers by RPC). `Equipment.equip_sfx`, `stow_sfx`, `attack_sfx` and `hit_sfx` replace those defaults per weapon; the random sets are `AudioStreamRandomizer` resources under `resources/audio/`, the clips under `assets/tommusic/fantasy_sfx/Attacks/`.
- **Look-at ownership**: `Player.set_look_at_target(target: Node3D)` is the single writer of the spine `LookAtModifier3D` (pass `null` to clear). `HeldObject` calls it on pickup/drop and `Bow` while `Bow/ArcheryLocomotion` is active.
- **Projectiles** (`Projectile`, `scenes/bullet.tscn`): every round is a `RigidBody3D` with real ballistics *and* a swept ray between physics steps, so fast bullets never tunnel through small targets such as balloons. On impact the projectile notifies the nearest ancestor of the collider that defines `register_projectile_hit(projectile, point, normal)` (or `register_weapon_hit(weapon, projectile)` for harvestables), applies `impact_impulse` to `RigidBody3D` targets, emits `hit`, then frees itself (or freezes in place for `stuck_seconds` when `sticks_on_hit`, as arrows do). Areas without a hit handler (water, weather zones) are ignored by the sweep. Launch one with `projectile.launch(origin_transform, direction, speed, shooter, weapon)`.
- **Firearms** (`Firearm`, base of `Rifle`): a gun is an `Equipment` with a child `Muzzle` (`Marker3D`, -Z is the barrel), a one-shot `FireTimer`, an optional `LaserSight` instance and `projectile_scene`; wire them through the `muzzle`, `fire_timer`, `laser_sight` exports. While shoot is held it fires every `fire_interval` (`automatic`), launching each round on the Player's `ProjectileRaycast` line, level with the muzzle, so rounds fly straight through the crosshair to where it lands; the camera keeps that ray on its centre line every physics frame (shoulder offset and first person included), so the crosshair is where rounds go, and detection-only areas (enemy aggro spheres, melee hitboxes) sit on no collision layer so the ray passes through them. Each gun carries `magazine_size` rounds; a shot spends one, and the `reload` action ([R]) or an empty trigger pull takes one `AmmoItem` unit for the gun's `equipment_type` from the Player's GARP inventory after `reload_time` (`reload_sfx` optional), refilling the magazine with `rounds_per_unit` rounds (0 means a full magazine); nothing carried, no reload. `reserve_rounds` reads the inventory (units times rounds) on a Player and is only an export for a gun without one; Use on an `AmmoItem` selects the kind the next reload chambers (`selected_ammo`, `ammo_selected`), `loaded_ammo` is what is in the gun, and its `projectile_scene` flies instead of the gun's own. `ammo_changed` reports both counts (on every reload, shot, pickup or drop) and the HUD's `AmmoLabel` shows them while a firearm is equipped. Every shot kicks the pad and a reload pulses it via `Controls.rumble(weak, strong, seconds)`, the one gated haptics call (no rumble on keyboard/mouse or touch) that the bow and `take_hit` use too. `fire()` returns the spawned projectile (null when the magazine is empty) and emits `fired`. `fire_sfx` is an optional `AudioStreamPlayer3D`. `Rifle` adds the firing spine emote while the Player stands still (on the move it just fires, since the emote fights the walk); the world's pistol uses `Firearm` directly. An optional `MuzzleFlash` (`scripts/muzzle_flash.gd`) under the `Muzzle` marker plays any VFX scene that has an AnimationPlayer with a `main` animation: point its `vfx` and `animation_player` at the instanced scene, turn the node so the VFX's forward axis runs down the marker's -Z, and wire the gun's `fired` to `flash` and the player's `animation_finished` to `_on_animation_finished`; the VFX stays hidden between shots so its light and glow never linger. An NPC can flash the same way: `EnemyNpc.fired` is emitted for every shot, on the authority with the round and on the other peers with `null` by RPC, so a `MuzzleFlash` under its `Muzzle` works for everyone.
- **Accuracy**: ranged `Equipment` (firearms, the bow) takes an `Accuracy` resource in its `accuracy` export: `spread_degrees` is the cone half-angle for a novice, `expert_spread_degrees` the cone at `expert_level` and above, eased linearly by the shooter's `skill_level` (`Player.skill_level`, and `EnemyNpc.skill_level` in the game's enemies, which take the same resource). Save one `.tres` per weapon (`resources/accuracy/pistol.tres`, `rifle.tres`, `bow.tres`) and tune it in the editor; `Equipment.scatter(direction)` applies it, so a weapon with no resource fires dead straight. The stray angle is uniform inside the cone, so most rounds land near the crosshair. Spread is rolled on the firing peer and the round replicates through the spawner, so every peer sees the same shot.
- **Laser sight** (`LaserSight`, `scenes/laser_sight.tscn`): a beam plus surface dot stretched from the muzzle to the aim point with `aim(from, to)`; shown while the Player focuses or shoots.
- **Bow & Arrow**: `Bow` reacts to `Player.locomotion_node_changed` (`Bow/BowDrawArrow` plays the draw sound, `Bow/BowFireArrow` duplicates the template `Arrow` child and launches it through the projectile API). `Arrow` is a `Projectile` that sticks where it lands for `stuck_seconds` (one second) before vanishing, drops its shooter exception after 0.15 s and frees itself after `lifetime` if it never lands. Every shot takes one bow `AmmoItem` from the inventory (the selected kind while any is carried, else regular arrows, else nothing flies) and fires its `projectile_scene` when it names one. Selection, reload and consumption happen on the Player's multiplayer authority only; peers receive the chosen scene through the spawner. The bow fires from the Player's projectile ray, level with the nocked arrow, on the low arc through the ray's hit point (`Bow.arc_direction`), falling back to a straight shot when the aim point is out of range; when Use selects a kind of arrow with its own scene, a frozen template copy of it is nocked in place of the plain arrow (local to the authority, cosmetic), and arrows fly without linear damping. Drawing the bow plays TomMusic's *Bow Take Out* and stowing it *Bow Put Away* through the Player's `WeaponAudio`; a shot plays the bow's `BowFireArrow` node when the scene has one, else *Bow Attack 1-2* (`resources/audio/bow_attack.tres`); `arrow.tscn` carries an `Impact` player wired to `hit`, so *Bow Impact Hit 1-3* lands on every peer that simulates the round. `arrow.tscn` also has a `Tip` `Marker3D` at the head end of the shaft (local +Y, which `Arrow` turns along its velocity in flight), so an inherited arrow scene can parent a head effect under it and have it lead the flight, sit on the string when nocked and move to the impact point when the arrow sticks.

### 4. Inventory & Radial Menu (`Inventory`, `RadialMenu`)
- The inventory is the [GARP addon](../garp/README.md) (`addons/garp`, required): `player.tscn` instances its `inventory.tscn` as the `Inventory` node, so equipment on the skeleton, the radial quick-select, the BOTW style tabs of stacked items, Zelda style `ItemPickup`s and the `user://` save all live there. The `Pause` menu's `inventory_screen_scene` export points at GARP's `inventory_screen.tscn` and shows an Inventory button that opens it, with Back returning to Pause; clear the path to drop the button. `extra_screen_scene` does the same for any `PlayerMenuLayer` scene of the game's, with `extra_screen_label` as the button's text (the demo world uses it for its Fish Index). `Equipment` carries `description` flavour text and an optional `model_scene` for the inventory's turning preview, and `get_details()` adds lines under the description.
- Circular weapon/tool selection menu activated by holding assigned keys or controller D-Pad.
- Quick weapon cycling (`last_weapon` / `next_weapon`).
- Extensible custom item provider callback for vehicle radios or contextual menus. Items are Dictionaries with `display_name` and `icon` (plus `item` for equipment); a `custom_item_provider` returns the same shape so the addon never knows about stations.
- `Inventory.equipment` is a typed `Array[Equipment]`; `get_equipment_by_type(type) -> Equipment`, and `equipment_changed` fires after every change (`cycle_weapon`, `equip_from_backpack`, `unequip_all`, `Inventory.equip_pickup`, which `Equipment.equip` and the walk-over pickups go through: it makes the `BoneAttachment3D` on the skeleton, duplicates the pickup onto it with the scene's offsets, and `Equipment.equip` keeps the copy as `equipment_instance`). Each `BoneAttachment3D` holds exactly one `Equipment`; stowed attachments are hidden children of `Inventory`.
- Hold detection uses the `HoldTimer` in `inventory.tscn` (`wait_time` = hold threshold); a release before timeout cycles, a timeout opens the menu.

### 4b. Abilities (`Abilities`, `Ability`)
World of Warcraft style spells on the Zelda-style controls, so an action RPG never needs a morphing action bar:
- **Tap** the `ability` action (`Q` / Left Bumper) to cast the picked ability; **hold** it to open the ability wheel and pick another. The wheel is the same `RadialMenu` scene the inventory uses (`radial_menu.tscn`, with `hold_actions` set to `ability`), and the picked ability's name shows on the Left Bumper label. The wheel holds eight spells at most; which eight is the [GARP](../garp/README.md) `Spellbook`'s loadout, unlocked from a `SpellTree` with skill points on the Pause menu's Spells screen (`Pause.spells_screen_scene`). `Abilities.abilities` is the starting set, which the Spellbook counts as unlocked.
- `Ability` is a `Resource` any `Node3D` can cast (the Player through `Abilities`, NPCs through their own caster; `get_target` reads the Player's focus target or an NPC's `target`, and `Ability.spawn_phase` is the shared VFX/SFX/bolt playback) with `display_name`, `icon`, `icon_color` (tints the icon on the wheel and GARP's spell screens), `cooldown`, `cast_time`, `cast_range`, `energy_cost` (mana or energy drawn from the caster's `Health` pool, never from stamina), `channel_while_moving` (off by default, so movement interrupts a timed cast as in WoW while attacks always do), `is_toggle` and `ends_on_attack`; subclass it and override `activate(player) -> bool` (return `false` to refuse, spending nothing) and `deactivate(player)` for toggles. Ship abilities as `.tres` files and list them in the Player's `Abilities.abilities` export.
- `Ability.can_cast(caster)` is checked before the cast bar starts, so a doomed cast (Heal on a full patient, a damage spell with nothing locked on) is refused at once instead of channeling for nothing; `activate` checks again when the effect lands.
- `Abilities` (a `CanvasLayer` child of the Player) handles the rest: the `HoldTimer` splits taps from holds, the `CastTimer` runs cast times while `%CastBar` in `controls.tscn` fills through a tween, and any `state_changed` / `locomotion_node_changed` interrupts the cast. Cooldowns are stored as end times (toggles start theirs when they end), so nothing polls. Signals: `cast_started`, `cast_interrupted`, `ability_activated`, `ability_deactivated`.
- Every `Ability` carries VFX (`PackedScene`) and SFX (`AudioStream`) for three phases: **channeling** (kept on the caster for the cast time, stopped on interrupt), **casting** (one-shot on the caster when the effect fires) and **impact** (one-shot at `get_impact_position(player)`, the caster by default; override it for ranged spells). Channeling VFX are parented to the `Abilities.hand_anchor` (the `SpellHand` bone attachment on the Player's right hand) so a charge rides the hand, bolts leave from it too, and the other VFX are instanced under the Player's `AbilityFx` node and freed after `fx_lifetime`; SFX play through the `ChannelingAudio` / `CastingAudio` / `ImpactAudio` players there on the `SFX` bus. Phases are played on every peer through an authority RPC.
- **Cast animation**: set an ability's `cast_style` (`FORWARD`, `UPWARD`, `SWEEPING_SIDEWAYS`, `SWEEPING_UPWARD`, `POWER_UP`) and the Player picks the clip for whatever it holds through `Ability.get_cast_state(group, channeling)`: with a shield or greatsword a timed cast holds the group's `...SpellCasting` channel (`cast_started`) and the effect landing plays `...SpellCast`, or `...PowerUp` for the power-up style (`ability_activated`); unarmed the landing plays the matching standing one-handed clip (`SpellCastForwards`, `SpellCastUpwards`, `SpellCastSweepingSideways`, `SpellCastSweepingUpwards`; power up borrows the upward cast) while the channel holds the *Ready To Cast Spell* emote on the upper body (the same pose a carried object uses); bows, guns and boxing play nothing. The clips return to locomotion on their own, an interrupt (`cast_interrupted`, which a cast that fizzles when it lands also emits, such as Heal at full health or Firebolt with nothing locked on) drops the channel pose, and the cast's own clips never count as a locomotion change that interrupts it. The three signals are connected to the Player in `player.tscn`.
- **Elements**: `elements` is a set of flags (`Fire`, `Water`, pick any mix) that the impact lets loose on the world within `element_radius`: Fire lights every `GrassField` (`ignite_at`, spreading for `element_fire_duration`) and `BurnableGrass` patch there, the way the thrown torch does; Water douses them (`GrassField.douse_at`). `Ability.apply_elements` runs from `spawn_phase` with the impact VFX, so every peer and NPC casters get it too. Firebolt carries Fire. `Ability.ignite_grass(tree, at, radius, duration)` is the Fire half as a static, for anything that is not a spell (a burning projectile).
- **Toon filter** (`ToonFilter`, `scenes/toon_filter.tscn`, `assets/shaders/toon_filter.gdshader`, `scripts/cel_compositor_effect.gd`): screen-space toon shading under the Player's `Camera3D` with a `mode` of `OFF`, `NEWSPAPER` or `CEL`. `NEWSPAPER` is a full-screen quad whose spatial shader posterises the opaque scene into `bands` luminance steps (hue and saturation kept) and draws `outline_color` lines where the depth buffer jumps, with `strength` to dial it down; it reads only the screen and depth textures, so it compiles in Forward+, Mobile and Compatibility, and draws before every CanvasLayer (HUD untouched) and before every other transparent object. `CEL` puts a `Compositor` with one `CelCompositorEffect` on the camera: a compute shader run after the transparent pass that snaps luminance to `bands` (3) hard perceptual levels, pushes saturation by `saturation_boost`, and inks `outline_color` `outline_thickness` (2 px) lines wherever the depth jumps past `depth_threshold` or the normal-roughness buffer's normal turns past `normal_threshold`, so interior creases get ink too; far-plane pixels are skipped so the sky keeps its gradient, and transparent objects are banded but not outlined. It needs the Forward+ compositor: `is_cel_available()` checks `RenderingServer.get_current_rendering_method()`, `cycle()` skips it elsewhere, and the effect stays inert without a `RenderingDevice`. The `toggle_toon` action (`F6`) cycles the modes; the **Toon shading** option in Video settings picks one (Cel greyed with a tooltip off Forward+); `mode_changed` keeps the option in step and the choice is saved as `PlayerSettingsResource.toon_mode` (an older `toon_enabled = true` loads as Newspaper). Local only, never replicated.
- **Chat** (`scenes/chat.tscn`, `ChatWindow`): an embedded, movable and resizable window on the local Player only. Enter (`chat` action) opens the input row, Enter or Send submits, Escape cancels; messages travel by RPC so ENet and Steam sessions both carry them, with the Steam persona name or `Player <id>` as the sender. Lines starting with "/" run locally: `/help` lists commands and `/teleport x y z` warps the Player; add a command with one line in `ChatWindow.commands`. The window fades to `idle_alpha` after `idle_seconds` and comes back while hovered or while a message arrives; while the input is open `Player.is_typing` blocks every gameplay action, and the window hides while a menu is up. Its position and size persist in `PlayerSettingsResource.chat_rect`.
- **Throwing**: `HeldObject` also throws inventory items. With nothing in hand, `throw` (`T` / Right Bumper) takes the equipped `Equipment` if its `is_throwable` is set (`Inventory.forget_equipment` unequips it), else `Player.selected_throwable` or the first `Item` with `throwable`, and puts its model in `HeldObject.throw_hand` (the `HeldItemConnector` bone attachment) while the usual charge runs; release throws it as `scenes/thrown_item.tscn` (`ThrownItem`) at `throw_speed` times the charge, through the `ProjectileSpawner` (`fire` with extra launch data) so every peer gets the body. On its first landing the server's copy calls `take_hit(throw_damage)` on what it hit and `place`s a GARP `ItemPickup` (or the equipment's scene) where it lies, despawning the body everywhere. Pausing mid-charge puts the item back.
- **Seeker wheel**: hold `seeker` (`I` / D-pad Up) for a second `RadialMenu` (`scenes/seeker_wheel.tscn`, `Player.seeker_wheel`). Aiming with a firearm, or holding a bow with focus held or the string drawn, it lists the carried ammunition kinds for that weapon and releasing on one selects it exactly as Use does (`Inventory.use_item`), so the badges and the nocked arrow follow; otherwise it lists the throwable items and releasing on one sets `Player.selected_throwable` for the next throw. It stays closed with nothing to pick, never opens on a puppet, and a carried object keeps D-pad Up for its own rotation. The HUD's Seeker hint reads Arrows with a bow out and Ammo with a gun out (`Controls.seeker_label_text`, refreshed on every equipment change).
- `target_mode` picks where impact lands: `SELF` (the caster) or `FOCUS` (the locked-on `Focus` target; with nothing locked, whatever the crosshair's projectile ray points at that has `take_hit`, found by `Ability.get_aimed_target`; with nothing there, the aim point along the ray). So a damage spell fires forward like a projectile without a lock, action-RPG style, and a lock only makes it home. Override `impact(player, target)` to apply damage or buffs to the target when the impact lands.
- Set `projectile_speed` above 0 and the casting VFX/SFX fly to the target as a `SpellProjectile` (`spell_projectile.tscn`) instead of a bullet or arrow: a plain `Node3D` bolt with no physics that always arrives, homing on a moving target by default (`projectile_homing`). Impact (and `impact()`) lands when the bolt arrives, WoW style; every peer flies its own copy and only the caster's authority lands the impact.
- Included abilities (`resources/abilities/`): **Stealth** (`StealthAbility`, instant toggle) sets `Player.is_stealthed`, which swaps every mesh under the skeleton for a ghost of itself (`assets/shaders/stealth.gdshader`: the surface's own colour and texture washed pale and tinted cold, drawn after a `depth_prepass_alpha` pre-pass so arms never show through the torso as plain `transparency` does) and tweens its alpha down to `1 - stealth_transparency` over `stealth_fade_time`, restoring the original materials once the fade out lands; the flag is replicated so other peers see the fade, and it makes followers lose the Player; any melee swing, bow shot or firearm `fired` ends it. **Heal** (`HealAbility`, 1.5 s cast) restores health. Heal casts upward with the TomMusic *Waterspray* channel and *Wave Attack* cast sounds, Stealth sweeps sideways with *Ice Freeze*; both still ship without VFX. The sounds live in `assets/tommusic/fantasy_sfx/Spells/`.
- Only the multiplayer authority reads input and casts; effects that others must see belong on replicated Player properties, as Stealth does.
- `Player.slow(factor, seconds)` is an RPC that lands on the owning peer like `take_hit` and scales the movement wish by `movement_scale` for a while, so a slowing spell walks the Player where it would run; a newer slow replaces an older one and runs its own timer. Give any other target a `slow(factor, seconds)` method and a slowing `DamageAbility` reaches it the same way.

### 5. Multi-Platform Contextual Controls (`Controls`)
- Adaptive input icons and button hints supporting:
  - **Keyboard & Mouse**
  - **Microsoft (Xbox)**
  - **Sony (PlayStation)**
  - **Nintendo (Switch)**
  - **Touch Screen**
- Real-time contextual action labels that adapt dynamically to the player's active locomotion state.
- `Controls` (class_name) registers every addon action from its `Controls.ACTIONS` table at runtime (keys, joypad buttons/axes, mouse buttons, deadzone), so the addon stays drop-in with no `project.godot` edits. Actions a project already defines are left untouched; the engine's built-in `ui_*` actions are only extended (joypad A / D-pad). The unused `emote` action is no longer registered.
- Device button textures come from per-vendor `Texture2D` lookups (`_vendor_textures`) applied in one loop; keyboard-only and joypad-only hints toggle visibility as a group, and `update_input_ui()` runs from the `current_input_type` setter before `input_type_changed` is emitted.

### 6. Stamina System (`Stamina`)
- Stamina is the Player's movement energy (sprinting, climbing, swimming, gliding; sprinting with a pistol or rifle costs nothing, since their blend spaces stop at the run clip and sprint buys no speed); abilities cost mana from the `Health` child's energy pool instead, so casting never touches the stamina wheel. Mana regenerates only out of combat: enemies call `Player.hunted_by(path, hunting)` (an RPC to the owner) when they start and stop targeting the Player, and `Health.regen_paused` holds the pool while `Player.hunters` is not empty. Hit points also live on `Health` (see 6c). `Player.take_hit(damage, from)` (an RPC that lands on the owning peer) costs health, shoves the Player away and rumbles the pad; `Player.heal(amount)` (an RPC to the owner) refills health, and Players are `Focusable`, so the Heal ability lands on a locked-on fellow Player instead of the caster; `register_projectile_hit` makes enemy arrows and bullets (`Projectile.damage`) count. At zero health the Player ragdolls and the `RespawnTimer` brings them back at the spawn point with full health.

### 6c. Health, Head Bars & Boss Bar (`Health`, `StatusBars3D`, `Boss`, `ProgressBar3D`)
- `Health` (`scenes/health.tscn`) is a drop-in child for any character: `max_health`, `health`, an optional `max_energy` pool with `energy_regen` on its `RegenTimer` (the Player ships with 100 mana; the spellcaster NPC has its own pool), `damage()`, `heal()`, `spend_energy()`, and `health_changed` / `energy_changed` / `damaged` / `died` signals. Replicate `Health:health` (and energy) from the authority and puppets follow.
- `StatusBars3D` floats a health bar (green for Players, red for enemies) and a blue energy bar over the head; wire `Health.health_changed` and `Health.energy_changed` to `set_health` / `set_energy` in the scene; the Player's blue bar is its mana. Bars hide while empty or full. `ProgressBar3D` is the billboarded world-space bar underneath (float values, per-instance colour, `always_visible`).
- `MeleeHitbox` (`scenes/melee_hitbox.tscn`) is an attack volume for NPC weapons: parent it to the bone attachment holding the weapon, set `attacker` and `damage`, and call `swing()` when the animation reaches the strike; it stays live for `active_seconds` and hurts each body it overlaps once per swing through `take_hit`, so a hit lands because the weapon touched the target.
- `Boss` (`scenes/boss.tscn`) shows the owner's `boss_name` and health on the HUD boss bar (`%BossBar` in `controls.tscn`, Breath of the Wild style) of the player it is fighting: the authority calls `engage(peer_id)`, `target_peer` replicates through its own synchronizer, and the peer owning that player shows the bar through `Controls.show_boss` / `update_boss` / `hide_boss`.
- Modular drain and recovery rates for sprinting, climbing, swimming, diving (breath meter), and gliding.
- Exhaustion state with heavy-breathing locomotion recovery.
- Inspector toggles to enable or disable stamina constraints. The hide delay is the `Stamina/Timer` node's `wait_time` in `player.tscn` (its `timeout` is wired to `hide`).
- **WeatherFX interop (optional)**: When the `weather_fx` addon is present, precipitation is read via a soft lookup (`Player.get_precipitation_strength()`) — the addon remains fully functional without it. The player scene root belongs to the `Player` group so interoperating addons can find it with an O(1) group lookup.

### 6b. Riding, Focus & Water Splash (`Riding`, `Focus`, `WaterSplash`)
- **Rideable contract** (duck typed; the addon depends on no rideable). Methods: `mount(player)` and `dismount(player)` on entering and leaving the state, `ride(player, delta)` every physics frame, optional `ride_input(player, event)`, `locomotion_node_changed(player, state_path)` and `get_contextual_controls(input_type)`, which returns label names to text (`{"key_k": "Dismount"}` goes on `Controls.key_k_label`; unknown names are dropped). Optional properties the state reads: `blocks_hands` (weapons and items stay holstered, the crosshair hides), `disables_collision` (the Player's collision shape is off while ridden, for a seat inside a body), `seat` (a `Node3D` the state pins the Player to, transform and all, after every ride, so they turn and move with the rideable in the same frame while their camera keeps the view it had, as on foot; the rider faces and their camera looks along the seat's -Z, Godot's forward, so point the seat the way the rideable travels, and they keep that facing when they get off; the Player is not reparented, so the spawner, the synchronizer and every path to it keep working; the horse uses it, the car positions its driver itself around the enter animation), `camera` (a `Camera3D` the state makes current; without one the Player's own camera stays the view and keeps looking around), `mount_animation` / `dismount_animation` (locomotion nodes the state plays on the way on and off, during which the rideable is not ridden; `player.dismount(true)` skips the get-off clip, a bail out) and `input_type` (kept equal to the Player's current `Controls.InputType`, so the rideable resolves its own keyboard and pad action exports). The Player's step-up ray is off for every ride, since the rideable owns the ground contact. Animations stay in the Player: the rideable emits `locomotion_requested(state_path, immediate)`, `locomotion_blend_requested(path, value)` and `jump_requested`. Beyond the contract a rideable uses the Player as a `CharacterBody3D` plus its movement API (`orientation`, `model_pitch`, `rotate_model_to_direction`, `turn_model_toward_direction`, `update_movement_and_rotation`, `warp_to`, `player_model`, `player_input`, `camera` and the state flags). `ride_started` / `ride_ended` signals and the `riding` reference tell everyone else what is being ridden. `ActionPrompt.show_for(player, "Get In")` names the Action button while a prompt is up and `hide_for(player)` gives the label back.
- **Focus**: candidates are bodies in the `Focusable` group overlapping the `TargetDetection` area; a target that leaves the area is dropped after `Focus/TargetLossTimer` elapses. Lock-on is disabled while a firearm is equipped (`Inventory.equipment_changed`). Put a `Marker3D_FocusTarget` on a body to set its focus point. While locked on, the camera aims at the target in the Player body's own frame, so it stays on the target after a ride or a rotated spawn instead of swinging off by the body's yaw.
- **WaterSplash**: `emitters: Array[GPUParticles3D]` is exported from `water_splash.tscn`; the splash frees itself once every emitter's `finished` signal has fired.

### 7. Debug HUD & In-Game Settings (`Debug`, `Settings`, `AudioSettings`, `VideoSettings`)
- **Debug Telemetry**: State, equipment, perspective and FPS read-outs refreshed at 10 Hz by a `Timer` in `debug.tscn` while the HUD is visible (toggle with `F3`; only the multiplayer authority reacts). The click-to-move target is marked by the hidden `NavigationMarker` sphere in the scene, which hides itself from `Player.navigating_changed`.
- **Menu base class** (`PlayerMenuLayer`): `Pause`, `Settings`, `AudioSettings`, `VideoSettings` and `LobbyManager` extend it. It owns `player`, `focus_on_show` (the control focused when the menu opens, set in each scene), `show_menu()`/`hide_menu()` (which set `player.is_paused` and the mouse mode) and closes on the `start` action. Subclasses only hold their button handlers.
- **Split Settings Menu**:
  - **Audio Settings** (`AudioSettings`): Volume sliders and step buttons for `Dialog`, `Menu`, `Music`, and `SFX` buses. Slider `value_changed` applies the bus volume immediately; the file is written on `drag_ended` and when the menu closes, not on every tick. The bus name and the slider are bound in the scene's `[connection]` blocks, so one handler serves all four rows. With Steam loaded the Audio settings also show a Voice Chat Volume row and a Mute voice chat toggle; both drive the `Voice` bus (added to `default_bus_layout.tres` and created by `Audio` when a project lacks it) and persist locally in `PlayerSettingsResource.voice_volume` and `voice_muted`.
  - **Video Settings** (`VideoSettings`): Controls for `VSYNC`, `MSAA`, `SSAA`, `FXAA`, `SSRL`, `TAA`, and `FSR`. `SSAA` and `FSR` both drive the viewport's 3D scaling, so picking one resets the other (control and saved value). The MSAA/SSAA value tables live only in `PlayerSettingsResource`.
- **Persistent User Settings**: All audio and video preferences are saved to and loaded from `user://settings.tres` via `PlayerSettingsResource`. `load_or_create()` returns one shared instance, so the player applies it once at startup and every menu edits the same object.
- **Multiplayer Animation Sync**: `PlayerSynchronizer` replicates `sync_locomotion_node` (the full `Group/Node` locomotion path) and `sync_blend_position`; puppets travel their AnimationTree to that path and write the blend position into whichever blend space is current.

### 8. Audio Component System (`Audio`)
- Modular 3D audio subsystem (`audio.tscn` paired with `audio.gd`) encapsulating surface-aware footstep audio streams (`Grass`/`Dirt`, `Stone`, `Wood`, `Water`, `Slide`).
- Dynamic surface detection via physics collider group tagging and raycasting.
- Centralized volume scaling: `set_sfx_volume` covers the footstep players and every `vehicles` group member with a `set_sfx_volume(value)` method; `set_music_volume` covers every node in the **`radio`** group with a `set_volume(linear: float)` method. Add your radios (e.g. `RadiOtPlayer3D`) to the `radio` group for the music slider to reach them.
- Creates the `Dialog`, `Menu`, `Music`, and `SFX` audio buses at runtime when your project's bus layout lacks them, so the audio settings menu works without editing `default_bus_layout.tres`. Footstep players play on `SFX`.

### 9. Steam Lobby UI (`LobbyExplorer`, `LobbyManager`) & Loading Screen (`Loading`)
- Optional and self-contained: the lobby scenes reach Steam only through `Engine.has_singleton("Steam")` and the `/root/Steamworks` autoload when present, and ship with plain `TextureRect`/`Label` nodes and Kenney icons, so the addon has no dependency on GodotSteam or GodotSteamKit and still exports to web. Without Steam the UI reports "Steam unavailable" and disables its buttons.
- `lobby_explorer.tscn` lists public lobbies and hosts/joins one. Set its exports on the instance in your project: `world_scene` (loaded after hosting/joining), `title_scene` (loaded by BACK) and `footer_text` (shown with the current year). `lobby_manager.tscn` (child of the Player, opened from the pause menu) lists members with avatar, host badge, profile/achievements shortcuts and, for the host, promote/kick; kicks go through Steam's lobby chat and the list refreshes from Steam's `lobby_chat_update`/`lobby_data_update` callbacks.
- `loading.tscn` (`Loading`) shows a tip, progress bar and dependency log while `ResourceLoader` loads a scene in a thread; `load_scene(path)` ignores a second request while one is in flight and only polls while loading.

---

### 10. Multiplayer (`SteamPeer`, `PlayerSpawner`, `ProjectileSpawner`, `SyncedBody`)
- **Session**: drop a `SteamPeer` node into the world. When the world loads inside a Steam lobby it hosts if the local user owns the lobby and connects to the owner otherwise (`SteamMultiplayerPeer`, reached only through the Steam singleton, so web exports stay inert). Call `host()` yourself after creating a lobby locally.
- **Players**: a `PlayerSpawner` (`MultiplayerSpawner`) with `player_scene` set to `player.tscn` or a scene inheriting it spawns one player per peer under `spawn_path`, named by peer id, and frees it on disconnect. `Player._enter_tree` takes its multiplayer authority from that name, so input, aiming and firing run only on the owning peer while `PlayerSynchronizer` replicates transform, locomotion path and blend position to everyone else. `local_player_spawned` hands the world the player it controls. In the editor the spawner (a `@tool`) shows the Player's model at `spawn_point` (or the `spawn_path` container's origin) so you can build the map around them; it is an internal child that is never saved and never exists in the game, and it refreshes when `player_scene` or `spawn_point` changes.
- **Projectiles**: a `ProjectileSpawner` in the `ProjectileSpawner` group makes `Firearm.fire()` and `Bow.fire_arrow()` (with `arrow_scene`) go through `spawner.fire(scene, origin, direction, speed, shooter, weapon)`. Clients ask the host over RPC; the host spawns with a custom `spawn_function`, so every peer instantiates and launches an identical round from the same data and resolves its own hits. Rounds sit on no collision layer and ignore each other. `ProjectileSpawner.place(scene, position)` spawns any scene at a world point on every peer through the same `spawn_function` (positions are relative to `spawn_path`), and `ProjectileSpawner.ignite(position, radius, duration)` lights the grass on every peer over an authority RPC; only the server's call does anything, since spawned rounds are the server's. `ProjectileSpawner.find_for(node)` returns the spawner of that node's multiplayer session.
- **World objects**: `SyncedBody` is a `MultiplayerSynchronizer` for physics props; peers that do not own the body freeze it kinematically and take the replicated transform. `resources/rigid_body_replication.tres` and `resources/character_body_replication.tres` are ready-made replication configs. Hit-driven state such as balloons and harvestables should resolve on the server and replicate back (`register_projectile_hit` → RPC to the server → `call_local` broadcast).
- **Signals and spawn state**: `Player.state_changed` only fires once the node is ready, because the spawner applies replicated spawn state while a puppet's children are still entering the tree.

## Installation

### Option 1: Manual Installation (Recommended)

1. Download or clone this repository.
2. Copy the `addons/3d_player_controller/` directory into your Godot project's `addons/` folder:
   ```text
   your_godot_project/
   ├── addons/
   │   └── 3d_player_controller/
   │       ├── assets/
   │       ├── plugin.cfg
   │       ├── plugin.gd
   │       ├── scenes/
   │       │   ├── player.tscn
   │       │   ├── controls.tscn
   │       │   └── ...
   │       ├── scripts/
   │       └── tests/
   ├── project.godot
   └── ...
   ```
3. Open your project in **Godot 4.8+**.
4. Go to **Project > Project Settings > Plugins** and toggle the **Enable** checkbox next to **3D Player Controller**.

The addon needs no `project.godot` edits. The Steam lobby UI and the `Loading` screen are inside `addons/3d_player_controller/scenes/` and work without GodotSteam installed. Copy `addons/garp/` alongside it: the Player's `Inventory` node is GARP's scene.

### Option 2: Download Release Zip

1. Download `3d_player_controller-vX.Y.Z.zip` from the [Releases](https://github.com/kirbycope/godot-3d-player-controller-v3/releases) page.
2. Extract the `3d_player_controller` folder directly into your project's `addons/` directory.

---

## Interactive Demo Scene

Open and run **`res://addons/3d_player_controller/scenes/demo/demo.tscn`** to explore the entire locomotion, combat, and interaction sandbox:
- **Playground Arena**: Features a courtyard, climbable walls, slopes/ramps, high towers for paragliding, and a water pool for swimming.
- **Quick Teleports**: Instantly jump to the Glider Tower, Water Pool, Climbing Wall, or Main Courtyard.
- **Full Debug HUD**: Press `F3` at any time to open the complete debug telemetry and feature toggles panel (state, speed, stamina, perspective, flight, ragdoll, etc.).

---

## Quick Start

### 1. Instantiate the Player Scene

Drag and drop the ready-to-use Player scene into your level:

```text
res://addons/3d_player_controller/scenes/player.tscn
```

### 2. Scene Setup Requirements

| Node | Where it goes | Set in the Inspector |
|---|---|---|
| `Player` (instance `scenes/player.tscn`) | A child of your level root, standing above the floor | `enable_flying`, `enable_paraglider`, `enable_ragdoll`, `enable_stamina`; `paraglider_scene` for the optional glider (the addon ships `scenes/paraglider.tscn`; `scenes/action_prompt.tscn` is the interaction prompt your props can use); `mass` and `push_force` for shoving rigid bodies |
| Floors and walls | `StaticBody3D` + `CollisionShape3D`, or CSG with `use_collision = true` | Put them in the `GRASS`, `DIRT`, `STONE` or `WOOD` group to pick the footstep sounds |
| `NavigationRegion3D` | Wrapped around the walkable floor and baked | Needed for the player's `NavigationAgent3D` (auto-walk and teleports) |
| Water | An `Area3D` in the `WATER` group with a `CollisionShape3D` | Connect `body_entered` / `body_exited` to a script that calls `player.enter_water(area)` / `player.exit_water(area)` |
| Lighting and camera | Your own `WorldEnvironment` and `DirectionalLight3D` | The Player scene brings its own `Camera3D` on a `SpringArm3D`, so add no camera |

Minimum scene:

```text
Level (Node3D)
├── WorldEnvironment
├── DirectionalLight3D
├── NavigationRegion3D
│   └── Ground (StaticBody3D, group GRASS)
└── Player (player.tscn)
```

The player's HUD (`Controls`, `Debug`, `Pause`, `Settings`, `Inventory`, `Stamina`, `Crosshair`) lives inside `player.tscn`, so nothing else is needed on screen.

### How `demo.tscn` does it

| Demo node | What it demonstrates |
|---|---|
| `Player` | `player.tscn` instanced with `paraglider_scene` (`scenes/paraglider.tscn`) set in the Inspector; `demo.gd` switches on `enable_paraglider` and `enable_stamina` in `_ready()`. |
| `NavigationRegion3D/Ground` (group `GRASS`) | The baked floor the `NavigationAgent3D` walks on, with grass footsteps. |
| `Structures/Tower`, `ClimbingWall` (group `STONE`), `Ramp` (group `WOOD`) | Climbing, hanging, sliding and a high launch for the paraglider, with stone and wood footsteps. |
| `Structures/PoolBasin/WaterPool` (`Area3D`, group `WATER`) | `body_entered` / `body_exited` are connected in the scene to `_on_water_pool_body_entered` / `_on_water_pool_body_exited`, which call `enter_water(water_pool)` / `exit_water(water_pool)` for swimming and diving. |
| `Markers/Courtyard`, `Tower`, `Pool`, `ClimbingWall` + `HUD/TeleportPanel` buttons | Each button's `pressed` is connected in the scene to `_on_teleport_pressed` with the marker's NodePath bound, and the handler moves the player there. |

### 3. Default Keybindings

| Action | Keyboard / Mouse | Gamepad (Xbox) |
|---|---|---|
| **Move** | `W` / `A` / `S` / `D` | Left Stick |
| **Look / Aim** | Mouse Motion | Right Stick |
| **Jump / Fly Up / Hop** | `Space` | `A` (Button 0) |
| **Sprint / Fast Swim** | `Shift` | `B` (Button 1) |
| **Crouch / Slide / Drop** | `Ctrl` | `X` (Button 2) / `Right Stick Click` |
| **Attack / Shoot** | `Left Click` | `Right Trigger` |
| **Aim Bow / Focus** | `Right Click` | `Left Trigger` |
| **Pick Up / Throw Object** | `E` / `Left Click` | `Right Bumper` / `Right Trigger` |
| **Cast Ability / Ability Wheel** | `Q` (Tap / Hold) | `Left Bumper` (Tap / Hold) |
| **Radial Menu / Prev Weapon** | `J` (Hold) | `D-Pad Left` (Hold) |
| **Radial Menu / Next Weapon** | `L` (Hold) | `D-Pad Right` (Hold) |
| **Toggle Perspective** | `F5` | `View / Back` |
| **Debug HUD** | `F3` | — |
| **Toon shading** (cycle Off, Newspaper, Cel) | `F6` | — |
| **Chat** | `Enter` | — |
| **Pause Menu** | `Escape` | `Start` |
| **Dismount** (`whistle`, a rideable's exit) | `K` | `D-Pad Down` |
| **Push-to-talk** (`broadcast`, voice chat) | `V` (Hold) | none |

All of the above are registered at runtime from `Controls.ACTIONS` when missing from the project's InputMap; the old `emote` (`M`) action was removed.

---

## Adding New Mixamo Animations

To prepare and import custom Mixamo animations with Root Motion:

1. Log into [Mixamo](https://www.mixamo.com/) and select the **Y Bot** character.
2. Search for and download your desired animation:
   - Format: **FBX Binary (.fbx)**
   - Skin: **Without Skin**
   - Frames per Second: **30** or **60**
3. Move the downloaded `.fbx` into `addons/3d_player_controller/assets/mixamo/animations/source/`.
4. Process root motion using the Blender script:
   ```bash
   blender --background --python tools/bake_root_motion.py
   ```
5. In Godot, reimport the resulting `.glb` as an **Animation Library** retargeted to `mixamo_root_bone_map.tres`.
6. Open `player.tscn`, select `AnimationPlayer`, and load the animation into the library.

---

## Example resources

`addons/3d_player_controller/resources/` holds the resources the addon needs to run alone: two abilities, three accuracy profiles and three replication configs. They reference only this addon (its scripts, icons and TomMusic sounds), never a host project's `res://resources/...` or `res://scenes/...`, so the addon works by itself and in the [GARP](../garp/README.md#example-resources) repo, whose demo tree is built from the two abilities. A game's own spells, fish and items live in its project-level `resources/` (see the [project README](../../README.md#example-resources)).

| File | Class | What it is | Used by | Tests that load it |
|---|---|---|---|---|
| `resources/abilities/stealth.tres` | `StealthAbility` (`scripts/stealth_ability.gd`) | Instant toggle, sets `Player.is_stealthed` | `scenes/player.tscn` (`Abilities.abilities`), GARP's `spell_tree_demo.tres`, the host's `world_player.tscn` and QA tree | `tests/test_abilities.gd`, GARP's `test_spellbook.gd`, `test_spells_screen.gd`, `test_spell_tree_editor.gd` |
| `resources/abilities/heal.tres` | `HealAbility` (`scripts/heal_ability.gd`) | 1.5 s cast, restores `amount` health | `player.tscn`, GARP's demo tree, the host's `enemy_spellcaster.tscn` | The same |
| `resources/accuracy/pistol.tres`, `rifle.tres`, `bow.tres` | `Accuracy` (`scripts/accuracy.gd`) | Spread cones per weapon (`spread_degrees`, `expert_spread_degrees`, `expert_level`) | Nothing in the addon's own scenes; the host's weapons in `world.tscn` and its `enemy_archer.tscn` and `enemy_rifleman.tscn` take them in the `accuracy` export | `tests/test_accuracy.gd` |
| `resources/boss_replication.tres`, `character_body_replication.tres`, `rigid_body_replication.tres` | `SceneReplicationConfig` | Multiplayer property lists for a boss, a character body and a rigid body | `scenes/boss.tscn`; the host's NPCs and props | None directly |

Adding more here:

- An ability: New Resource, `HealAbility` or `StealthAbility`, or a new script under `scripts/` that extends `Ability` (override `activate`, `impact`, and `deactivate` for toggles). Save it under `resources/abilities/` with an icon from `assets/game_icons/` or `assets/icons/` and sounds from `assets/tommusic/`. List it in the Player's `Abilities.abilities` to put it on the wheel, or on a GARP `SpellTree`; the Spell Tree panel's palette finds it on its own.
- An accuracy profile: New Resource, `Accuracy`, saved under `resources/accuracy/`, assigned to the weapon's `accuracy` export.
- `test_abilities.gd` and `test_accuracy.gd` preload these files by name, so renaming one means updating them.

---

## Testing

The controller includes an automated test suite powered by [GUT (Godot Unit Test)](https://github.com/bitwes/Gut).

### Running Tests Headless (CLI)

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://addons/3d_player_controller/tests -gexit
```

### Running Tests in Editor

1. Open the **GUT** panel at the bottom of the Godot editor.
2. Select directory `res://addons/3d_player_controller/tests/`.
3. Click **Run All**.

---

## Assets

| Folder | Source | License |
|---|---|---|
| `assets/game_icons/` | [game-icons.net](https://game-icons.net/) (authors listed in the `.txt` file next to each icon, e.g. Lorc) | CC BY 3.0 |
| `assets/icons/` (`stealth.svg`, `heal.svg`) | Drawn for this addon | CC0 |
| `assets/kenney_nl/` (incl. `Lobby Icons/`, copied from Kenney's Game Icons pack) | [Kenney](https://www.kenney.nl/) | CC0 |
| `assets/quaternius/` (characters, `paraglider/`) | [Quaternius](https://quaternius.com/) | CC0 1.0 |
| `assets/freesound/72853__benboncan__parachute.wav` | [Benboncan on Freesound](https://freesound.org/s/72853/) | CC BY 4.0 |
| `assets/freesound/570701__robinhood76__10136-flag-flicking-on-strong-wind-isolated.wav` | [Robinhood76 on Freesound](https://freesound.org/s/570701/) | CC BY-NC 4.0 (non-commercial) |
| `assets/tommusic/` | [TomMusic](https://tommusic.itch.io/) | Not stated (the pack's `ReadMe.txt` contains no license) |
| `assets/mixamo/` | [Adobe Mixamo](https://www.mixamo.com/) | Adobe Mixamo terms |
| `assets/pixabay/` (arrow swish and twang) | [djartmusic on Pixabay](https://pixabay.com) | Not recorded - fill in |
| `assets/le_lu/wind/` (the paraglider's wind streaks: two visual shaders, four textures, two meshes copied from the Wind VFX pack, so the addon stands alone without `weather_fx`) | [Le Lu](https://www.patreon.com/Le_Lu) | Not recorded - fill in (Patreon pack, no license file) |

---

## License

MIT License.
