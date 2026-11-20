# Blue Archive 3D Fan Game Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a playable 3D Blue Archive fan game in Godot 4.7 featuring semi-open academy hub exploration, FPS/TPS Sensei controls, rich student intimacy (headpat, cheek pinch, feeding gestures), a relaxed cooking minigame, a chibi tactical multi-room roguelike dungeon with RTS micro-controls, 4 distinct role AIs, random combat events, and a portable modding system (`<game_dir>/mods/`).

**Architecture:** Decoupled modular and data-driven architecture (`Core/`, `Data/`, `Hub/`, `Combat/`, `Minigames/`, `UI/`). Core game state communicates via a central `EventBus` autoload; characters are defined via unified `StudentData` resources/JSON schemas supporting dual-model pipelines (1:1 Normal model for Hub, Chibi model for Combat).

**Tech Stack:** Godot Engine 4.7 (GDScript), Jolt Physics 3D, D3D12/Forward+ with low-end rendering fallbacks, GLTF/GLB 3D pipeline with blendshapes.

**Spec:** [docs/superpowers/specs/2026-11-19-blue-archive-fan-game-design.md](file:///D:/This%20PC/Project/test/docs/superpowers/specs/2026-11-19-blue-archive-fan-game-design.md)

## Global Constraints

* Engine version: Godot 4.7.
* Physics engine: Jolt Physics 3D.
* Scripting language: GDScript (project has C# dotnet configured but primary development uses GDScript for modding accessibility).
* Portable Mod directory: Must resolve relative to the game executable directory (`<game_dir>/mods/` via `OS.get_executable_path().get_base_dir().path_join("mods")`), falling back to `res://mods` in editor mode.
* Dual-Model Pipeline: 1:1 Normal models (`normal_model.glb`) for Hub & Intimacy; Chibi models (`chibi_model.glb`) for Tactical Combat.
* Performance floor: Must run stably (≥30 FPS) on 8GB RAM and integrated GPU (Intel UHD 620 / Vega iGPU) at low settings.
* No hard-coded student lists: All students and skills must load dynamically from data schemas to ensure 100% moddability.
* All Resource/Data classes must be serializable to JSON for save/load and modding compatibility.

## Review Focus

1. **Mod Directory Resolution:** `ModLoader.get_mod_root_dir()` must return `res://mods` inside Godot Editor (`OS.has_feature("editor")`) and the executable's sibling `mods/` directory in exported builds, without file I/O exceptions on either path.
2. **Missing Model Fallbacks:** If a modded student provides only a Chibi model or only a Normal model, the game must fall back gracefully to a placeholder proxy mesh instead of crashing the scene tree.
3. **Gesture Raycast Precision:** Camera FOV or aspect ratio changes must not offset the raycast hitboxes for headpats, cheek pinches, or feeding — test at 16:9, 16:10, and 21:9.
4. **Unit Micro Interrupt vs Role AI:** When the player issues a manual move/cover order, the unit must set `has_player_order = true` and Role AI must yield until the order completes or a critical state (HP < 10%) triggers emergency override.
5. **Memory Cleanup on Scene Transition:** Switching between Hub Districts and Tactical Multi-Room Dungeons must call `queue_free()` on unloaded zone roots and await one idle frame for ResourceLoader cleanup to stay within 8GB memory budget.
6. **3AM Forced Day Advance:** The `DayCycleManager` must handle the 3AM boundary gracefully — save state, apply fatigue penalty, and transition without data loss even if player is mid-interaction or mid-menu.
7. **Random Combat Event Timing:** `CombatEventManager` must not trigger disruptive events (boss spawn, third-party intervention) during the first 15 seconds of a room or while the roguelike card draft UI is open.

---

### Task 1: Core Architecture, EventBus & Data Resource Definitions

**Files:**
- Create: `scripts/core/EventBus.gd`
- Create: `scripts/data/StudentData.gd`
- Create: `scripts/data/SkillData.gd`
- Create: `scripts/data/ItemData.gd`
- Create: `scripts/data/RecipeData.gd`
- Create: `tests/test_data_models.gd`

**Interfaces:**
- Produces: `EventBus` autoload with signals:
  - `student_bonded(student_id: String, new_level: int)`
  - `ap_changed(current: int, max_ap: int)`
  - `day_advanced(new_day: int, fatigue_penalty: bool)`
  - `mod_loaded(mod_id: String)`
  - `combat_room_cleared(room_index: int)`
  - `item_picked_up(item_id: String, quantity: int)`
  - `combat_event_triggered(event_type: String)`
  - `save_requested()`, `load_requested(slot: int)`
- Produces: `StudentData` resource class:
  - `id: String`, `student_name: String`
  - `role: CombatRole` (enum: TANKER, DAMAGE_DEALER, HEALER, BUFFER)
  - `squad_slot: SquadSlot` (enum: STRIKER, SPECIAL)
  - `normal_model_path: String`, `chibi_model_path: String`
  - `bond_level: int`, `bond_exp: int`
  - `base_hp: int`, `base_atk: int`, `base_def: int`, `base_speed: float`
  - `attack_range: float`, `attack_type: String` (HITSCAN, PROJECTILE)
  - `skills: Array[SkillData]`
  - `favorite_food: String`, `favorite_gift: String`
- Produces: `SkillData` resource: `id`, `name`, `cost: int`, `cooldown: float`, `aoe_radius: float`, `effect_type: String`.
- Produces: `ItemData` resource: `id`, `name`, `type` (enum: GIFT, FOOD, INGREDIENT, MATERIAL, AP_RESTORE), `stack_max: int`, `bond_bonus: int`, `quality: String`.
- Produces: `RecipeData` resource: `id`, `name`, `ingredients: Dictionary` (item_id → quantity), `base_quality_threshold: float`.

- [ ] **Step 1: Write the failing test for StudentData, ItemData, and EventBus**

```gdscript
# tests/test_data_models.gd
extends SceneTree

func _init():
    # Test StudentData
    var student = StudentData.new()
    student.id = "shiroko"
    student.student_name = "Sunaookami Shiroko"
    student.role = StudentData.CombatRole.DAMAGE_DEALER
    student.squad_slot = StudentData.SquadSlot.STRIKER
    student.base_hp = 3200
    student.base_atk = 450
    assert(student.id == "shiroko", "Student ID mismatch")
    assert(student.role == StudentData.CombatRole.DAMAGE_DEALER, "Role mismatch")
    assert(student.base_hp == 3200, "HP mismatch")

    # Test ItemData
    var item = ItemData.new()
    item.id = "yakisoba_bread"
    item.type = ItemData.ItemType.FOOD
    item.bond_bonus = 30
    assert(item.type == ItemData.ItemType.FOOD, "Item type mismatch")

    # Test RecipeData
    var recipe = RecipeData.new()
    recipe.id = "parfait"
    recipe.ingredients = {"milk": 2, "fruit": 3, "sugar": 1}
    assert(recipe.ingredients.size() == 3, "Recipe ingredient count mismatch")

    print("PASS: test_data_models")
    quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s tests/test_data_models.gd`
Expected: FAIL — classes not defined.

- [ ] **Step 3: Implement StudentData, SkillData, ItemData, RecipeData, and EventBus**

`StudentData.gd`: `extends Resource`, `class_name StudentData`, with the enums and exported properties above.
`SkillData.gd`: `extends Resource`, `class_name SkillData`.
`ItemData.gd`: `extends Resource`, `class_name ItemData`, with `enum ItemType`.
`RecipeData.gd`: `extends Resource`, `class_name RecipeData`.
`EventBus.gd`: `extends Node`, all signals listed above with typed parameters.

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s tests/test_data_models.gd`
Expected: PASS.

- [ ] **Step 5: Register EventBus as Autoload in project.godot**

Add `EventBus="*res://scripts/core/EventBus.gd"` under `[autoload]`.

- [ ] **Step 6: Commit**

```bash
git add scripts/core/ scripts/data/ tests/ project.godot
git commit -m "feat(core): add data models (StudentData, SkillData, ItemData, RecipeData) and EventBus autoload"
```

---

### Task 2: Day Cycle Manager & AP System (with 3AM Forced Sleep)

**Files:**
- Create: `scripts/core/DayCycleManager.gd`
- Create: `tests/test_day_cycle.gd`

**Interfaces:**
- Consumes: `EventBus` signals `ap_changed`, `day_advanced`.
- Produces: `DayCycleManager` autoload:
  - `current_day: int`, `current_hour: float` (0.0–24.0), `current_ap: int`, `max_ap: int`
  - `consume_ap(amount: int) -> bool` — returns false if insufficient AP.
  - `restore_ap(amount: int)` — clamp to max_ap.
  - `advance_day()` — reset AP to max, increment day, set hour to morning.
  - `advance_time(hours: float)` — advances clock, triggers forced sleep at 3AM with fatigue penalty.
  - `get_time_of_day() -> String` — returns "MORNING", "AFTERNOON", "EVENING", "NIGHT".
  - `is_forced_sleep_hour() -> bool`

- [ ] **Step 1: Write failing test for AP consumption, day advance, and 3AM forced sleep**

```gdscript
# tests/test_day_cycle.gd
extends SceneTree

func _init():
    var mgr = preload("res://scripts/core/DayCycleManager.gd").new()
    mgr.max_ap = 100
    mgr.current_ap = 100
    mgr.current_hour = 8.0
    mgr.current_day = 1

    # Test AP consumption
    assert(mgr.consume_ap(30) == true, "Should succeed with 100 AP")
    assert(mgr.current_ap == 70, "AP should be 70 after consuming 30")
    assert(mgr.consume_ap(80) == false, "Should fail with only 70 AP")
    assert(mgr.current_ap == 70, "AP should remain 70 after failed consume")

    # Test day advance
    mgr.advance_day()
    assert(mgr.current_day == 2, "Day should advance to 2")
    assert(mgr.current_ap == 100, "AP should fully restore on new day")

    # Test 3AM forced sleep
    mgr.current_hour = 2.5
    mgr.advance_time(1.0)  # reaches 3:30 -> triggers forced sleep
    assert(mgr.current_day == 3, "Forced sleep should advance day")
    assert(mgr.current_hour >= 10.0, "Wake up should be late morning after forced sleep")
    assert(mgr.current_ap < 100, "Fatigue penalty should reduce max AP recovery")

    print("PASS: test_day_cycle")
    quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s tests/test_day_cycle.gd`
Expected: FAIL.

- [ ] **Step 3: Implement DayCycleManager.gd**

`extends Node`. Track `current_hour` as float. `advance_time()` checks if hour crosses 3.0 boundary → triggers `_force_sleep()` which: advances day, sets `current_hour = 10.5` (late morning), applies fatigue penalty (`current_ap = int(max_ap * 0.7)`), emits `EventBus.day_advanced(current_day, true)`. Normal `advance_day()` restores full AP and sets `current_hour = 7.0`, emits `EventBus.day_advanced(current_day, false)`.

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s tests/test_day_cycle.gd`
Expected: PASS.

- [ ] **Step 5: Register DayCycleManager as Autoload and Commit**

Add `DayCycleManager="*res://scripts/core/DayCycleManager.gd"` to `[autoload]`.

```bash
git add scripts/core/DayCycleManager.gd tests/test_day_cycle.gd project.godot
git commit -m "feat(core): implement day cycle with AP system and 3AM forced sleep"
```

---

### Task 3: Save/Load System (SaveManager)

**Files:**
- Create: `scripts/core/SaveManager.gd`
- Create: `tests/test_save_load.gd`

**Interfaces:**
- Consumes: `DayCycleManager`, `StudentData`, `EventBus`.
- Produces: `SaveManager` autoload:
  - `save_game(slot: int) -> bool`
  - `load_game(slot: int) -> bool`
  - `get_save_slots() -> Array[Dictionary]` — returns metadata (slot, day, playtime, timestamp).
  - `delete_save(slot: int) -> bool`
  - `serialize_game_state() -> Dictionary`
  - `deserialize_game_state(data: Dictionary)`

- [ ] **Step 1: Write failing test for serialize/deserialize round-trip**

```gdscript
# tests/test_save_load.gd
extends SceneTree

func _init():
    var save_mgr = preload("res://scripts/core/SaveManager.gd").new()

    # Build mock state
    var state = {
        "day": 5,
        "hour": 14.5,
        "ap": 60,
        "max_ap": 100,
        "credits": 25000,
        "bonds": {"shiroko": 3, "hoshino": 5},
        "inventory": [{"id": "yakisoba_bread", "qty": 2}],
        "current_zone": "schale_office"
    }

    # Serialize to JSON string
    var json_str = save_mgr.state_to_json(state)
    assert(json_str.length() > 0, "Serialized JSON must not be empty")

    # Deserialize back
    var restored = save_mgr.json_to_state(json_str)
    assert(restored.day == 5, "Day must round-trip")
    assert(restored.bonds.shiroko == 3, "Bond data must round-trip")
    assert(restored.inventory[0].id == "yakisoba_bread", "Inventory must round-trip")

    print("PASS: test_save_load")
    quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s tests/test_save_load.gd`
Expected: FAIL.

- [ ] **Step 3: Implement SaveManager.gd**

`extends Node`. Uses `JSON.stringify()` / `JSON.parse_string()` for serialization. Save files stored at `user://saves/slot_N.json`. `save_game()` gathers state from all autoloads (`DayCycleManager`, future `InventoryManager`, bond data from student registry). `load_game()` reads JSON file and distributes state back to autoloads. `get_save_slots()` scans save directory for existing files and reads metadata headers.

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s tests/test_save_load.gd`
Expected: PASS.

- [ ] **Step 5: Register SaveManager as Autoload and Commit**

Add `SaveManager="*res://scripts/core/SaveManager.gd"` to `[autoload]`.

```bash
git add scripts/core/SaveManager.gd tests/test_save_load.gd project.godot
git commit -m "feat(core): implement save/load system with JSON serialization"
```

---

### Task 4: Portable ModLoader Engine (`<game_dir>/mods/`)

**Files:**
- Create: `scripts/core/ModLoader.gd`
- Create: `tests/test_mod_loader.gd`

**Interfaces:**
- Consumes: `StudentData`, `EventBus`.
- Produces: `ModLoader` autoload:
  - `get_mod_root_dir() -> String`
  - `scan_and_load_mods() -> Array[Dictionary]` — returns list of loaded mod metadata.
  - `parse_student_json(json_string: String) -> StudentData`
  - `load_pck_package(path: String) -> bool`
  - `get_loaded_mods() -> Array[Dictionary]`
  - `set_mod_enabled(mod_id: String, enabled: bool)`

- [ ] **Step 1: Write failing test for ModLoader path resolution & JSON parsing**

```gdscript
# tests/test_mod_loader.gd
extends SceneTree

func _init():
    var loader = preload("res://scripts/core/ModLoader.gd").new()

    # Test path resolution
    var mod_dir = loader.get_mod_root_dir()
    assert(mod_dir.ends_with("mods"), "Mod directory should end with 'mods'")

    # Test student JSON parsing
    var json = '{"id":"nonomi","student_name":"Izayoi Nonomi","role":"DAMAGE_DEALER","squad_slot":"STRIKER","base_hp":2800,"base_atk":380,"normal_model_path":"mods/students/nonomi/normal.glb","chibi_model_path":"mods/students/nonomi/chibi.glb"}'
    var student = loader.parse_student_json(json)
    assert(student.id == "nonomi", "Parsed student id must match")
    assert(student.role == StudentData.CombatRole.DAMAGE_DEALER, "Parsed role must match enum")
    assert(student.base_hp == 2800, "Parsed HP must match")

    # Test mod enable/disable tracking
    loader.set_mod_enabled("test_mod", false)
    assert(loader.is_mod_enabled("test_mod") == false, "Disabled mod should return false")

    print("PASS: test_mod_loader")
    quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s tests/test_mod_loader.gd`
Expected: FAIL.

- [ ] **Step 3: Implement ModLoader.gd**

`extends Node`. Path detection: `OS.has_feature("editor") → "res://mods"`, else `OS.get_executable_path().get_base_dir().path_join("mods")`. JSON parser maps string enum names to `StudentData.CombatRole` values. `.pck` loading via `ProjectSettings.load_resource_pack()`. Mod enable/disable state persisted to `user://mod_settings.json`. Graceful fallback: if `normal_model_path` or `chibi_model_path` is empty or file missing, set to `"res://assets/placeholders/placeholder_normal.glb"` or `"res://assets/placeholders/placeholder_chibi.glb"`.

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s tests/test_mod_loader.gd`
Expected: PASS.

- [ ] **Step 5: Register ModLoader as Autoload and Commit**

Add `ModLoader="*res://scripts/core/ModLoader.gd"` to `[autoload]`.

```bash
git add scripts/core/ModLoader.gd tests/test_mod_loader.gd project.godot
git commit -m "feat(modding): implement portable mod loader with JSON parser and PCK support"
```

---

### Task 5: Hub World Sensei 3D Controller (Dual FPS / TPS)

**Files:**
- Create: `scripts/hub/SenseiController.gd`
- Create: `scripts/hub/CameraModeState.gd`
- Create: `scenes/hub/player_sensei.tscn`
- Create: `tests/test_camera_mode.gd`

**Interfaces:**
- Produces: `CameraModeState` pure data class: `enum CameraMode { FPS, TPS }`, `current_mode: CameraMode`, `toggle() -> CameraMode`.
- Produces: `SenseiController` (extends `CharacterBody3D`): WASD movement, Space jump, Shift sprint, V toggle camera, E interact raycast, mouse look.

- [ ] **Step 1: Write failing test for CameraModeState toggle logic**

```gdscript
# tests/test_camera_mode.gd
extends SceneTree

func _init():
    var state = preload("res://scripts/hub/CameraModeState.gd").new()
    assert(state.current_mode == state.CameraMode.TPS, "Default must be TPS")
    var new_mode = state.toggle()
    assert(new_mode == state.CameraMode.FPS, "First toggle must switch to FPS")
    assert(state.current_mode == state.CameraMode.FPS, "State must reflect FPS")
    state.toggle()
    assert(state.current_mode == state.CameraMode.TPS, "Second toggle back to TPS")
    print("PASS: test_camera_mode")
    quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s tests/test_camera_mode.gd`
Expected: FAIL.

- [ ] **Step 3: Implement CameraModeState.gd (pure logic, headless-safe)**

`extends RefCounted`, `class_name CameraModeState`. Contains `enum CameraMode { FPS, TPS }`, `var current_mode := CameraMode.TPS`, `func toggle() -> CameraMode`.

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s tests/test_camera_mode.gd`
Expected: PASS.

- [ ] **Step 5: Implement SenseiController.gd and player_sensei.tscn**

`extends CharacterBody3D`. Scene tree: `CharacterBody3D` → `CollisionShape3D`, `SpringArm3D` (TPS) → `Camera3D`, `Camera3D` (FPS, initially disabled), `RayCast3D` (interact detection, 2m range), `Area3D` (proximity trigger for interactable prompts). Uses `CameraModeState` internally. Input map actions: `move_forward`, `move_back`, `move_left`, `move_right`, `jump`, `sprint`, `interact`, `toggle_camera`. Jolt Physics for CharacterBody3D movement.

- [ ] **Step 6: Commit**

```bash
git add scripts/hub/ scenes/hub/ tests/test_camera_mode.gd
git commit -m "feat(hub): create dual FPS/TPS Sensei controller with CameraModeState"
```

---

### Task 6: Zone Transition System & Interactable Objects

**Files:**
- Create: `scripts/hub/ZoneTransitionManager.gd`
- Create: `scripts/hub/InteractableBase.gd`
- Create: `scripts/hub/SittableChair.gd`
- Create: `scripts/hub/ToggleLight.gd`
- Create: `scripts/hub/PickableItem.gd`
- Create: `scripts/hub/DoorPortal.gd`
- Create: `scenes/hub/loading_screen.tscn`
- Create: `tests/test_interactables.gd`

**Interfaces:**
- Consumes: `EventBus`, `SenseiController.interact_raycast`.
- Produces: `InteractableBase` (extends `Area3D`):
  - `interaction_prompt: String` — text shown to player (e.g. "[E] Sit", "[E] Pick up").
  - `interact()` — virtual method overridden by subclasses.
  - `get_interaction_type() -> String` — "SIT", "TOGGLE", "PICKUP", "DOOR".
- Produces: `PickableItem` (extends `InteractableBase`):
  - `item_data: ItemData`, `quantity: int`.
  - `interact()` → adds item to player inventory, emits `EventBus.item_picked_up`, `queue_free()` self.
- Produces: `DoorPortal` (extends `InteractableBase`):
  - `target_scene_path: String`, `spawn_point_id: String`.
  - `interact()` → triggers `ZoneTransitionManager.transition_to(target_scene_path, spawn_point_id)`.
- Produces: `ZoneTransitionManager` autoload:
  - `transition_to(scene_path: String, spawn_id: String)` — fade-out, show loading screen with tips/art, `change_scene_to_packed()`, fade-in.
  - `register_spawn_point(id: String, position: Vector3)`

- [ ] **Step 1: Write failing test for InteractableBase, PickableItem, and DoorPortal**

```gdscript
# tests/test_interactables.gd
extends SceneTree

func _init():
    # Test PickableItem
    var pickup = preload("res://scripts/hub/PickableItem.gd").new()
    var item = ItemData.new()
    item.id = "energy_drink"
    item.type = ItemData.ItemType.AP_RESTORE
    item.stack_max = 10
    pickup.item_data = item
    pickup.quantity = 3
    assert(pickup.get_interaction_type() == "PICKUP", "Must be PICKUP type")
    assert(pickup.interaction_prompt == "[E] Pick up", "Prompt must match")

    # Test DoorPortal
    var door = preload("res://scripts/hub/DoorPortal.gd").new()
    door.target_scene_path = "res://scenes/hub/zones/abydos_academy.tscn"
    door.spawn_point_id = "entrance_a"
    assert(door.get_interaction_type() == "DOOR", "Must be DOOR type")

    # Test SittableChair
    var chair = preload("res://scripts/hub/SittableChair.gd").new()
    assert(chair.get_interaction_type() == "SIT", "Must be SIT type")

    print("PASS: test_interactables")
    quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s tests/test_interactables.gd`
Expected: FAIL.

- [ ] **Step 3: Implement InteractableBase, PickableItem, DoorPortal, SittableChair, ToggleLight**

`InteractableBase.gd`: `extends Area3D`, `class_name InteractableBase`. Virtual `interact()`, `get_interaction_type()`, exported `interaction_prompt`.
`PickableItem.gd`: On `interact()`, emits `EventBus.item_picked_up(item_data.id, quantity)` and self-destructs.
`SittableChair.gd`: On `interact()`, moves player to seat position and plays sit animation.
`ToggleLight.gd`: On `interact()`, toggles `OmniLight3D.visible`.
`DoorPortal.gd`: On `interact()`, calls `ZoneTransitionManager.transition_to()`.

- [ ] **Step 4: Implement ZoneTransitionManager.gd and loading_screen.tscn**

`extends Node` autoload. `transition_to()`: fades screen via `AnimationPlayer` on `CanvasLayer`, loads target scene via `ResourceLoader.load_threaded_request()` for async loading, displays loading screen with random tips and BA art, fades in after scene swap. Registers spawn points via marker nodes (`Marker3D` with metadata).

- [ ] **Step 5: Run test to verify it passes**

Run: `godot --headless -s tests/test_interactables.gd`
Expected: PASS.

- [ ] **Step 6: Register ZoneTransitionManager as Autoload and Commit**

Add `ZoneTransitionManager="*res://scripts/hub/ZoneTransitionManager.gd"` to `[autoload]`.

```bash
git add scripts/hub/ scenes/hub/ tests/test_interactables.gd project.godot
git commit -m "feat(hub): add zone transition system, interactable objects (sit, toggle, pickup, door)"
```

---

### Task 7: Student Intimacy & Direct Gesture Minigame

**Files:**
- Create: `scripts/intimacy/IntimacyManager.gd`
- Create: `scripts/intimacy/GestureReceiver.gd`
- Create: `scripts/intimacy/BondProgressTracker.gd`
- Create: `scenes/intimacy/intimacy_viewport.tscn`
- Create: `tests/test_gesture_logic.gd`

**Interfaces:**
- Consumes: `StudentData`, `EventBus`, `ItemData`.
- Produces: `GestureReceiver`:
  - `register_stroke(delta: Vector2)` — accumulates mouse movement data.
  - `get_headpat_satisfaction() -> float` — 0.0 to 1.0 based on stroke pattern quality.
  - `get_cheek_pinch_offset() -> float` — displacement amount for blendshape.
  - `register_feed(item: ItemData) -> Dictionary` — returns `{accepted: bool, bond_bonus: int, reaction: String}`.
  - `reset()`
  - Signals: `headpat_completed(satisfaction: float)`, `cheek_pinched(offset: float)`, `food_fed(item_id: String, reaction: String)`
- Produces: `BondProgressTracker`:
  - `MAX_BOND_LEVEL: int = 100`
  - `DEFAULT_QUEST_GATE_LEVELS: Array[int] = [5, 10, 15, 20]` (only gated up to level 20 by default; extensible for >20 via `register_quest_gate(student_id, level)`).
  - `add_bond_exp(student_id: String, amount: int)` — handles level-up thresholds up to `MAX_BOND_LEVEL`, pausing level-up at a gate level until `complete_bond_quest_gate(student_id, level)` is called.
  - `is_bond_gate_locked(student_id: String) -> bool`
  - `complete_bond_quest_gate(student_id: String, level: int)`
  - `get_bond_level(student_id: String) -> int`
  - `get_bond_exp(student_id: String) -> int`
  - `get_level_up_threshold(level: int) -> int`

- [ ] **Step 1: Write failing test for gesture stroke logic and bond progression**

```gdscript
# tests/test_gesture_logic.gd
extends SceneTree

func _init():
    # Test GestureReceiver headpat
    var receiver = preload("res://scripts/intimacy/GestureReceiver.gd").new()
    receiver.register_stroke(Vector2(15, 0))
    receiver.register_stroke(Vector2(-15, 0))
    receiver.register_stroke(Vector2(12, 0))
    assert(receiver.get_headpat_satisfaction() > 0.0, "Back-and-forth strokes must build satisfaction")

    # Test cheek pinch
    receiver.reset()
    receiver.register_stroke(Vector2(8, 3))  # pulling motion
    assert(receiver.get_cheek_pinch_offset() > 0.0, "Pull motion must generate pinch offset")

    # Test feeding
    var food = ItemData.new()
    food.id = "parfait"
    food.type = ItemData.ItemType.FOOD
    food.bond_bonus = 50
    var result = receiver.register_feed(food)
    assert(result.accepted == true, "Food item must be accepted")
    assert(result.bond_bonus == 50, "Bond bonus must match food item")

    # Test BondProgressTracker
    var tracker = preload("res://scripts/intimacy/BondProgressTracker.gd").new()
    tracker.add_bond_exp("shiroko", 80)
    assert(tracker.get_bond_exp("shiroko") == 80, "Bond EXP must accumulate")
    assert(tracker.get_bond_level("shiroko") == 0, "Should not level up yet")
    tracker.add_bond_exp("shiroko", 120)  # total 200, threshold for level 1 = 100
    assert(tracker.get_bond_level("shiroko") >= 1, "Should have leveled up")

    print("PASS: test_gesture_logic")
    quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s tests/test_gesture_logic.gd`
Expected: FAIL.

- [ ] **Step 3: Implement GestureReceiver.gd and BondProgressTracker.gd**

`GestureReceiver.gd`: `extends RefCounted`. Tracks stroke history (last N deltas), detects back-and-forth pattern for headpats (direction reversal count), calculates pull magnitude for cheek pinch. Feeding checks `ItemData.type == FOOD`.
`BondProgressTracker.gd`: `extends RefCounted`. Internal dictionary `_bonds: Dictionary` mapping `student_id` → `{exp: int, level: int}`. Level thresholds: `level * 100 + 50` (level 1 = 100, level 2 = 250, etc.). On level-up emits `EventBus.student_bonded`.

- [ ] **Step 4: Implement IntimacyManager.gd and intimacy_viewport.tscn**

`IntimacyManager.gd`: `extends Node`. Manages camera transition to close-up portrait view (smooth lerp to `Marker3D` position on student face). Swaps mouse cursor to hand sprite. Creates 3 `Area3D` collision zones on student model (head top, left cheek, right cheek, mouth). Routes mouse input through raycasts to `GestureReceiver`. Drives blendshapes (`eye_smile`, `cheek_puff`, `mouth_open`, `blush`) via `MeshInstance3D.set("blend_shapes/name", value)`. Spawns particle effects (hearts, sparkles). Plays voice clips from student's audio folder.

- [ ] **Step 5: Run test to verify it passes**

Run: `godot --headless -s tests/test_gesture_logic.gd`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add scripts/intimacy/ scenes/intimacy/ tests/test_gesture_logic.gd
git commit -m "feat(intimacy): implement gesture receiver, bond tracker, and intimacy camera system"
```

---

### Task 8: Cooking Minigame System (Relaxed Pace)

**Files:**
- Create: `scripts/minigames/CookingManager.gd`
- Create: `scripts/minigames/CookingStation.gd`
- Create: `scripts/minigames/IngredientPrepStep.gd`
- Create: `scenes/minigames/cooking_station.tscn`
- Create: `tests/test_cooking_system.gd`

**Interfaces:**
- Consumes: `ItemData`, `RecipeData`, `EventBus`.
- Produces: `CookingManager`:
  - `start_recipe(recipe: RecipeData) -> bool` — checks inventory for ingredients.
  - `complete_prep_step(step_index: int, quality: float)` — records quality of each prep action.
  - `get_cooking_indicator_position() -> float` — returns 0.0–1.0 oscillating indicator for final cook phase.
  - `finalize_cook() -> ItemData` — locks in final quality based on indicator position at moment of press.
  - `calculate_dish_quality(prep_scores: Array[float], cook_timing: float) -> String` — returns "NORMAL", "GOOD", "PERFECT".
- Produces: `IngredientPrepStep`:
  - `prep_type: String` — "CHOP", "SLICE", "STIR", "SEASON", "KNEAD".
  - `target_count: int` — number of actions needed (e.g. 8 chops).
  - `current_count: int`
  - `perform_action() -> float` — returns quality score 0.0–1.0 per action.

- [ ] **Step 1: Write failing test for relaxed prep steps and final cook timing**

```gdscript
# tests/test_cooking_system.gd
extends SceneTree

func _init():
    var cooking = preload("res://scripts/minigames/CookingManager.gd").new()

    # Test ingredient prep step (relaxed, no timer)
    var prep = preload("res://scripts/minigames/IngredientPrepStep.gd").new()
    prep.prep_type = "CHOP"
    prep.target_count = 5
    for i in range(5):
        prep.perform_action()
    assert(prep.current_count == 5, "All chops must register")
    assert(prep.is_complete(), "Prep step must be complete after target_count actions")

    # Test final dish quality calculation
    var prep_scores = [0.9, 0.85, 0.95]  # quality from each prep step
    var cook_timing = 0.92  # close to sweet spot

    var quality = cooking.calculate_dish_quality(prep_scores, cook_timing)
    assert(quality == "PERFECT", "High prep + good timing = PERFECT")

    var low_quality = cooking.calculate_dish_quality([0.4, 0.5, 0.3], 0.2)
    assert(low_quality == "NORMAL", "Low scores = NORMAL quality")

    # Test dish output
    var dish = cooking.create_dish_item("parfait", "PERFECT")
    assert(dish.type == ItemData.ItemType.FOOD, "Dish must be FOOD type")
    assert(dish.bond_bonus >= 50, "PERFECT dish must have high bond bonus")
    assert(dish.quality == "PERFECT", "Quality label must match")

    print("PASS: test_cooking_system")
    quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s tests/test_cooking_system.gd`
Expected: FAIL.

- [ ] **Step 3: Implement IngredientPrepStep.gd**

`extends RefCounted`. No timer — player performs actions (click to chop, drag to stir) at their own pace. Each action increments `current_count` and calculates individual quality based on input precision (e.g., chop rhythm consistency, stir circle completeness). `is_complete()` returns `current_count >= target_count`.

- [ ] **Step 4: Implement CookingManager.gd**

`extends RefCounted`. Recipe flow: 1) Verify ingredients in inventory, deduct them. 2) Present prep steps sequentially (CHOP vegetables, SEASON meat — no time pressure). 3) Final cook phase: oscillating indicator bar (sine wave, speed varies by recipe difficulty). Player presses action button to stop indicator — closer to center = higher cook_timing score. `calculate_dish_quality()`: average prep scores × 0.6 + cook_timing × 0.4 → thresholds: ≥0.85 PERFECT, ≥0.6 GOOD, else NORMAL. `create_dish_item()` returns new `ItemData` with bond_bonus scaled by quality (NORMAL=15, GOOD=30, PERFECT=50+).

- [ ] **Step 5: Implement CookingStation.gd and cooking_station.tscn**

`CookingStation.gd` extends `InteractableBase`. Scene: 3D kitchen counter with cutting board, pot, ingredients display. UI overlay for prep actions and final cook indicator bar. Camera shifts to fixed kitchen view. Ambient cooking sounds (sizzling, chopping).

- [ ] **Step 6: Run test to verify it passes**

Run: `godot --headless -s tests/test_cooking_system.gd`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add scripts/minigames/ scenes/minigames/ tests/test_cooking_system.gd
git commit -m "feat(minigame): implement relaxed cooking system with prep steps and cook timing indicator"
```

---

### Task 9: Chibi Tactical RTS Camera & Unit Micro-Controls

**Files:**
- Create: `scripts/combat/RTSCamera3D.gd`
- Create: `scripts/combat/UnitSelectionManager.gd`
- Create: `scripts/combat/SelectionMath.gd`
- Create: `scenes/combat/combat_camera.tscn`
- Create: `tests/test_rts_selection.gd`

**Interfaces:**
- Produces: `RTSCamera3D` (extends `Camera3D`): isometric pan (WASD / edge scroll), rotate (middle-mouse drag / Q/E keys), zoom (scroll wheel), clamped within arena bounds.
- Produces: `SelectionMath` (pure logic, extends `RefCounted`):
  - `is_point_in_rect(point: Vector2, rect: Rect2) -> bool`
  - `normalize_selection_rect(start: Vector2, end: Vector2) -> Rect2` — handles any drag direction.
- Produces: `UnitSelectionManager`:
  - `selected_units: Array[Node3D]`
  - `select_unit(unit: Node3D)`, `deselect_all()`
  - `box_select(screen_rect: Rect2, camera: Camera3D, units: Array[Node3D])` — projects 3D positions to screen and tests containment.
  - `issue_move_order(target: Vector3)` — dispatched to all selected units.
  - `issue_cover_order(cover_point: Node3D)`
  - `issue_focus_fire(enemy: Node3D)`
  - `issue_hold_position()`, `issue_hold_fire()`

- [ ] **Step 1: Write failing test for SelectionMath and UnitSelectionManager logic**

```gdscript
# tests/test_rts_selection.gd
extends SceneTree

func _init():
    # Test SelectionMath
    var math = preload("res://scripts/combat/SelectionMath.gd").new()
    var rect = math.normalize_selection_rect(Vector2(150, 150), Vector2(50, 50))
    assert(rect.position == Vector2(50, 50), "Rect must normalize to top-left origin")
    assert(rect.size == Vector2(100, 100), "Rect size must be positive")
    assert(math.is_point_in_rect(Vector2(100, 100), rect) == true, "Center point must be inside")
    assert(math.is_point_in_rect(Vector2(200, 200), rect) == false, "Outside point must fail")

    # Test UnitSelectionManager
    var mgr = preload("res://scripts/combat/UnitSelectionManager.gd").new()
    var mock_unit_a = Node3D.new()
    mock_unit_a.name = "Shiroko"
    var mock_unit_b = Node3D.new()
    mock_unit_b.name = "Hoshino"
    mgr.select_unit(mock_unit_a)
    assert(mgr.selected_units.size() == 1, "One unit selected")
    mgr.select_unit(mock_unit_b)
    assert(mgr.selected_units.size() == 2, "Two units selected")
    mgr.deselect_all()
    assert(mgr.selected_units.size() == 0, "All deselected")

    mock_unit_a.free()
    mock_unit_b.free()

    print("PASS: test_rts_selection")
    quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s tests/test_rts_selection.gd`
Expected: FAIL.

- [ ] **Step 3: Implement SelectionMath.gd (pure math, headless-safe)**

`extends RefCounted`, `class_name SelectionMath`. Pure geometric helpers.

- [ ] **Step 4: Implement UnitSelectionManager.gd**

`extends Node`. Manages `selected_units` array. `box_select()` iterates units, projects each `global_position` via `camera.unproject_position()`, tests `SelectionMath.is_point_in_rect()`. Order methods set `target_position`, `target_cover`, `target_enemy` on each selected unit's data, and set `has_player_order = true`.

- [ ] **Step 5: Implement RTSCamera3D.gd and combat_camera.tscn**

Isometric camera rig: `Node3D` pivot → `Camera3D` at 45° pitch, 35.264° yaw (true isometric). Pan: WASD or mouse at screen edges. Rotate: Q/E or middle-mouse. Zoom: scroll wheel clamped between 5m–25m from pivot. Selection box overlay: `Control` node draws `Rect2` with `_draw()` during left-mouse drag.

- [ ] **Step 6: Run test to verify it passes**

Run: `godot --headless -s tests/test_rts_selection.gd`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add scripts/combat/ scenes/combat/ tests/test_rts_selection.gd
git commit -m "feat(combat): implement isometric RTS camera, selection math, and unit micro controls"
```

---

### Task 10: Combat Unit Base, Stats & Damage Resolution

**Files:**
- Create: `scripts/combat/CombatUnit.gd`
- Create: `scripts/combat/DamageResolver.gd`
- Create: `scripts/combat/ProjectileManager.gd`
- Create: `tests/test_combat_damage.gd`

**Interfaces:**
- Consumes: `StudentData`, `SkillData`.
- Produces: `CombatUnit` (extends `CharacterBody3D`):
  - `unit_data: StudentData` (source stats)
  - `current_hp: int`, `max_hp: int`, `atk: int`, `def: int`, `speed: float`, `attack_range: float`
  - `is_alive: bool`
  - `has_player_order: bool` — when true, Role AI yields to player command.
  - `take_damage(amount: int, source: CombatUnit)` — applies defense formula, emits signal.
  - `heal(amount: int)`
  - `die()` — plays death animation, disables collider.
  - Signals: `hp_changed(current, max_val)`, `unit_died(unit)`, `order_completed()`
- Produces: `DamageResolver`:
  - `calculate_damage(attacker: CombatUnit, defender: CombatUnit) -> int` — formula: `max(1, attacker.atk - defender.def * 0.5) * random_range(0.9, 1.1)`.
  - `apply_buff_modifiers(base_damage: int, active_buffs: Array) -> int`
- Produces: `ProjectileManager` (extends `Node`):
  - `spawn_projectile(origin: Vector3, target: Vector3, speed: float, damage: int, source: CombatUnit)`
  - `spawn_hitscan(origin: Vector3, target: CombatUnit, damage: int, source: CombatUnit)` — instant raycast hit.

- [ ] **Step 1: Write failing test for damage formula and unit HP management**

```gdscript
# tests/test_combat_damage.gd
extends SceneTree

func _init():
    var resolver = preload("res://scripts/combat/DamageResolver.gd").new()

    # Test damage calculation
    var attacker_data = {"atk": 500}
    var defender_data = {"def": 200}
    var dmg = resolver.calculate_damage_raw(attacker_data.atk, defender_data.def)
    assert(dmg >= 360, "Damage must be at least floor value (500 - 200*0.5)*0.9 = 360")
    assert(dmg <= 440, "Damage must be at most ceiling value (500 - 200*0.5)*1.1 = 440")

    # Test buff modifier
    var buffed = resolver.apply_buff_modifiers(400, [{"type": "ATK_UP", "value": 0.2}])
    assert(buffed == 480, "20% ATK_UP on 400 = 480")

    # Test zero/negative defense edge case
    var high_def_dmg = resolver.calculate_damage_raw(100, 300)
    assert(high_def_dmg >= 1, "Damage must never go below 1")

    print("PASS: test_combat_damage")
    quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s tests/test_combat_damage.gd`
Expected: FAIL.

- [ ] **Step 3: Implement DamageResolver.gd (pure math, headless-safe)**

`extends RefCounted`. `calculate_damage_raw(atk: int, def: int) -> int`: `max(1, int((atk - def * 0.5) * randf_range(0.9, 1.1)))`. `apply_buff_modifiers()` iterates buff array and stacks multiplicative/additive modifiers.

- [ ] **Step 4: Implement CombatUnit.gd**

`extends CharacterBody3D`. Initializes stats from `StudentData` on `setup(data: StudentData)`. `take_damage()` calls `DamageResolver`, subtracts from `current_hp`, emits `hp_changed`, triggers `die()` at 0. `has_player_order` flag checked by Role AI — when true, AI skips its `evaluate_action()` until `order_completed` signal fires.

- [ ] **Step 5: Implement ProjectileManager.gd**

`extends Node`. Object pool pattern for projectile instances. `spawn_projectile()`: instantiates `Area3D` with `CollisionShape3D` (sphere), moves toward target at speed, on collision calls `target.take_damage()`. `spawn_hitscan()`: immediate raycast, instant damage application, visual tracer effect via `ImmediateMesh` or `Line2D` overlay.

- [ ] **Step 6: Run test to verify it passes**

Run: `godot --headless -s tests/test_combat_damage.gd`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add scripts/combat/CombatUnit.gd scripts/combat/DamageResolver.gd scripts/combat/ProjectileManager.gd tests/test_combat_damage.gd
git commit -m "feat(combat): implement combat unit base, damage resolver, and projectile manager"
```

---

### Task 11: Combat Role AIs (Tanker, DPS, Healer, Buffer) & Cover Grid

**Files:**
- Create: `scripts/combat/ai/RoleAIBase.gd`
- Create: `scripts/combat/ai/TankerAI.gd`
- Create: `scripts/combat/ai/DamageDealerAI.gd`
- Create: `scripts/combat/ai/HealerAI.gd`
- Create: `scripts/combat/ai/BufferAI.gd`
- Create: `scripts/combat/CoverPoint3D.gd`
- Create: `tests/test_role_ai_decisions.gd`

**Interfaces:**
- Consumes: `CombatUnit`, `CoverPoint3D`, `NavigationAgent3D`.
- Produces: `RoleAIBase` (extends `Node`):
  - `evaluate_action(owner: CombatUnit, allies: Array, enemies: Array, covers: Array) -> Dictionary` — returns `{action: String, target: Variant, priority: float}`.
  - `should_yield_to_player(owner: CombatUnit) -> bool` — returns `owner.has_player_order`.
- Produces: `CoverPoint3D` (extends `Marker3D`):
  - `cover_type: CoverType` (enum: HALF, FULL)
  - `is_occupied: bool`, `occupant: CombatUnit`
  - `get_cover_direction() -> Vector3` — the direction this cover protects from.
  - `claim(unit: CombatUnit)`, `release()`

- [ ] **Step 1: Write failing test for role-specific AI decision logic**

```gdscript
# tests/test_role_ai_decisions.gd
extends SceneTree

func _init():
    # Test Healer AI target selection
    var healer_ai = preload("res://scripts/combat/ai/HealerAI.gd").new()
    var low_hp = {"name": "Hoshino", "hp_percent": 0.2, "is_alive": true}
    var full_hp = {"name": "Shiroko", "hp_percent": 1.0, "is_alive": true}
    var dead = {"name": "Nonomi", "hp_percent": 0.0, "is_alive": false}
    var target = healer_ai.pick_heal_target([full_hp, low_hp, dead])
    assert(target.name == "Hoshino", "Healer must prioritize lowest HP living ally")

    # Test Tanker AI cover preference
    var tanker_ai = preload("res://scripts/combat/ai/TankerAI.gd").new()
    var front_cover = {"distance_to_enemy": 5.0, "cover_type": "FULL", "is_occupied": false}
    var rear_cover = {"distance_to_enemy": 15.0, "cover_type": "FULL", "is_occupied": false}
    var chosen = tanker_ai.pick_cover_point([rear_cover, front_cover])
    assert(chosen.distance_to_enemy == 5.0, "Tanker must pick cover closest to enemies")

    # Test DPS AI target priority
    var dps_ai = preload("res://scripts/combat/ai/DamageDealerAI.gd").new()
    var tough_enemy = {"name": "Boss", "hp_percent": 0.9, "is_pinged": false}
    var weak_enemy = {"name": "Grunt", "hp_percent": 0.15, "is_pinged": false}
    var pinged_enemy = {"name": "Elite", "hp_percent": 0.5, "is_pinged": true}
    var dps_target = dps_ai.pick_attack_target([tough_enemy, weak_enemy, pinged_enemy])
    assert(dps_target.name == "Elite", "DPS must prioritize pinged target over low HP")

    # Test Buffer AI positioning
    var buffer_ai = preload("res://scripts/combat/ai/BufferAI.gd").new()
    var ally_positions = [Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(2, 0, 3)]
    var centroid = buffer_ai.calculate_optimal_position(ally_positions, 5.0)
    assert(centroid.distance_to(Vector3(2, 0, 1)) < 1.5, "Buffer should position near ally centroid")

    # Test player order yielding
    var base_ai = preload("res://scripts/combat/ai/RoleAIBase.gd").new()
    var mock_owner = {"has_player_order": true}
    assert(base_ai.should_yield_to_player_dict(mock_owner) == true, "AI must yield when player order active")

    print("PASS: test_role_ai_decisions")
    quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s tests/test_role_ai_decisions.gd`
Expected: FAIL.

- [ ] **Step 3: Implement CoverPoint3D.gd**

`extends Marker3D`, `class_name CoverPoint3D`. `enum CoverType { HALF, FULL }`. Exported `cover_type`, `cover_direction: Vector3`. `claim(unit)` sets `is_occupied = true`, `occupant = unit`. `release()` clears both. Visual debug gizmo in editor showing cover direction arrow.

- [ ] **Step 4: Implement RoleAIBase.gd and the 4 Role AI subclasses**

`RoleAIBase.gd`: `extends Node`. Virtual `evaluate_action()`. `should_yield_to_player()` checks `owner.has_player_order`.
`TankerAI.gd`: Sorts covers by proximity to nearest enemy (ascending), claims forward cover, activates taunt/aggro aura.
`DamageDealerAI.gd`: Prioritizes pinged targets first, then lowest HP enemies. Seeks cover with clear line of sight to target.
`HealerAI.gd`: Filters alive allies, sorts by `hp_percent` ascending, heals lowest. Stays behind Tanker cover, seeks rear-most available cover.
`BufferAI.gd`: Calculates centroid of allied positions, moves to position that maximizes allies within `aura_radius`. Applies buffs to allies in range, debuffs to enemies in range.

- [ ] **Step 5: Run test to verify it passes**

Run: `godot --headless -s tests/test_role_ai_decisions.gd`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add scripts/combat/ai/ scripts/combat/CoverPoint3D.gd tests/test_role_ai_decisions.gd
git commit -m "feat(combat): implement cover grid and 4 role AIs (Tanker, DPS, Healer, Buffer)"
```

---

### Task 12: Enemy System, Wave Spawner & Random Combat Events

**Files:**
- Create: `scripts/combat/EnemyUnit.gd`
- Create: `scripts/combat/EnemyAI.gd`
- Create: `scripts/combat/WaveSpawner.gd`
- Create: `scripts/combat/CombatEventManager.gd`
- Create: `tests/test_enemy_and_events.gd`

**Interfaces:**
- Consumes: `CombatUnit`, `DamageResolver`, `EventBus`.
- Produces: `EnemyUnit` (extends `CombatUnit`):
  - `enemy_type: String` — "GRUNT", "ELITE", "BOSS".
  - `behavior: String` — "AGGRESSIVE", "DEFENSIVE", "PATROL".
  - `loot_table: Array[Dictionary]` — items dropped on death.
- Produces: `EnemyAI` (extends `Node`):
  - `evaluate(owner: EnemyUnit, player_units: Array) -> Dictionary` — returns action based on behavior type.
  - AGGRESSIVE: rushes nearest player unit. DEFENSIVE: holds position and shoots. PATROL: walks waypoints until detecting player unit in range.
- Produces: `WaveSpawner`:
  - `start_wave(wave_index: int, spawn_points: Array[Marker3D])` — instantiates enemies from wave definition.
  - `is_wave_complete() -> bool` — all enemies dead.
  - `get_current_wave() -> int`
- Produces: `CombatEventManager`:
  - `check_for_random_event(elapsed_time: float, room_index: int) -> Dictionary` — may return null or an event.
  - `trigger_event(event: Dictionary)` — executes the event.
  - Event types:
    - `"ALLY_ARTILLERY"`: Friendly bombardment on random enemy cluster, deals AOE damage.
    - `"HIDDEN_BOSS"`: Spawns a mini-boss mid-room unexpectedly.
    - `"THIRD_PARTY"`: Spawns a hostile third faction that attacks both player and enemies.
  - Constraints: No events during first 15 seconds of room, no events while card draft UI is open.
  - Event chance increases as room_index increases (later rooms = more surprises).

- [ ] **Step 1: Write failing test for enemy AI, wave completion, and event system**

```gdscript
# tests/test_enemy_and_events.gd
extends SceneTree

func _init():
    # Test EnemyAI behavior selection
    var enemy_ai = preload("res://scripts/combat/EnemyAI.gd").new()
    var aggressive_enemy = {"behavior": "AGGRESSIVE", "attack_range": 10.0}
    var nearby_target = {"position": Vector3(5, 0, 0)}
    var action = enemy_ai.evaluate_simple(aggressive_enemy, [nearby_target])
    assert(action.action == "RUSH", "Aggressive enemy must rush nearest target")

    var defensive_enemy = {"behavior": "DEFENSIVE", "attack_range": 15.0}
    var far_target = {"position": Vector3(12, 0, 0)}
    var def_action = enemy_ai.evaluate_simple(defensive_enemy, [far_target])
    assert(def_action.action == "HOLD_AND_SHOOT", "Defensive enemy must hold position")

    # Test WaveSpawner completion tracking
    var spawner = preload("res://scripts/combat/WaveSpawner.gd").new()
    spawner.register_enemy_count(3)
    assert(spawner.is_wave_complete() == false, "Wave not complete with 3 alive")
    spawner.register_enemy_killed()
    spawner.register_enemy_killed()
    spawner.register_enemy_killed()
    assert(spawner.is_wave_complete() == true, "Wave complete when all killed")

    # Test CombatEventManager
    var event_mgr = preload("res://scripts/combat/CombatEventManager.gd").new()
    var early_event = event_mgr.check_for_random_event(5.0, 1, false)
    assert(early_event == null, "No events in first 15 seconds")
    # Note: random events are probabilistic — test the constraint, not the roll
    var late_check = event_mgr.check_for_random_event(60.0, 5, false)
    # late_check may or may not trigger — just verify it doesn't crash
    assert(late_check == null or late_check.has("type"), "Event must be null or have type key")

    print("PASS: test_enemy_and_events")
    quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s tests/test_enemy_and_events.gd`
Expected: FAIL.

- [ ] **Step 3: Implement EnemyUnit.gd and EnemyAI.gd**

`EnemyUnit.gd`: `extends CombatUnit` (from Task 10). Adds `enemy_type`, `behavior`, `loot_table`. On `die()`: rolls loot table, emits items.
`EnemyAI.gd`: `extends Node`. State machine: PATROL → ALERT (detected player) → ENGAGE. AGGRESSIVE: `NavigationAgent3D` pathfinds to nearest player unit. DEFENSIVE: stays at spawn, shoots if in range. PATROL: follows `Path3D` waypoints until detection range triggered.

- [ ] **Step 4: Implement WaveSpawner.gd**

`extends Node`. Wave definitions as Array of Dictionaries (`{enemy_scene, count, spawn_delay, behavior}`). `start_wave()` instantiates enemies at spawn points with staggered `Timer`. Tracks alive count via `unit_died` signal connections. `is_wave_complete()` returns `alive_count == 0`.

- [ ] **Step 5: Implement CombatEventManager.gd**

`extends Node`. `check_for_random_event(elapsed, room_index, is_draft_open)`: if `elapsed < 15.0` or `is_draft_open`, return null. Base chance: `0.02 * room_index` per check (called every 10 seconds). Event pool weighted by room difficulty. `ALLY_ARTILLERY`: spawns AOE damage circle on enemy cluster after 2-second warning indicator. `HIDDEN_BOSS`: instantiates boss enemy at room edge with dramatic camera shake. `THIRD_PARTY`: spawns hostile faction (3–5 units) that target both sides using AGGRESSIVE AI.

- [ ] **Step 6: Run test to verify it passes**

Run: `godot --headless -s tests/test_enemy_and_events.gd`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add scripts/combat/EnemyUnit.gd scripts/combat/EnemyAI.gd scripts/combat/WaveSpawner.gd scripts/combat/CombatEventManager.gd tests/test_enemy_and_events.gd
git commit -m "feat(combat): implement enemy system, wave spawner, and random combat events"
```

---

### Task 13: EX-Skill System, Cost Bar & Special Support Slots

**Files:**
- Create: `scripts/combat/EXSkillSystem.gd`
- Create: `scripts/combat/CostBarManager.gd`
- Create: `scripts/combat/SkillTargetingOverlay.gd`
- Create: `tests/test_ex_skill.gd`

**Interfaces:**
- Consumes: `SkillData`, `CombatUnit`, `EventBus`.
- Produces: `CostBarManager`:
  - `current_cost: float`, `max_cost: float`
  - `accumulate(delta: float)` — passive Cost generation per second.
  - `spend(amount: float) -> bool` — returns false if insufficient.
  - `get_fill_percent() -> float`
- Produces: `EXSkillSystem`:
  - `special_slots: Array[StudentData]` — 2 Special students providing skills.
  - `get_available_skills() -> Array[SkillData]` — skills with cost ≤ current_cost.
  - `activate_skill(skill: SkillData, target_position: Vector3) -> bool`
  - `is_skill_on_cooldown(skill: SkillData) -> bool`
- Produces: `SkillTargetingOverlay` (extends `Control`):
  - `begin_targeting(skill: SkillData)` — shows AOE radius circle on ground plane.
  - `confirm_target(screen_pos: Vector2, camera: Camera3D) -> Vector3` — raycasts to ground, returns world position.
  - `cancel_targeting()`

- [ ] **Step 1: Write failing test for Cost bar and skill activation**

```gdscript
# tests/test_ex_skill.gd
extends SceneTree

func _init():
    # Test CostBarManager
    var cost_bar = preload("res://scripts/combat/CostBarManager.gd").new()
    cost_bar.max_cost = 10.0
    cost_bar.current_cost = 0.0
    cost_bar.accumulate(5.0)  # simulate 5 seconds of generation
    assert(cost_bar.current_cost > 0.0, "Cost must accumulate over time")

    cost_bar.current_cost = 4.0
    assert(cost_bar.spend(3.0) == true, "Should succeed spending 3 with 4 available")
    assert(abs(cost_bar.current_cost - 1.0) < 0.01, "Should have 1.0 remaining")
    assert(cost_bar.spend(5.0) == false, "Should fail spending 5 with 1 available")

    # Test EXSkillSystem
    var ex_sys = preload("res://scripts/combat/EXSkillSystem.gd").new()
    var heal_skill = SkillData.new()
    heal_skill.id = "heal_aoe"
    heal_skill.cost = 3
    heal_skill.cooldown = 10.0
    heal_skill.aoe_radius = 5.0

    ex_sys.register_skill(heal_skill)
    cost_bar.current_cost = 5.0
    ex_sys.cost_bar = cost_bar

    var available = ex_sys.get_available_skills()
    assert(available.size() >= 1, "Heal skill should be available at 5.0 cost")

    var activated = ex_sys.activate_skill(heal_skill, Vector3(10, 0, 5))
    assert(activated == true, "Skill activation must succeed")
    assert(ex_sys.is_skill_on_cooldown(heal_skill) == true, "Skill must be on cooldown after use")
    assert(abs(cost_bar.current_cost - 2.0) < 0.01, "Cost should be deducted")

    print("PASS: test_ex_skill")
    quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s tests/test_ex_skill.gd`
Expected: FAIL.

- [ ] **Step 3: Implement CostBarManager.gd**

`extends RefCounted`. `accumulate(delta)`: `current_cost = min(max_cost, current_cost + generation_rate * delta)`, default `generation_rate = 0.5` per second. `spend()` checks sufficiency, deducts, returns bool. `get_fill_percent()` returns `current_cost / max_cost`.

- [ ] **Step 4: Implement EXSkillSystem.gd**

`extends Node`. Holds reference to `CostBarManager`. Manages `special_slots` (2 `StudentData` entries). `register_skill()` adds to available pool. `activate_skill()`: checks cooldown, checks cost, deducts cost, starts cooldown timer (`Timer` node per skill), spawns skill effect at `target_position` (AOE heal circle, artillery strike, buff zone). `get_available_skills()`: filters by cost ≤ current and not on cooldown.

- [ ] **Step 5: Implement SkillTargetingOverlay.gd**

`extends Control`. When `begin_targeting(skill)`: draws translucent circle decal on ground plane matching `skill.aoe_radius`, follows mouse cursor via raycast to `PhysicsDirectSpaceState3D` ground plane. Left-click confirms, right-click cancels. Circle color: green if valid position, red if out of range.

- [ ] **Step 6: Run test to verify it passes**

Run: `godot --headless -s tests/test_ex_skill.gd`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add scripts/combat/EXSkillSystem.gd scripts/combat/CostBarManager.gd scripts/combat/SkillTargetingOverlay.gd tests/test_ex_skill.gd
git commit -m "feat(combat): implement EX-Skill system with cost bar, cooldowns, and targeting overlay"
```

---

### Task 14: Multi-Room Dungeon Layout Generator & Roguelike Buff Drafting

**Files:**
- Create: `scripts/combat/DungeonLayoutGenerator.gd`
- Create: `scripts/combat/DungeonRoomManager.gd`
- Create: `scripts/combat/RoguelikeCardManager.gd`
- Create: `scenes/combat/roguelike_card_draft.tscn`
- Create: `tests/test_dungeon_progression.gd`

**Interfaces:**
- Consumes: `EventBus`, `WaveSpawner`, `CombatEventManager`.
- Produces: `DungeonLayoutGenerator`:
  - `generate_layout(room_count: int, difficulty: int) -> Array[Dictionary]` — returns ordered list of `{room_scene_path, room_type, enemy_wave_def, door_positions}`.
  - `room_type: String`: "COMBAT", "ELITE", "BOSS", "REST" (heal between rooms).
- Produces: `DungeonRoomManager`:
  - `start_dungeon(layout: Array[Dictionary])`
  - `get_current_room_index() -> int`
  - `advance_to_next_room()` — unloads current room scene, loads next, positions squad at entrance door.
  - `is_dungeon_complete() -> bool`
  - `get_squad_persistent_state() -> Dictionary` — HP values carried between rooms.
- Produces: `RoguelikeCardManager`:
  - `roll_cards(count: int) -> Array[Dictionary]` — returns `count` random buff cards from pool.
  - `apply_buff(card_id: String)` — adds buff to active session buffs.
  - `get_active_buffs() -> Array[Dictionary]`
  - `clear_session_buffs()` — reset on dungeon exit.
  - Card pool examples: `{id: "fire_rounds", name: "Đạn cháy", effect: "ATK+15%"}`, `{id: "cost_regen", name: "Hồi Cost nhanh", effect: "COST_RATE+30%"}`, `{id: "tank_reflect", name: "Khiên phản đòn", effect: "REFLECT_DMG_10%"}`, `{id: "heal_on_kill", name: "Hồi máu khi hạ gục", effect: "HEAL_ON_KILL_5%"}`.

- [ ] **Step 1: Write failing test for layout generation, card drafting, and persistent HP**

```gdscript
# tests/test_dungeon_progression.gd
extends SceneTree

func _init():
    # Test DungeonLayoutGenerator
    var gen = preload("res://scripts/combat/DungeonLayoutGenerator.gd").new()
    var layout = gen.generate_layout(5, 1)
    assert(layout.size() == 5, "Must generate exactly 5 rooms")
    assert(layout[0].room_type == "COMBAT", "First room should be COMBAT")
    assert(layout[4].room_type == "BOSS", "Last room should be BOSS")
    # Verify no two REST rooms adjacent
    for i in range(layout.size() - 1):
        assert(not (layout[i].room_type == "REST" and layout[i + 1].room_type == "REST"), "No adjacent REST rooms")

    # Test RoguelikeCardManager
    var card_mgr = preload("res://scripts/combat/RoguelikeCardManager.gd").new()
    var cards = card_mgr.roll_cards(3)
    assert(cards.size() == 3, "Must provide exactly 3 card choices")
    # Verify no duplicate cards
    var ids = []
    for card in cards:
        assert(not ids.has(card.id), "No duplicate cards in single draft")
        ids.append(card.id)

    card_mgr.apply_buff(cards[0].id)
    assert(card_mgr.get_active_buffs().size() == 1, "One buff should be active")
    card_mgr.apply_buff(cards[1].id)
    assert(card_mgr.get_active_buffs().size() == 2, "Two buffs should stack")
    card_mgr.clear_session_buffs()
    assert(card_mgr.get_active_buffs().size() == 0, "Buffs cleared on session end")

    # Test DungeonRoomManager persistent state
    var room_mgr = preload("res://scripts/combat/DungeonRoomManager.gd").new()
    room_mgr.set_squad_hp({"shiroko": 2500, "hoshino": 1800})
    var state = room_mgr.get_squad_persistent_state()
    assert(state.shiroko == 2500, "HP must persist between rooms")

    print("PASS: test_dungeon_progression")
    quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s tests/test_dungeon_progression.gd`
Expected: FAIL.

- [ ] **Step 3: Implement DungeonLayoutGenerator.gd**

`extends RefCounted`. Pool of pre-built room scene paths. `generate_layout()`: first room always COMBAT, last always BOSS, middle rooms randomly selected from [COMBAT, COMBAT, ELITE, REST] with weighted probabilities. Higher `difficulty` increases ELITE weight and enemy count in wave definitions. Ensures no adjacent REST rooms.

- [ ] **Step 4: Implement RoguelikeCardManager.gd**

`extends RefCounted`. Static card pool loaded from `res://data/roguelike_cards.json` (moddable). `roll_cards()` samples without replacement. `apply_buff()` adds to `_active_buffs` array. Buffs consumed by `DamageResolver.apply_buff_modifiers()` during combat.

- [ ] **Step 5: Implement DungeonRoomManager.gd and roguelike_card_draft.tscn**

`DungeonRoomManager.gd`: `extends Node`. Tracks `current_room_index`, `layout`, `squad_hp: Dictionary`. `advance_to_next_room()`: saves squad HP, unloads current room scene (`queue_free()`), awaits idle frame, loads next room scene, positions squad at entry marker, restores HP, connects `WaveSpawner` and `CombatEventManager`. Shows card draft UI between rooms.
`roguelike_card_draft.tscn`: `PanelContainer` with 3 `CardButton` children displaying card name, icon, and effect text. Click selects → applies buff → closes panel → advances room.

- [ ] **Step 6: Run test to verify it passes**

Run: `godot --headless -s tests/test_dungeon_progression.gd`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add scripts/combat/DungeonLayoutGenerator.gd scripts/combat/DungeonRoomManager.gd scripts/combat/RoguelikeCardManager.gd scenes/combat/ tests/test_dungeon_progression.gd
git commit -m "feat(roguelike): implement dungeon layout generator, room manager, and card draft system"
```

---

### Task 15: UI System, MomoTalk Phone OS & In-Game Mod Manager

**Files:**
- Create: `scripts/ui/HUDManager.gd`
- Create: `scripts/ui/PhoneOSManager.gd`
- Create: `scripts/ui/PauseMenuManager.gd`
- Create: `scripts/ui/ModManagerUI.gd`
- Create: `scripts/ui/CombatHUD.gd`
- Create: `scenes/ui/hud.tscn`
- Create: `scenes/ui/phone_os.tscn`
- Create: `scenes/ui/pause_menu.tscn`
- Create: `scenes/ui/mod_manager_menu.tscn`
- Create: `scenes/ui/combat_hud.tscn`
- Create: `tests/test_ui_navigation.gd`

**Interfaces:**
- Consumes: `EventBus`, `ModLoader`, `DayCycleManager`, `SaveManager`, `CostBarManager`.
- Produces: `HUDManager`: displays AP bar, credits, day/time, mini-map.
- Produces: `PhoneOSManager`:
  - `active_tab: String` — "INVENTORY", "MAP", "CONTACTS", "MISSIONS", "BGM".
  - `switch_tab(tab_name: String)`
  - `is_open: bool`, `toggle()`
- Produces: `PauseMenuManager`: Resume, Save/Load (uses `SaveManager`), Settings, Quit to Menu, Quit Game.
- Produces: `CombatHUD`: Unit portraits with HP bars, selection indicators, Cost bar display, EX-Skill buttons, wave counter, active buff icons.

- [ ] **Step 1: Write failing test for Phone OS tab switching and pause menu state**

```gdscript
# tests/test_ui_navigation.gd
extends SceneTree

func _init():
    # Test PhoneOS
    var phone = preload("res://scripts/ui/PhoneOSManager.gd").new()
    assert(phone.is_open == false, "Phone must start closed")
    phone.toggle()
    assert(phone.is_open == true, "Phone must open on toggle")
    phone.switch_tab("CONTACTS")
    assert(phone.active_tab == "CONTACTS", "Active tab must switch")
    phone.switch_tab("MAP")
    assert(phone.active_tab == "MAP", "Tab must switch to MAP")
    phone.toggle()
    assert(phone.is_open == false, "Phone must close on second toggle")

    # Test PauseMenu
    var pause = preload("res://scripts/ui/PauseMenuManager.gd").new()
    assert(pause.is_paused == false, "Must start unpaused")
    pause.toggle_pause()
    assert(pause.is_paused == true, "Must be paused after toggle")

    print("PASS: test_ui_navigation")
    quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s tests/test_ui_navigation.gd`
Expected: FAIL.

- [ ] **Step 3: Implement PhoneOSManager.gd and PauseMenuManager.gd (logic)**

`PhoneOSManager.gd`: `extends Control`. Tab enum, `toggle()` slides phone UI in/out with tween animation, `switch_tab()` hides all tab panels and shows selected.
`PauseMenuManager.gd`: `extends Control`. `toggle_pause()` sets `get_tree().paused` and shows/hides menu. Button handlers for Resume, Save, Load, Settings, Quit.

- [ ] **Step 4: Implement HUDManager.gd, CombatHUD.gd, ModManagerUI.gd, and all scene files**

`HUDManager.gd`: `extends CanvasLayer`. Updates labels from `DayCycleManager` signals. Mini-map uses `SubViewport` with top-down camera.
`CombatHUD.gd`: `extends CanvasLayer`. Portrait bar with 4 Striker icons + HP bars, 2 Special skill buttons, Cost bar fill animation, wave counter, active buff icon row.
`ModManagerUI.gd`: `extends Control`. Lists mods from `ModLoader.get_loaded_mods()`, toggle switches per mod, visual indicators for enabled/disabled/error state.

- [ ] **Step 5: Run test to verify it passes**

Run: `godot --headless -s tests/test_ui_navigation.gd`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add scripts/ui/ scenes/ui/ tests/test_ui_navigation.gd
git commit -m "feat(ui): implement HUD, MomoTalk phone OS, combat HUD, pause menu, and mod manager UI"
```

---

### Task 16: Performance Scaler & Cel-Shading Pipeline

**Files:**
- Create: `shaders/cel_toon_shader.gdshader`
- Create: `shaders/outline_shader.gdshader`
- Create: `scripts/core/SettingsManager.gd`
- Create: `scenes/ui/settings_menu.tscn`
- Create: `tests/test_settings_scaler.gd`

**Interfaces:**
- Produces: `SettingsManager` autoload:
  - `current_render_scale: float` (0.5–1.0)
  - `current_draw_distance: float` (50.0–200.0)
  - `shadow_tier: int` (0=Off, 1=Low, 2=Medium, 3=High)
  - `bloom_enabled: bool`, `dof_enabled: bool`, `particles_enabled: bool`
  - `apply_render_scale(scale: float)`, `apply_draw_distance(dist: float)`, `apply_shadow_tier(tier: int)`
  - `save_settings()` — persists to `user://settings.json`.
  - `load_settings()` — reads from `user://settings.json`, applies all.

- [ ] **Step 1: Write failing test for settings application**

```gdscript
# tests/test_settings_scaler.gd
extends SceneTree

func _init():
    var settings = preload("res://scripts/core/SettingsManager.gd").new()

    # Test render scale
    settings.apply_render_scale(0.75)
    assert(abs(settings.current_render_scale - 0.75) < 0.01, "Render scale must update to 0.75")

    # Test draw distance
    settings.apply_draw_distance(80.0)
    assert(abs(settings.current_draw_distance - 80.0) < 0.1, "Draw distance must update")

    # Test shadow tier
    settings.apply_shadow_tier(0)
    assert(settings.shadow_tier == 0, "Shadow tier must be OFF")
    settings.apply_shadow_tier(3)
    assert(settings.shadow_tier == 3, "Shadow tier must be HIGH")

    # Test toggle states
    settings.bloom_enabled = false
    assert(settings.bloom_enabled == false, "Bloom must be disabled")

    # Test settings serialization round-trip
    var dict = settings.to_dict()
    assert(dict.render_scale == 0.75, "Serialized render scale must match")
    var settings2 = preload("res://scripts/core/SettingsManager.gd").new()
    settings2.from_dict(dict)
    assert(abs(settings2.current_render_scale - 0.75) < 0.01, "Deserialized render scale must match")

    print("PASS: test_settings_scaler")
    quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s tests/test_settings_scaler.gd`
Expected: FAIL.

- [ ] **Step 3: Implement cel_toon_shader.gdshader and outline_shader.gdshader**

`cel_toon_shader.gdshader`: `shader_type spatial`. Simplified 2-band cel shading: `dot(NORMAL, LIGHT)` stepped into shadow/lit bands. Configurable shadow color, light color, shadow threshold via uniforms. Supports albedo texture.
`outline_shader.gdshader`: Inverted-hull outline method (vertex extrusion along normals in a second pass). Uniform `outline_width` and `outline_color`.

- [ ] **Step 4: Implement SettingsManager.gd**

`extends Node`. On `apply_render_scale()`: sets `get_viewport().scaling_3d_scale`. On `apply_draw_distance()`: stores value, Hub cameras read it for `Camera3D.far`. On `apply_shadow_tier()`: adjusts `RenderingServer` shadow atlas size (Off=0, Low=1024, Med=2048, High=4096). Toggle methods set `WorldEnvironment` Bloom and DOF enabled states, and toggle `GPUParticles3D` visibility layer. `save_settings()` writes `JSON.stringify(to_dict())` to `user://settings.json`. `load_settings()` reads and applies on startup.

- [ ] **Step 5: Implement settings_menu.tscn**

Scene with `VBoxContainer`: Render Scale slider (0.5–1.0), Draw Distance slider, Shadow Quality dropdown (Off/Low/Med/High), Bloom/DOF/Particles checkboxes, Audio volume sliders (Master, BGM, SFX, Voice). Apply and Reset Defaults buttons.

- [ ] **Step 6: Run test to verify it passes**

Run: `godot --headless -s tests/test_settings_scaler.gd`
Expected: PASS.

- [ ] **Step 7: Register SettingsManager as Autoload and Commit**

Add `SettingsManager="*res://scripts/core/SettingsManager.gd"` to `[autoload]`.

```bash
git add shaders/ scripts/core/SettingsManager.gd scenes/ui/settings_menu.tscn tests/test_settings_scaler.gd project.godot
git commit -m "feat(graphics): add cel-toon shader, outline shader, and performance settings scaler"
```

---

### Task 17: Student Bond Quests & Mission System

**Files:**
- Create: `scripts/data/QuestData.gd`
- Create: `scripts/core/MissionManager.gd`
- Create: `tests/test_mission_system.gd`

**Interfaces:**
- Consumes: `EventBus`, `BondProgressTracker`, `StudentData`.
- Produces: `QuestData` (extends `Resource`, `class_name QuestData`):
  - `id: String`, `title: String`, `description: String`, `student_id: String`
  - `required_bond_level: int` (e.g., 5, 10, 15, 20; extensible for >20 in future updates)
  - `objective_type: String` ("CLEAR_DUNGEON", "COOK_DISH", "GIFT_ITEM", "INTERACT")
  - `target_id: String`, `target_count: int`
  - `reward_items: Dictionary`, `unlocks_roguelike_card_id: String`
- Produces: `MissionManager`:
  - `register_quest(quest: QuestData)`
  - `get_available_quests(student_id: String, current_bond_level: int) -> Array[QuestData]`
  - `record_objective_progress(objective_type: String, target_id: String, count: int)`
  - `complete_quest(quest_id: String, bond_tracker: RefCounted) -> bool` — unlocks the bond gate on `BondProgressTracker` when a milestone quest (levels 5, 10, 15, 20) completes.

- [ ] **Step 1: Write failing test for bond milestone gating (1–20 gated, 21–100 free) and quest completion**

```gdscript
# tests/test_mission_system.gd
extends SceneTree

func _init():
    var tracker = preload("res://scripts/intimacy/BondProgressTracker.gd").new()
    var mission_mgr = preload("res://scripts/core/MissionManager.gd").new()

    var quest = QuestData.new()
    quest.id = "shiroko_bond_5"
    quest.student_id = "shiroko"
    quest.required_bond_level = 5
    quest.objective_type = "CLEAR_DUNGEON"
    quest.target_id = "abydos_bank_robbery"
    quest.target_count = 1
    mission_mgr.register_quest(quest)

    # Give huge EXP: should stop at gate level 5 until quest is completed
    tracker.add_bond_exp("shiroko", 50000)
    assert(tracker.get_bond_level("shiroko") == 5, "Must pause at bond level 5 gate")
    assert(tracker.is_bond_gate_locked("shiroko") == true, "Gate must report locked at level 5")

    # Complete objective & quest
    mission_mgr.record_objective_progress("CLEAR_DUNGEON", "abydos_bank_robbery", 1)
    assert(mission_mgr.complete_quest("shiroko_bond_5", tracker) == true, "Quest completion must succeed")
    assert(tracker.is_bond_gate_locked("shiroko") == false, "Gate 5 must unlock after quest")

    # Unlock gates 10, 15, 20 and verify free leveling from 21 up to cap 100
    for gate_lvl in [10, 15, 20]:
        tracker.complete_bond_quest_gate("shiroko", gate_lvl)
    tracker.add_bond_exp("shiroko", 10000000)
    assert(tracker.get_bond_level("shiroko") == 100, "Bond level must reach max cap 100 freely after level 20")

    print("PASS: test_mission_system")
    quit(0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s tests/test_mission_system.gd`
Expected: FAIL.

- [ ] **Step 3: Implement QuestData.gd and MissionManager.gd**

Implement `QuestData` resource and `MissionManager` tracking objective progress and unlocking `BondProgressTracker` milestone gates (`[5, 10, 15, 20]` by default, capped at `MAX_BOND_LEVEL = 100`).

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s tests/test_mission_system.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/data/QuestData.gd scripts/core/MissionManager.gd scripts/intimacy/BondProgressTracker.gd tests/test_mission_system.gd
git commit -m "feat(missions): add bond quest gating (levels 1-20, max 100) and MissionManager"
```

---

### Task 18: Crafting Chamber & Office Decoration System (with Active Student Cap)

**Files:**
- Create: `scripts/data/FurnitureData.gd`
- Create: `scripts/hub/CraftingChamberManager.gd`
- Create: `scripts/hub/OfficeDecorator.gd`
- Create: `scripts/hub/VisitorSpawner.gd`
- Create: `tests/test_office_and_crafting.gd`

**Interfaces:**
- Consumes: `ItemData`, `StudentData`, `SettingsManager`.
- Produces: `FurnitureData` (extends `Resource`, `class_name FurnitureData`):
  - `id: String`, `name: String`, `grid_size: Vector2i`, `comfort_points: int`, `craft_materials: Dictionary`, `price: int`, `model_path: String`
- Produces: `CraftingChamberManager`:
  - `facility_display_name: String = "Crafting Chamber"` (configurable via data/JSON so lore name can be updated anytime).
  - `craft_furniture(furniture: FurnitureData, inventory: Dictionary) -> bool`
- Produces: `OfficeDecorator`:
  - `grid_width: int`, `grid_height: int`
  - `place_furniture(furniture: FurnitureData, cell: Vector2i, rotation_deg: int) -> bool` (validates bounds, collision, and 90° rotation increments).
  - `remove_furniture(cell: Vector2i) -> FurnitureData`
  - `get_total_comfort() -> int`
- Produces: `VisitorSpawner`:
  - `max_active_students: int = 5` (hard cap on simultaneously spawned 3D student NPCs in office/hub to prevent FPS drops; configurable down to 3 on low-end PCs).
  - `calculate_daily_visitors(unlocked_students: Array[String], comfort_score: int) -> Dictionary` — returns `{active_spawns: Array[String], overflow_queue: Array[String], bonus_gift_multiplier: float}` where `active_spawns.size() <= max_active_students`.

- [ ] **Step 1: Write failing test for Crafting Chamber, grid decoration, and active student FPS cap**

```gdscript
# tests/test_office_and_crafting.gd
extends SceneTree

func _init():
    var crafting = preload("res://scripts/hub/CraftingChamberManager.gd").new()
    assert(crafting.facility_display_name == "Crafting Chamber", "Default facility name must be Crafting Chamber")

    var desk = FurnitureData.new()
    desk.id = "schale_desk"
    desk.grid_size = Vector2i(2, 1)
    desk.comfort_points = 150
    desk.craft_materials = {"wood": 3, "iron": 2}

    var inv = {"wood": 5, "iron": 2}
    assert(crafting.craft_furniture(desk, inv) == true, "Should craft when materials sufficient")
    assert(inv["wood"] == 2, "Materials must be deducted")

    # Test OfficeDecorator grid placement & comfort
    var office = preload("res://scripts/hub/OfficeDecorator.gd").new(8, 8)
    assert(office.place_furniture(desk, Vector2i(0, 0), 0) == true, "Placement on empty cells must succeed")
    assert(office.place_furniture(desk, Vector2i(1, 0), 0) == false, "Overlapping placement must fail")
    assert(office.get_total_comfort() == 150, "Comfort score must sum placed furniture")

    # Test VisitorSpawner hard cap for FPS protection
    var spawner = preload("res://scripts/hub/VisitorSpawner.gd").new()
    spawner.max_active_students = 4
    var roster: Array[String] = ["shiroko", "hoshino", "nonomi", "serika", "ayane", "arona", "yuuka"]
    var result = spawner.calculate_daily_visitors(roster, 2000)
    assert(result.active_spawns.size() <= 4, "Active spawned 3D models must never exceed max_active_students cap")
    assert(result.overflow_queue.size() == 3, "Remaining visitors must go to rotation queue")
    assert(result.bonus_gift_multiplier > 1.0, "High comfort above cap must grant bonus gift multiplier")

    print("PASS: test_office_and_crafting")
    quit(0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s tests/test_office_and_crafting.gd`
Expected: FAIL.

- [ ] **Step 3: Implement FurnitureData, CraftingChamberManager, OfficeDecorator, and VisitorSpawner**

Implement 2D grid occupancy map with 90° rotation footprint calculation, material deduction in Crafting Chamber, and hard-capped visitor spawning with overflow rotation.

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s tests/test_office_and_crafting.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/data/FurnitureData.gd scripts/hub/CraftingChamberManager.gd scripts/hub/OfficeDecorator.gd scripts/hub/VisitorSpawner.gd tests/test_office_and_crafting.gd
git commit -m "feat(hub): add Crafting Chamber, office decoration grid, and FPS-capped VisitorSpawner"
```

---

### Task 19: Shittim Chest Virtual Space (Arona & Plana 3D Mascot Interaction)

**Files:**
- Create: `scripts/hub/ShittimChestSpaceManager.gd`
- Create: `scenes/hub/shittim_chest_space.tscn`
- Create: `tests/test_shittim_chest_space.gd`

**Interfaces:**
- Consumes: `DayCycleManager`, `GestureReceiver`, `EventBus`.
- Produces: `ShittimChestSpaceManager`:
  - `is_loaded: bool`
  - `active_mascots: Array[String]` (default `["arona", "plana"]`)
  - `enter_space() -> bool` — loads the isolated Shittim Chest classroom scene on demand.
  - `exit_space() -> void` — immediately frees the virtual space scene from memory so it consumes 0 RAM/VRAM during normal hub/combat gameplay.
  - `get_mascot_greeting(mascot_id: String, current_hour: float) -> String` — returns contextual greeting or 3:00 AM curfew warning when `current_hour >= 2.0 and current_hour < 3.0`.
  - `interact_with_mascot(mascot_id: String, gesture_type: String) -> Dictionary` — handles headpat, cheek pinch, poke, and dialogue for Arona and Plana.

- [ ] **Step 1: Write failing test for on-demand load/unload lifecycle and Arona/Plana interactions**

```gdscript
# tests/test_shittim_chest_space.gd
extends SceneTree

func _init():
    var space = preload("res://scripts/hub/ShittimChestSpaceManager.gd").new()
    assert(space.is_loaded == false, "Shittim Chest space must not be loaded by default")

    assert(space.enter_space() == true, "Entering Shittim Chest must load isolated space")
    assert(space.is_loaded == true, "Space must report loaded")

    var interaction = space.interact_with_mascot("arona", "HEADPAT")
    assert(interaction.accepted == true, "Arona headpat must succeed")
    var plana_poke = space.interact_with_mascot("plana", "CHEETH_PINCH")
    assert(plana_poke.accepted == true, "Plana interaction must succeed")

    var curfew_msg = space.get_mascot_greeting("arona", 2.5)
    assert(curfew_msg.find("3:00") != -1 or curfew_msg.to_lower().find("sleep") != -1, "Must warn Sensei near 3AM curfew")

    space.exit_space()
    assert(space.is_loaded == false, "Exiting Shittim Chest must unload scene immediately")

    print("PASS: test_shittim_chest_space")
    quit(0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s tests/test_shittim_chest_space.gd`
Expected: FAIL.

- [ ] **Step 3: Implement ShittimChestSpaceManager.gd and shittim_chest_space.tscn**

Implement on-demand scene instantiation and immediate cleanup on exit, mascot interaction handlers for Arona and Plana, and time-of-day/curfew dialogue lines.

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s tests/test_shittim_chest_space.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/hub/ShittimChestSpaceManager.gd scenes/hub/shittim_chest_space.tscn tests/test_shittim_chest_space.gd
git commit -m "feat(shittim-chest): add isolated on-demand 3D space for Arona and Plana interaction"
```

---

### Task 20: Multi-Phase Boss Encounters & Telegraphed AoE System

**Files:**
- Create: `scripts/combat/BossUnit.gd`
- Create: `scripts/combat/TelegraphedAoE.gd`
- Create: `tests/test_boss_encounters.gd`

**Interfaces:**
- Consumes: `EnemyUnit`, `CombatUnit`, `DamageResolver`.
- Produces: `BossUnit` (extends `EnemyUnit`, `class_name BossUnit`):
  - `current_phase: int` (1, 2, 3)
  - `phase_thresholds: Array[float] = [0.7, 0.3]` (transitions to Phase 2 at ≤70% HP, Phase 3 at ≤30% HP).
  - `update_phase_from_hp() -> int`
  - `select_boss_pattern() -> Dictionary` — returns phase-specific attack pattern including telegraphed AoE parameters.
  - Signals: `phase_changed(new_phase: int)`
- Produces: `TelegraphedAoE` (extends `Node3D`, `class_name TelegraphedAoE`):
  - `target_position: Vector3`, `radius: float`, `warn_duration: float` (1.0–2.0s), `damage: int`
  - `elapsed: float`, `has_detonated: bool`
  - `tick(delta: float, units_in_arena: Array) -> Array` — advances warning timer; upon reaching `warn_duration`, deals damage only to units still inside `radius` (rewarding RTS micro dodging).

- [ ] **Step 1: Write failing test for boss phase transitions and telegraphed AoE dodge mechanics**

```gdscript
# tests/test_boss_encounters.gd
extends SceneTree

func _init():
    var boss = preload("res://scripts/combat/BossUnit.gd").new()
    boss.max_hp = 10000
    boss.current_hp = 10000
    assert(boss.current_phase == 1, "Boss starts in Phase 1")

    boss.current_hp = 6800  # 68% -> Phase 2
    assert(boss.update_phase_from_hp() == 2, "Boss must transition to Phase 2 at <=70% HP")

    boss.current_hp = 2500  # 25% -> Phase 3
    assert(boss.update_phase_from_hp() == 3, "Boss must transition to Phase 3 at <=30% HP")

    # Test TelegraphedAoE warning window and dodge via micro
    var aoe = preload("res://scripts/combat/TelegraphedAoE.gd").new()
    aoe.target_position = Vector3(0, 0, 0)
    aoe.radius = 4.0
    aoe.warn_duration = 1.5
    aoe.damage = 500

    var unit_inside = {"name": "Hoshino", "position": Vector3(1, 0, 1), "hp": 2000}
    var unit_dodged = {"name": "Shiroko", "position": Vector3(10, 0, 10), "hp": 2000}

    # At 1.0s (before 1.5s telegraph finishes), no detonation yet
    var early_hits = aoe.tick(1.0, [unit_inside, unit_dodged])
    assert(aoe.has_detonated == false, "Must not detonate before warn_duration")
    assert(early_hits.size() == 0, "No units hit during telegraph warning")

    # At 1.6s total, detonates and hits only unit_inside
    var hits = aoe.tick(0.6, [unit_inside, unit_dodged])
    assert(aoe.has_detonated == true, "Must detonate once warn_duration elapsed")
    assert(hits.size() == 1 and hits[0].name == "Hoshino", "Only unit still inside radius takes damage")

    boss.free()
    aoe.free()
    print("PASS: test_boss_encounters")
    quit(0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s tests/test_boss_encounters.gd`
Expected: FAIL.

- [ ] **Step 3: Implement BossUnit.gd and TelegraphedAoE.gd**

Implement multi-phase boss state machine (70% / 30% HP thresholds) and ground danger zone indicator that only damages units remaining within radius when `warn_duration` expires.

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s tests/test_boss_encounters.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/combat/BossUnit.gd scripts/combat/TelegraphedAoE.gd tests/test_boss_encounters.gd
git commit -m "feat(combat): add multi-phase BossUnit and telegraphed AoE dodge mechanic"
```

---

### Task 21: Horizontal Student Progression & Challenge Modifiers (Anti-Grind System)

**Files:**
- Create: `scripts/core/ProgressionManager.gd`
- Create: `tests/test_progression_system.gd`

**Interfaces:**
- Consumes: `StudentData`, `RoguelikeCardManager`.
- Produces: `ProgressionManager`:
  - `MAX_PERMANENT_STAT_BONUS: float = 0.10` (hard ceiling of +10% permanent stat bonus so skill & roguelike cards always outweigh grinding).
  - `get_permanent_stat_multiplier(student_id: String, bond_level: int, upgrade_tier: int) -> float` — returns multiplier clamped to `[1.0, 1.10]`.
  - `unlock_horizontal_option(student_id: String, option_type: String, option_id: String)` — unlocks new roguelike cards into draft pool or alternative skill variants (`"ROGUELIKE_CARD"`, `"SKILL_VARIANT"`).
  - `get_unlocked_roguelike_cards() -> Array[String]`
  - `set_challenge_modifiers(modifiers: Array[String])` — optional Hades-style heat/challenge modifiers (`"ENEMY_SPEED_UP"`, `"NO_REST_ROOMS"`, `"DOUBLE_BOSS_PHASE"`).
  - `get_challenge_reward_multiplier() -> float`

- [ ] **Step 1: Write failing test for +10% stat ceiling, horizontal card unlocks, and challenge modifiers**

```gdscript
# tests/test_progression_system.gd
extends SceneTree

func _init():
    var prog = preload("res://scripts/core/ProgressionManager.gd").new()

    # Even at max bond 100 and max upgrade tier, permanent stat multiplier must never exceed 1.10 (+10%)
    var mult_zero = prog.get_permanent_stat_multiplier("shiroko", 1, 0)
    assert(abs(mult_zero - 1.0) < 0.001, "0 upgrades at bond 1 must have 1.0x multiplier")

    var mult_max = prog.get_permanent_stat_multiplier("shiroko", 100, 99)
    assert(mult_max <= 1.1001, "Permanent stat bonus must be hard-capped at +10% (1.10x)")
    assert(mult_max >= 1.09, "Max progression should reach the +10% cap")

    # Test horizontal roguelike pool unlocks
    prog.unlock_horizontal_option("shiroko", "ROGUELIKE_CARD", "drone_overclock")
    assert(prog.get_unlocked_roguelike_cards().has("drone_overclock"), "Unlocked roguelike card must appear in pool")

    # Test optional challenge modifiers
    prog.set_challenge_modifiers(["ENEMY_SPEED_UP", "NO_REST_ROOMS"])
    assert(prog.get_challenge_reward_multiplier() > 1.0, "Active challenge modifiers must increase reward multiplier")

    print("PASS: test_progression_system")
    quit(0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s tests/test_progression_system.gd`
Expected: FAIL.

- [ ] **Step 3: Implement ProgressionManager.gd**

Implement horizontal unlock registry (roguelike cards and skill variants), permanent stat multiplier strictly clamped to `1.0 + MAX_PERMANENT_STAT_BONUS` (`1.10`), and optional challenge modifiers.

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s tests/test_progression_system.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/core/ProgressionManager.gd tests/test_progression_system.gd
git commit -m "feat(progression): add horizontal unlocks, +10% stat cap, and challenge modifiers"
```

