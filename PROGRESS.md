# PROGRESS.md — Blue Archive 3D Fan Game (Godot 4.7)

* **Ngày cập nhật:** 2026-11-20
* **Nhánh Git hiện tại:** `master`
* **Trạng thái:** Hoàn thành **21 / 21 Tasks** (kèm vòng Final Review Fix Wave tích hợp liên phân hệ), toàn bộ **21/21 bộ test headless** đều **PASS**.
* **Engine & Cấu hình:** Godot `4.7.2-stable` (Forward+ / D3D12, Jolt Physics 3D, GDScript, addon `godot_ai` MCP và `GDQuest_GDScript_formatter`)
* **Tài liệu nguồn:**
  * Design Spec: [docs/superpowers/specs/2026-11-19-blue-archive-fan-game-design.md](docs/superpowers/specs/2026-11-19-blue-archive-fan-game-design.md)
  * Implementation Plan: [docs/superpowers/plans/2026-11-19-blue-archive-fan-game.md](docs/superpowers/plans/2026-11-19-blue-archive-fan-game.md)
  * SDD Ledger: `.superpowers/sdd/2026-11-19-blue-archive-fan-game/progress.md`

---

## 1. Kiến trúc & Cấu trúc Dự án

Dự án áp dụng **Kiến trúc Đa phân hệ Phân tách rời & Hướng dữ liệu (Decoupled Modular & Data-Driven)**:
* **Dual-Model Pipeline:** Model 1:1 (`normal_model_path`) cho Hub & Tương tác cận cảnh; Model 3D Chibi (`chibi_model_path`) cho Phó bản chiến thuật RTS, hỗ trợ fallback sang placeholder khi thiếu asset.
* **Autoloads (`project.godot`):**
  1. `EventBus` (`scripts/core/EventBus.gd`) — 9 signal toàn cục kết nối lỏng lẻo giữa Core, Hub, Intimacy, Combat và UI.
  2. `DayCycleManager` (`scripts/core/DayCycleManager.gd`) — Vòng lặp ngày/giờ, hệ thống AP và giới nghiêm 3:00 AM.
  3. `SaveManager` (`scripts/core/SaveManager.gd`) — Lưu/tải JSON portable (`<game_dir>/saves`, trong Editor là `res://saves`, fallback `user://saves`), đồng bộ `bonds_exp`, `item_picked_up`, và phát thông báo khi nạp save.
  4. `ModLoader` (`scripts/core/ModLoader.gd`) — Nạp mod portable (`<game_dir>/mods`, trong Editor là `res://mods`), parse JSON học viên, nạp `.pck`, lưu trạng thái bật/tắt mod.
  5. `ZoneTransitionManager` (`scripts/hub/ZoneTransitionManager.gd`) — Chuyển cảnh bất đồng bộ kèm màn hình loading.
  6. `SettingsManager` (`scripts/core/SettingsManager.gd`) — Render scale, draw distance, shadow atlas tier, max active students, post-processing toggles.
  7. `_mcp_game_helper` (`addons/godot_ai/runtime/game_helper.gd`).

```text
D:\This PC\Project\test
├── project.godot
├── docs/superpowers/
│   ├── specs/2026-11-19-blue-archive-fan-game-design.md
│   └── plans/2026-11-19-blue-archive-fan-game.md
├── scenes/
│   ├── combat/        # combat_camera.tscn, roguelike_card_draft.tscn
│   ├── hub/           # loading_screen.tscn, player_sensei.tscn, shittim_chest_space.tscn
│   ├── intimacy/      # intimacy_viewport.tscn
│   ├── minigames/     # cooking_station.tscn
│   └── ui/            # combat_hud.tscn, hud.tscn, mod_manager_menu.tscn, pause_menu.tscn, phone_os.tscn, settings_menu.tscn
├── scripts/
│   ├── core/          # EventBus, DayCycleManager, SaveManager, ModLoader, MissionManager, ProgressionManager, SettingsManager
│   ├── data/          # StudentData, SkillData, ItemData, RecipeData, QuestData, FurnitureData
│   ├── hub/           # CameraModeState, SenseiController, ZoneTransitionManager, DoorPortal, InteractableBase, PickableItem, SittableChair, ToggleLight, CraftingChamberManager, OfficeDecorator, VisitorSpawner, ShittimChestSpaceManager
│   ├── intimacy/      # GestureReceiver, BondProgressTracker, IntimacyManager
│   ├── minigames/     # IngredientPrepStep, CookingManager, CookingStation
│   ├── combat/        # SelectionMath, UnitSelectionManager, RTSCamera3D, DamageResolver, CombatUnit, ProjectileManager, CoverPoint3D, EnemyUnit, EnemyAI, WaveSpawner, CombatEventManager, CostBarManager, EXSkillSystem, SkillTargetingOverlay, DungeonLayoutGenerator, RoguelikeCardManager, DungeonRoomManager, BossUnit, TelegraphedAoE
│   │   └── ai/        # RoleAIBase, TankerAI, DamageDealerAI, HealerAI, BufferAI
│   └── ui/            # HUDManager, PhoneOSManager, PauseMenuManager, ModManagerUI, CombatHUD
├── shaders/           # cel_toon_shader.gdshader, outline_shader.gdshader
└── tests/             # 21 bộ test headless (tests/test_*.gd)
```

---

## 2. Danh sách 21 Tasks đã hoàn thiện

1. **Task 1 — Core Data & EventBus:** `StudentData`, `SkillData`, `ItemData`, `RecipeData` và `EventBus` autoload (`tests/test_data_models.gd`).
2. **Task 2 — Day Cycle & AP System:** `DayCycleManager` autoload với cơ chế AP và giới nghiêm 3:00 AM (`tests/test_day_cycle.gd`).
3. **Task 3 — Portable Save/Load System:** `SaveManager` autoload hỗ trợ `bonds`, `bonds_exp`, `inventory` qua `EventBus.item_picked_up`, và phát tín hiệu đồng bộ UI khi load (`tests/test_save_load.gd`).
4. **Task 4 — Portable ModLoader:** `ModLoader` autoload nạp JSON/PCK, giữ danh sách mod đã tắt (`enabled: false`) cho UI quản lý, `get_enabled_mods()`, phân giải đường dẫn model tương đối trong thư mục mod (`tests/test_mod_loader.gd`).
5. **Task 5 — Hub Sensei Controller (FPS/TPS):** `CameraModeState`, `SenseiController`, `scenes/hub/player_sensei.tscn` đồng bộ `draw_distance` từ `SettingsManager` (`tests/test_camera_mode.gd`).
6. **Task 6 — Hub Interactables & Zone Transitions:** `InteractableBase`, `SittableChair`, `ToggleLight`, `PickableItem`, `DoorPortal`, `ZoneTransitionManager`, `scenes/hub/loading_screen.tscn` (`tests/test_interactables.gd`).
7. **Task 7 — Student Intimacy & Direct Gestures:** `GestureReceiver` (tách riêng `register_headpat_stroke` và `register_cheek_pinch`, clamp offset `[0.0, 1.0]`), `BondProgressTracker` (tối đa cấp 100, cổng nhiệm vụ 1–20), `IntimacyManager`, `scenes/intimacy/intimacy_viewport.tscn` (`tests/test_gesture_logic.gd`).
8. **Task 8 — Relaxed Cooking Minigame:** `IngredientPrepStep`, `CookingManager` (thanh canh điểm vàng dao động không áp lực đếm ngược), `CookingStation`, `scenes/minigames/cooking_station.tscn` (`tests/test_cooking_system.gd`).
9. **Task 9 — Isometric RTS Camera & Selection:** `SelectionMath`, `UnitSelectionManager`, `RTSCamera3D`, `scenes/combat/combat_camera.tscn` (`tests/test_rts_selection.gd`).
10. **Task 10 — Combat Unit Base & Projectiles:** `DamageResolver`, `CombatUnit`, `ProjectileManager` (`tests/test_combat_damage.gd`).
11. **Task 11 — Cover Grid & 4 Role AIs:** `CoverPoint3D`, `RoleAIBase`, `TankerAI`, `DamageDealerAI`, `HealerAI`, `BufferAI` với guard đơn vị đã hạ gục (`IDLE`) và nhường lệnh người chơi (`tests/test_role_ai_decisions.gd`).
12. **Task 12 — Enemies, Waves & Random Combat Events:** `EnemyUnit`, `EnemyAI`, `WaveSpawner`, `CombatEventManager` (`tests/test_enemy_and_events.gd`).
13. **Task 13 — EX-Skill System & Cost Bar:** `CostBarManager`, `EXSkillSystem`, `SkillTargetingOverlay` (`tests/test_ex_skill.gd`).
14. **Task 14 — Multi-Room Dungeon & Roguelike Card Draft:** `DungeonLayoutGenerator`, `RoguelikeCardManager` (hỗ trợ `sync_unlocked_cards()` và `load_cards_from_json()`), `DungeonRoomManager`, `scenes/combat/roguelike_card_draft.tscn` (`tests/test_dungeon_progression.gd`).
15. **Task 15 — UI System:** `HUDManager` (đồng bộ lại khi `SaveManager.game_loaded`), `PhoneOSManager` (MomoTalk OS 5 tab + hiện con trỏ chuột khi mở), `PauseMenuManager` (signal `settings_requested` + hiện con trỏ chuột khi pause), `ModManagerUI`, `CombatHUD` và 5 scene UI (`tests/test_ui_navigation.gd`).
16. **Task 16 — Cel-Shading Shaders & Low-End Settings Scaler:** `cel_toon_shader.gdshader`, `outline_shader.gdshader`, `SettingsManager` (`apply_post_processing`, cập nhật `positional_shadow_atlas_size`), `scenes/ui/settings_menu.tscn` (`tests/test_settings_scaler.gd`).
17. **Task 17 — Bond Quests (Gated 1–20, Max Bond 100):** `QuestData`, `MissionManager` mở khóa bond gate và thẻ roguelike qua `ProgressionManager` khi hoàn thành quest (`tests/test_mission_system.gd`).
18. **Task 18 — Crafting Chamber, Office Decoration & Active Student Cap:** `FurnitureData`, `CraftingChamberManager`, `OfficeDecorator`, `VisitorSpawner` (giới hạn số học viên hiển thị theo `SettingsManager`, hàng đợi tràn + thưởng quà, xoay vòng theo `day_offset`) (`tests/test_office_and_crafting.gd`).
19. **Task 19 — Shittim Chest 3D Space (Arona & Plana):** `ShittimChestSpaceManager` nạp/hủy scene theo nhu cầu, tương tác cử chỉ tách biệt và cảnh báo giới nghiêm 3:00 AM, `scenes/hub/shittim_chest_space.tscn` (`tests/test_shittim_chest_space.gd`).
20. **Task 20 — Multi-Phase Boss & Telegraphed AoE:** `BossUnit` (chuyển pha tại 70% / 30% HP, không chuyển pha sau khi đã bị hạ gục), `TelegraphedAoE` cho phép micro né đòn (`tests/test_boss_encounters.gd`).
21. **Task 21 — Horizontal Progression & Challenge Modifiers:** `ProgressionManager` giới hạn buff chỉ số vĩnh viễn +10%, mở khóa ngang thẻ roguelike / biến thể kỹ năng và bộ điều chỉnh độ khó (`tests/test_progression_system.gd`).

---

## 3. Hướng dẫn Chạy Toàn bộ 21 Bộ Test Headless

Yêu cầu `godot` (Godot `4.7.2-stable`) nằm trong `PATH`. Chạy từng test hoặc toàn bộ vòng lặp từ thư mục gốc repository:

### PowerShell (Windows)
```powershell
Get-ChildItem tests/test_*.gd | Sort-Object Name | ForEach-Object {
    Write-Host "=== Running $($_.Name) ==="
    godot --headless -s ("tests/" + $_.Name)
    if ($LASTEXITCODE -ne 0) { throw "Test failed: $($_.Name)" }
}
```

### Danh sách 21 bộ test
* `godot --headless -s tests/test_data_models.gd`
* `godot --headless -s tests/test_day_cycle.gd`
* `godot --headless -s tests/test_save_load.gd`
* `godot --headless -s tests/test_mod_loader.gd`
* `godot --headless -s tests/test_camera_mode.gd`
* `godot --headless -s tests/test_interactables.gd`
* `godot --headless -s tests/test_gesture_logic.gd`
* `godot --headless -s tests/test_cooking_system.gd`
* `godot --headless -s tests/test_rts_selection.gd`
* `godot --headless -s tests/test_combat_damage.gd`
* `godot --headless -s tests/test_role_ai_decisions.gd`
* `godot --headless -s tests/test_enemy_and_events.gd`
* `godot --headless -s tests/test_ex_skill.gd`
* `godot --headless -s tests/test_dungeon_progression.gd`
* `godot --headless -s tests/test_ui_navigation.gd`
* `godot --headless -s tests/test_settings_scaler.gd`
* `godot --headless -s tests/test_mission_system.gd`
* `godot --headless -s tests/test_office_and_crafting.gd`
* `godot --headless -s tests/test_shittim_chest_space.gd`
* `godot --headless -s tests/test_boss_encounters.gd`
* `godot --headless -s tests/test_progression_system.gd`
