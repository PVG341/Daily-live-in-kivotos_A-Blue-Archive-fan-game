# PROGRESS.md — Blue Archive 3D Fan Game (Godot 4.7)

* **Ngày cập nhật:** 2026-11-23
* **Nhánh Git hiện tại:** `main`
* **Trạng thái:** Hoàn thành **21 / 21 Tasks** (kèm Final Review Fix Wave, Memory/RAM Leak Audit, Phase 5 Mốc 1 Tòa nhà Schale, Phase 5 Mốc 2 Đấu trường Roguelike RTS, và Nâng cấp Tactical UI & Địa hình Chiến trường), toàn bộ **25/25 bộ test headless** đều **PASS** với **0 orphan nodes / 0 ObjectDB leaks**.
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
│   ├── combat/        # combat_camera.tscn, combat_arena.tscn, roguelike_card_draft.tscn, rooms/room_{combat,elite,rest,boss}.tscn
│   ├── hub/           # loading_screen.tscn, player_sensei.tscn, shittim_chest_space.tscn, zones/schale_building.tscn, zones/schale_office.tscn, zones/crafting_chamber.tscn
│   ├── intimacy/      # intimacy_viewport.tscn
│   ├── minigames/     # cooking_station.tscn
│   └── ui/            # combat_hud.tscn, hud.tscn, mod_manager_menu.tscn, pause_menu.tscn, phone_os.tscn, settings_menu.tscn
├── scripts/
│   ├── core/          # EventBus, DayCycleManager, SaveManager, ModLoader, MissionManager, ProgressionManager, SettingsManager
│   ├── data/          # StudentData, SkillData, ItemData, RecipeData, QuestData, FurnitureData
│   ├── hub/           # CameraModeState, SenseiController, ZoneTransitionManager, HubSceneController, DoorPortal, InteractiveDoor, InteractiveElevator, ElevatorCallButton, FloorVisibilityZone, InteractableBase, PickableItem, SittableChair, ToggleLight, CraftingChamberManager, OfficeDecorator, VisitorSpawner, ShittimChestSpaceManager
│   ├── intimacy/      # GestureReceiver, BondProgressTracker, IntimacyManager
│   ├── minigames/     # IngredientPrepStep, CookingManager, CookingStation
│   ├── combat/        # SelectionMath, UnitSelectionManager, RTSCamera3D, DamageResolver, CombatUnit, ProjectileManager, CoverPoint3D, EnemyUnit, EnemyAI, WaveSpawner, CombatEventManager, CostBarManager, EXSkillSystem, SkillTargetingOverlay, CombatHealthBarOverlay, DestructibleWall3D, CommanderDirectiveSystem, DungeonLayoutGenerator, RoguelikeCardManager, DungeonRoomManager, BossUnit, TelegraphedAoE, TacticalTerrainZone, CombatRoomData, ChibiProxyFactory, SelectionBoxOverlay, CombatArenaController
│   │   └── ai/        # RoleAIBase, TankerAI, DamageDealerAI, HealerAI, BufferAI, UtilityAIManager
│   └── ui/            # HUDManager, PhoneOSManager, PauseMenuManager, ModManagerUI, CombatHUD
├── shaders/           # cel_toon_shader.gdshader, outline_shader.gdshader
└── tests/             # 25 bộ test headless (tests/test_*.gd)
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

### Danh sách 25 bộ test
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
* `godot --headless -s tests/test_memory_leaks.gd`
* `godot --headless -s tests/test_hub_scene_flow.gd`
* `godot --headless -s tests/test_seamless_hub.gd`
* `godot --headless -s tests/test_combat_arena_flow.gd`

---

## 5. Knowledge Graph & Tiết kiệm Token (Graphify Godot)

Dự án đã được tích hợp bộ công cụ **`graphify-godot`** (`graphifyy==0.5.0+godot1`), cho phép chuyển đổi toàn bộ mã nguồn GDScript (`.gd`) và các Scene (`.tscn`) thành Đồ thị Tri thức (Knowledge Graph) offline bằng AST Tree-sitter (0 token API).

* **Đầu ra trích xuất:** Thư mục `graphify-out/` gồm:
  * `graph.json` (3.391 nodes, 10.056 edges, 29 communities)
  * `graph.html` (Giao diện trực quan hóa đồ thị tương tác trong trình duyệt)
  * `GRAPH_REPORT.md` (Báo cáo tóm tắt các nút trung tâm / God Nodes và cộng đồng mã nguồn)
* **Bộ nhớ đệm AST:** Được lưu trữ cục bộ tại `.graphify_cache/` (đã thêm vào `.gitignore`).
* **Lệnh cập nhật đồ thị (0 token):**
  ```powershell
  $env:TREE_SITTER_LANGUAGE_PACK_CACHE_DIR='d:/This PC/Project/test/.graphify_cache'
  graphify update .
  ```
* **Lệnh truy vấn nhanh cho Agent mới (Tiết kiệm token khảo sát):**
  ```powershell
  graphify explain "<NodeName.gd>"     # Ví dụ: graphify explain "DayCycleManager.gd"
  graphify query "<Câu hỏi về hệ thống>"  # Giới hạn chặt chẽ trong ngân sách 2000 tokens
  graphify path "<NodeA>" "<NodeB>"       # Tìm đường đi ngắn nhất giữa 2 thành phần
  ```

---

## 6. Kiểm toán & Chống Rò rỉ Bộ nhớ / Tràn RAM (Memory & Leak Audit)

Trước khi chuyển sang Phase 5, toàn bộ 60 scripts GDScript và 22 bộ test đã được kiểm toán vòng đời bộ nhớ (`NOTIFICATION_PREDELETE`, `_exit_tree()`, dọn dẹp tham chiếu và node mồ côi):
* **`ProjectileManager.gd`:** Thêm giới hạn vòng đời `MAX_PROJECTILE_LIFETIME = 15.0`, loại bỏ ngay đạn có `speed <= 0.0`, giải phóng tham chiếu `source` / `target_unit` khi chạm đích hoặc hết hạn, và bổ sung `clear_projectiles()`.
* **`ShittimChestSpaceManager.gd` & `DungeonRoomManager.gd`:** Bổ sung bảo vệ `NOTIFICATION_PREDELETE` và `_exit_tree()` để tự động giải phóng scene `loaded_space_instance` / `current_room_node` còn sót lại nếu manager bị hủy đột ngột, tránh Orphan Node leak.
* **`HUDManager.gd` & `CombatHUD.gd`:** Ngắt kết nối tín hiệu `EventBus` / `SaveManager` trong `_exit_tree()`; tự động xóa các `Portrait_<sid>` cũ trong `StrikerPortraits` và cung cấp `clear_hud()`.
* **`CoverPoint3D.gd`, `CombatUnit.gd` & `UnitSelectionManager.gd`:** `CoverPoint3D` tự dọn occupant đã chết hoặc đã bị giải phóng (`_sanitize_occupant()`); `CombatUnit.die()` xóa `order_target_node` & `current_order_type`; `UnitSelectionManager` cung cấp `prune_invalid_units()`.
* **`SaveManager.gd` & `ModLoader.gd`:** `SaveManager` ngắt kết nối `EventBus` cũ khi đổi bus (`set_event_bus`) và khi rời tree (`_exit_tree`); `ModLoader` theo dõi `_mounted_pcks` để tránh nạp trùng gói `.pck` vào RAM khi quét lại mod.
* **Stress Test Tự động:** `tests/test_memory_leaks.gd` kiểm chứng trực tiếp `Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT) == 0` sau hàng loạt chu kỳ cấp phát/giải phóng.

---

## 7. Nâng cấp Tactical UI & Bản đồ Chiến trường Phức tạp (Phase 5)

* **Phản hồi Chọn Đơn vị & Nhóm (RTS Selection Feedback):** `CombatHUD` (`SelectedUnitsLabel`, viền sáng chân dung `"★ [...]"`), `SelectionBoxOverlay` (khung chọn nhóm 2D, ngoặc chọn cá thể, đường chỉ dẫn lệnh), và vòng `SelectionRing` + `AttackRangeRing` 3D quanh đơn vị được chọn.
* **Cột sáng Lệnh RTS & Target Reticle:** `ChibiProxyFactory` bổ sung `OrderStatusPillar` (cột sáng + nhãn trạng thái `"🛡️ HOLD POS"`, `"🚫 HOLD FIRE"`, `"🎯 FOCUS FIRE"`, `"🧱 TAKE COVER"`, `"➔ MOVING"`) và `TargetReticle` (`"▼ TARGET ▼"`) trên mục tiêu bị focus fire; `CombatArenaController` phát `order_beacon` tại vị trí ra lệnh.
* **Xem trước Phạm vi EX-Skill (Live AoE Range Preview):** `SkillTargetingOverlay` & `CombatArenaController` cập nhật `skill_preview_disc` (3D) + vòng tròn AoE 2D theo vị trí con trỏ chuột khi nhắm kỹ năng.
* **Địa hình Chiến trường Mở rộng (`TacticalTerrainZone.gd`):** Mở rộng kích thước `room_combat.tscn` (`64×56`), `room_elite.tscn` (`68×60`), `room_boss.tscn` (`72×64`) với nhà đô thị, bunker bê tông (`BUNKER_INTERIOR`), cầu vượt (`UNDER_BRIDGE`), mương nước làm chậm (`WATER_TRENCH`), hố pháo (`CRATER_PIT`), và điểm cao chiến thuật tăng tầm đánh (`HIGH_GROUND`).

---

## 8. Phase A — Thanh máu Kẻ địch, Cấu hình Tầm Skill & Di chuyển Camera Combat

* **Tùy chọn khung chọn nhóm (`SettingsManager` & `SelectionBoxOverlay`):** Thêm `show_group_frame` (mặc định `false`) để ẩn khung xanh bao nhóm sau khi thả chuột kéo chọn, chỉ giữ vòng sáng dưới chân và viền HUD.
* **Di chuyển & Xoay Camera Combat (`RTSCamera3D`):** Hỗ trợ đầy đủ WASD, phím mũi tên (`Arrow Keys`), kéo chuột giữa hoặc `Space + Chuột trái` (`pan_by_screen_delta()`), xoay `Q/E`, zoom cuộn chuột và phím `C` / `Home` để đưa camera về lại tâm đội hình.
* **Cấu hình Tầm & Hình dạng Skill (`SkillData` & `SkillTargetingOverlay`):** Bổ sung `cast_range`, `min_range`, `aoe_shape` (`CIRCLE`/`CONE`/`LINE`), `cone_angle_deg`, `line_width`, `requires_los`, `pierce_walls`, `wall_damage`; giới hạn điểm nhắm vào trong `cast_range` kèm vòng `SkillRangeRing` 3D và chuyển màu cam-đỏ khi vượt tầm.
* **Thanh máu 3D/2D, Boss HP Bar & Số sát thương bay (`ChibiProxyFactory` & `CombatHealthBarOverlay`):** Gắn `HPBar3D` trên từng đơn vị (tự xoay mặt theo camera), overlay thanh máu 2D, Boss HP bar trên đỉnh màn hình (kèm mốc chuyển pha 70% / 30%) và số sát thương/hồi máu bay lên theo thời gian thực.

---

## 9. Phase B — Line-of-Sight (LOS), Xuyên Tường & Tường Phá Hủy Được

* **Phân mảnh Tường Phá hủy được (`DestructibleWall3D` & `CombatRoomData`):** Tự động tách các tường nhà, bunker, trụ cầu, parapet và chướng ngại vật trong phòng thành từng module `DestructibleWall3D` với `armor_tier` (`1` = gỗ/chắn nhẹ, `2` = tường gạch/nhà, `3` = bê tông/trụ cầu) và `max_hp`. Khi bị phá hủy sẽ tạo lỗ hổng (đống gạch vụn thấp `RubbleRoot`), tắt va chạm và mở đường di chuyển/tầm nhìn.
* **Chặn Đạn, Kiểm tra Tầm Nhìn & Lực Xuyên (`ProjectileManager` & `CombatArenaController`):** Đạn bắn thường (`penetration_power = 0`) bị chặn bởi tường có `armor_tier > 0` (`🧱 BLOCKED`); đơn vị tự động vòng cạnh bên (`_move_unit_around_walls()`) để tìm góc bắn rõ LOS. Đạn hoặc skill có `penetration_power >= armor_tier` xuyên qua tường với sát thương suy giảm theo số lớp tường đã xuyên.
* **Kỹ năng Đục Tường / Xuyên Tường (`SkillData` & `SkillTargetingOverlay`):** Bổ sung `[3] Shotgun Breach (2)` (hình nón `CONE`, đục tường tầm gần) và `[4] Railgun Beam (3)` (tia thẳng `LINE`, xuyên tường bê tông `armor_tier = 3`), cùng xem trước hình nón/tia 2D và cảnh báo đỏ khi bị tường chắn LOS.

---

## 10. Phase C — Chế độ Chỉ huy ("Pick Me Up"), Utility AI & Sửa Lỗi Kẹt Tường

* **Hệ thống Chỉ thị Chỉ huy (`CommanderDirectiveSystem` & `CombatArenaController`):** Thay thế điều khiển vi mô RTS trực tiếp bằng các chỉ thị chiến thuật: kéo chuột trái để khoanh **Vùng Tác Chiến (`TacticalZoneDisc`)**, chuột phải vào địch để gắn **Mục Tiêu Trọng Yếu (`TargetReticle`)**, chuột phải ra đất để vẽ **Mũi tên Hướng Tiến Quân (`advance_arrow`)**, phím `Z / X / V` đổi tư thế đội hình (`TỔNG TẤN CÔNG` / `CÂN BẰNG` / `PHÒNG THỦ`), phím `TAB` bật tắt **Tactical Slow-Mo 0.25x**, phím `G` xóa chỉ thị.
* **Utility AI Tự chủ (`UtilityAIManager`):** Chấm điểm liên tục 7 hành vi (`EVADE_AOE` né vòng đỏ `TelegraphedAoE`, `SURVIVAL_RETREAT` rút lui khi máu thấp, `HEAL_ALLY`, `ADVANCE_TO_ZONE`, `FOCUS_PRIORITY_TARGET`, `TAKE_COVER_AND_ENGAGE`, `ENGAGE_BEST_ENEMY`), kết hợp cấp Bond để tính độ tuân lệnh và tự động bỏ qua các điểm nấp không còn tầm nhìn tới địch.
* **Điều hướng Chống Kẹt & Tách Đơn vị (`DestructibleWall3D` & `CombatArenaController`):** Khắc phục triệt để lỗi 2 nhân vật đi qua lại hoặc chồng lên nhau ở mép tường (`CoverCraterRim` / `Bunker`): đẩy thoát chồng lấn tức thì (`get_push_out_offset()`), chọn waypoint góc ngoài không bị chặn (`get_flank_corners()` kèm `_unit_flank_memory`), lái 7 góc quạt `[0°, ±35°, ±65°, ±95°]` và tách khoảng cách đồng minh (`_apply_unit_separation()`).

---

## 11. Phase C+ (Bản nâng cấp Công cụ Chỉ huy Đa Vùng, Lệnh Riêng Từng Nhân Vật, Vùng Freeshot & Giữ Hỏa Lực Không Chặn Di Chuyển)

* **Quy trình Công cụ Chỉ huy Chuẩn ("Chọn Nhân Vật -> Chọn Công Cụ -> Click Bản Đồ" & Ấn Đúp Tại Chỗ):** Bổ sung thanh `CommanderToolBar` trong `CombatHUD` (`focus_mode = FOCUS_NONE`) với các nút và phím tắt `[Z / ZZ]` **Vùng Giao Tranh (`ASSAULT`)**, `[V / VV]` **Vùng Phòng Thủ (`DEFENSE`)**, `[B / BB]` **Vùng Freeshot (`FREESHOT`)**, `[H]` **Giữ Hỏa Lực (`HOLD_FIRE`)**, `[G]` **Hủy Đang Chọn**, `[Shift+G]` **Hủy Toàn Bộ** (loại bỏ chế độ Vùng Cân Bằng và bỏ tư thế chung toàn đội khi mới chọn công cụ). Ấn 1 lần chỉ nạp công cụ, ấn đúp (`ZZ`/`VV`/`BB`) kích hoạt ngay vùng tại vị trí nhóm đang chọn.
* **Quy Tắc "Lệnh Mới Nhất Thắng" & Đa Vùng Không Trùng Lặp (`CommanderDirectiveSystem` & `ChibiProxyFactory`):** Loại bỏ ký hiệu `"*"` gây trùng vùng giữa "4 thành viên" và "TOÀN ĐỘI"; chuẩn hóa danh sách `squad_unit_ids` để lệnh toàn đội ban ra sau xóa hẳn vùng cá nhân cũ, và lệnh cá nhân ban ra sau tách riêng người đó khỏi vùng toàn đội. Tự động thu hồi vùng khi nhân vật hy sinh (`_on_striker_died`).
* **Chuột Phải Tiến Công Vừa Đi Vừa Đánh (`ADVANCE_ENGAGE`) vs `Shift + Chuột Phải` Đi Thẳng (`MOVE`):** Chuột phải xuống đất gán `unit_advance_map` cho phép nhân vật tiến về hướng chỉ định và tự động bắn trả kẻ địch trong tầm & LOS trên đường đi; `Shift + Chuột phải` ra lệnh di chuyển thẳng không bắn (`issue_move_order`).
* **Phá Kẹt Vòng Tròn & Chống Va Chạm Đồng Minh (`UtilityAIManager` & `CombatArenaController`):** Khắc phục lỗi đứng khựng ở rìa vòng tròn bằng cơ chế trễ trạng thái (`_in_zone_<id>`) kết hợp điểm neo 4 góc phần tư sâu bên trong vùng (`_get_zone_inner_anchor()`); khóa đơn vị `DEFENSE` giữ đội hình chiến đấu bên trong vùng và cho phép đơn vị `ASSAULT` tiến/rút tự do sau khi vào vùng. Nâng cấp tránh đồng minh trong `_navigate_unit_toward()` (`_is_step_blocked_by_peer()`) và tăng lực đẩy tách `_apply_unit_separation()` (`1.35m`).
* **Vùng Freeshot (`FREESHOT_BOMBARD`) & Giữ Hỏa Lực Không Khóa Di Chuyển (`CombatUnit`):** Cho phép chỉ định vùng oanh tạc pháo kích liên tục (`_fire_freeshot_shell()` gây sát thương AoE trong bán kính vùng). Đặt `is_holding_fire` là cờ độc lập trong `CombatUnit` để khi bật `[H]`, nhân vật vẫn nhận lệnh di chuyển, né AoE và đổi vùng bình thường, chỉ chặn hoàn toàn hành động nổ súng.
* **Kiểm thử Xác minh (`tests/test_combat_arena_flow.gd`):** Bổ sung `# 4e.` và `# 4f.` kiểm tra chọn công cụ `CommanderToolBar`, click chân dung HUD, 3 vùng đồng thời, quy tắc "lệnh mới nhất thắng" (`Cá nhân -> Toàn đội` và `Toàn đội -> Cá nhân`), không trùng vùng 4 thành viên vs toàn đội, `[G]` vs `[Shift+G]`, ấn đúp `[VV]` đặt vùng tại chỗ, `ADVANCE_ENGAGE` vừa đi vừa đánh, và `HOLD_FIRE` (25/25 suite pass, `0` orphan nodes).

---

## 12. Phase D — Chiến Trường Seamless Đa Phân Khu (`EncounterZoneManager`), Tải Chunk Bất Đồng Bộ & Hành Quân Không Dịch Chuyển

* **Quản lý Vùng Giao Tranh & Tải Chunk Bất Đồng Bộ (`EncounterZoneManager.gd` & `DungeonLayoutGenerator.gd`):**
  * Chuyển từ mô hình "phòng rời xóa/tạo lại tại `(0,0,0)`" sang **Chiến trường Seamless Đa Phân Khu** dài hơn `260m` dọc theo trục tiến quân `-Z`.
  * Sử dụng `ResourceLoader.load_threaded_request` (`preload_layout_chunks()` / `get_chunk_scene()`) để nạp trước các chunk phân khu (`COMBAT`, `ELITE`, `REST`, `BOSS`) vào bộ đệm, loại bỏ khựng khung hình.
  * Tự động mở cổng thông suốt `16m` (`open_sector_gateways()`) ở tường Bắc/Nam của các phân khu liền kề và dựng đại lộ nối tiếp **`SectorConnector`** kèm tường chắn bên và `CoverPoint3D`.
* **Cổng Chắn Năng Lượng (`SectorGate`) & Hành Quân Liên Tục Không Teleport (`CombatArenaController.gd`):**
  * Mỗi phân khu có cổng chắn năng lượng `SectorGate_<k>` (`armor_tier = 99`) khóa lối ra phía Bắc khi còn địch. Ngay khi tiêu diệt hết địch trong khu vực (`_on_wave_cleared`), cổng tự động hạ xuống (`unlock_sector_gate()`), đổi bảng hiệu sang màu xanh lục `"🔓 KHU VỰC ... — TIẾN QUÂN ➔"`.
  * Khi người chơi chọn thẻ Roguelike (`select_draft_card`), các phân khu cũ và những bức tường đã bị bắn thủng **được giữ nguyên** trên bản đồ; **4 học viên Striker không bị dịch chuyển (teleport)** mà giữ nguyên vị trí thực tế, tự động nhận chỉ thị `ADVANCE_ENGAGE` kèm **tăng tốc hành quân chiến thuật `1.65x` (`TACTICAL_MARCH_SPEED_MULT`)** để băng qua đại lộ nối tiếp tiến vào khu vực giao tranh mới.
  * Mở rộng `room_rest.tscn` lên `64×36` đồng bộ chiều rộng chiến trường; trong chế độ seamless, đội hình hành quân thực tế vào **Trạm Tiếp Tế (`REST`)** mới kích hoạt hồi máu `+35%` và mở thẻ bài.
* **Truy vấn Tọa độ Thế giới Liên Phân Khu & Mở rộng Camera (`CombatRoomData.gd`, `TacticalTerrainZone.gd`, `CoverPoint3D.gd`, `CombatHUD.gd`):**
  * Liên kết toàn bộ phân khu qua `linked_sectors` để kiểm tra tầm nhìn `check_line_of_sight()`, đạn xuyên tường `get_all_battlefield_walls()`, và hiệu ứng địa hình `get_terrain_modifiers_at()` xuyên suốt mọi phân khu và hành lang.
  * Tự động mở rộng giới hạn `RTSCamera3D` (`bounds_min` / `bounds_max`) bao trọn toàn bộ chiến trường seamless và bổ sung thanh tiến trình `SectorProgressLabel` trên `CombatHUD`.

### 12b. Tối ưu Hiệu năng & Hotfix Phase D (QA Patch)
* **Tăng tốc CPU & GPU từ 5–6 FPS lên 116–128 FPS (4.08 ms/tick @ 60Hz):**
  * `DestructibleWall3D.gd`: Cache `global_transform`, `affine_inverse()`, tâm thế giới và nửa kích thước XZ AABB qua `set_notify_transform(true)`; fast XZ AABB reject trước OBB kèm hằng `_NO_HIT`; tạo `RubbleRoot` lazy khi `destroy_wall()`; chia sẻ `StandardMaterial3D` theo màu và chỉ `duplicate()` khi tường bắt đầu vỡ/nhận sát thương.
  * `TacticalTerrainZone.gd` & `CombatRoomData.gd`: Cache `get_world_center()` qua `_center_dirty`, cache `get_terrain_zones()`, lọc nhanh theo biên XZ phân khu trong `get_terrain_modifiers_at()`, bỏ `_prune_wall_obstacles()` mỗi tick, cache `get_all_battlefield_walls()` O(W) kèm `invalidate_wall_cache()`, thêm truy vấn Z-band (`find_wall_blocking_point()`, `find_movement_blocker_along_segment()`) và áp dụng lọc Z-band vào `check_line_of_sight()`.
  * `EncounterZoneManager.gd`: Poll `ResourceLoader.load_threaded_get_status()` trong `_process()` không chặn Main Thread, thêm `update_sector_visibility(active_index)` ẩn phân khu/hành lang cách $\ge 2$ bước, khử trùng O(N) bằng `Dictionary`.
  * `UtilityAIManager.gd`, `CombatArenaController.gd`, `CombatHUD.gd`: Memoize `_check_los()` trong cùng lượt đánh giá, fast axis reject trong `_find_best_cover()`, giảm tần suất chạy AI xuống `AI_EVAL_INTERVAL = 0.15s` lệch pha giữa 4 Striker kèm `_invalidate_ai_cache()`, và dirty-check HP/trạng thái nhãn & chân dung HUD.
* **Hotfix Boss AoE (`previously freed instance`):** Trong `_tick_striker()`, ép đánh giá lại khi `cached_action == "EVADE_AOE"` và kiểm tra `typeof(...) == TYPE_OBJECT and is_instance_valid(...)` trước toán tử `is`; gọi `_invalidate_ai_cache()` trong `_tick_active_aoes()` và `_clear_active_aoes()`. Đã thêm 2 tick hồi quy trong `tests/test_combat_arena_flow.gd`.

---

## 13. Phase E — Phân Vai Vũ Khí/Kẻ Địch, EX Caster Chuyên Biệt, Game Feel (VFX/SFX) & Blue Archive Tactical HUD

* **Phân vai Vũ khí Striker & EX Caster Riêng Biệt (`CombatUnit.gd`, `SkillData.gd`, `UtilityAIManager.gd`, `CombatArenaController.gd`):**
  * **4 Striker đặc trưng vai trò:** **Hoshino (`SG`)** Tanker mang khiên chắn trước (`frontal_shield_ratio = 0.40`, `FrontShieldMesh`), **Shiroko (`SR`)** tầm xa `16.5m` có xuyên giáp/xuyên khiên `penetration_power = 2` và ưu tiên điểm cao chiến thuật (`HIGH_GROUND` `+10.0`), **Serika (`ARTILLERY`)** gây sát thương nổ lan AoE mỗi phát bắn (`is_aoe_attacker = true`), và **Hanae (`HG`)** Healer.
  * **Tách EX Caster Độc Lập & Khóa Caster Bị Hạ Gục:** Gắn `caster_id`/`caster_name` cho kỹ năng EX: **`[3] Shotgun Breach`** lấy vị trí Hoshino và **`[4] Railgun Beam`** lấy vị trí Shiroko bất kể đang chọn đơn vị nào; `[1] Missile Barrage` và `[2] Team Heal` giữ vai trò Special chi viện. Khóa kích hoạt và hiển thị trạng thái `DOWN` trên HUD nếu caster bị hạ gục.
* **Kẻ Địch Đa Dạng & Đánh Thức Phân Khu Seamless (`EnemyUnit.gd`, `EnemyAI.gd`, `ProjectileManager.gd`, `ChibiProxyFactory.gd`):**
  * Bổ sung 3 loại địch chiến thuật: **`GRUNT` (`AR`)**, **`SHIELD_HEAVY` (`SG`, khiên trước `frontal_shield_ratio = 0.55` buộc đánh bọc sườn hoặc dùng `penetration_power >= 2`)**, và **`SNIPER` (`SR`, biết `KITE_BACK` lùi giữ cự ly trong bán kính `12m` quanh `patrol_origin`)**.
  * Hướng xoay mặt độc lập qua `VisualRoot/FacingPivot` (`update_facing_toward()`), `take_directional_damage()` kèm tín hiệu `projectile_impact`, và cơ chế `is_alerted` / `detection_radius` đánh thức dây chuyền cả tổ đội (`_alert_enemy_squad()` -> `"❗ PHÁT HIỆN!"`).
* **Game Feel, Hiệu Ứng 3D & Âm Thanh Tổng Hợp (`CombatFeelManager.gd`, `RTSCamera3D.gd`, `SettingsManager.gd`):**
  * Triển khai **rung camera bậc hai theo `trauma` (`RTSCamera3D.tick_shake`)**, **real-time Hit-Stop** (`get_hit_stop_scale()` đồng bộ không đè Slow-Mo `[TAB]`), tia đạn theo lớp vũ khí/Railgun, quạt lửa Shotgun `spawn_cone_flash()`, sóng nổ `spawn_explosion_burst()`, hiệu ứng giật lún thân `trigger_unit_hit_flash()`, cùng pool âm thanh `AudioStreamWAV` (`shot_ar`, `shot_sg`, `shot_sr`, `explosion`, `breach`, `heal`, `alert`, `ui_click`).
  * Bổ sung tùy chọn tiếp cận `screen_shake_strength` và `reduce_flashing` trong `SettingsManager`.
* **Blue Archive Tactical HUD (`CombatHUD.gd` & `scenes/ui/combat_hud.tscn`):**
  * Bố cục lại HUD phong cách Blue Archive gọn gàng, không chồng lấp ở `1152×648` và `1280×720`: thẻ chân dung `PanelContainer` gắn huy hiệu vũ khí (`[SG]`/`[SR]`/`[ARTILLERY]`/`[HG]`), thanh máu, thẻ EX hiển thị Cost/Cooldown/Caster, thanh Cost phân đoạn cyan kèm `CostValueLabel`, `SectorProgressLabel` và `SlowMoBadge`, tối ưu bằng `_ui_styles` và dirty-check.
* **Kiểm thử Xác minh:** Bổ sung `# 5b.` và `# 5c.` trong `tests/test_combat_arena_flow.gd`; toàn bộ **25/25 suite headless pass** (`OBJECT_ORPHAN_NODE_COUNT == 0`) và smoke-test trực tiếp `scenes/combat/combat_arena.tscn --quit-after 60` đạt `0` lỗi runtime.

### 13b. Vá Điều hướng A* (`BattlefieldNavGrid`) & Hotfix An toàn Instance Đã Giải phóng (`CombatFeelManager`)
* **Tìm đường A* trên lưới XZ (`BattlefieldNavGrid.gd`, `CombatRoomData.gd`, `EncounterZoneManager.gd`, `CombatArenaController.gd`):**
  * Tạo mới `BattlefieldNavGrid.gd` (`AStarGrid2D`, `cell_size = 1.0m`) bake ô rắn từ toàn bộ `DestructibleWall3D` chưa vỡ và tường tĩnh (`Wall*`, `CorridorWall*`, `RestFountain`) với bộ đếm `_cell_block_counts` chống mất ô góc khi phá 1 đoạn tường.
  * `CombatRoomData.gd` phát signal `wall_obstacle_added`; `EncounterZoneManager.gd` dựng `nav_grid` sau khi nối battlefield seamless, cập nhật `notify_wall_destroyed()` khi mở `SectorGate`, và dọn dẹp khi `clear_battlefield()`.
  * Nâng cấp `_navigate_unit_toward()` dùng A* + làm mượt `_smooth_nav_path()`, cache waypoint kèm watchdog chống kẹt (`NAV_STUCK_CHECK_INTERVAL = 0.45s`), mở rộng góc rẽ tới `±160°` để thoát bunker chữ U/nhà đô thị và hủy cache ngay khi cổng mở hoặc tường bị phá. Kiểm thử hồi quy `# 4g.` trong `tests/test_combat_arena_flow.gd`.
* **Hotfix An toàn Instance Đã Giải phóng (`CombatFeelManager.gd`, `CombatArenaController.gd`):**
  * Đảo thứ tự sang `typeof(x) == TYPE_OBJECT and is_instance_valid(x) and x is ...` tại toàn bộ 6 điểm trong `CombatFeelManager.gd` (`_attach_vfx_node`, `trigger_unit_hit_flash`, `tick_effects`, `clear_effects`) và 5 điểm trong `CombatArenaController.gd`.
  * Gọi `feel_manager.clear_effects()` trước `_clear_enemies()` trong `_on_room_loaded()`.
  * Bổ sung kiểm thử hồi quy `# 5d.` trong `tests/test_combat_arena_flow.gd` (xác nhận an toàn khi node có hit-flash bị `free()` ngay lập tức); chạy lại toàn bộ **25/25 suite headless pass** (không phát sinh `SCRIPT ERROR`, `OBJECT_ORPHAN_NODE_COUNT == 0`) và smoke-test `scenes/combat/combat_arena.tscn --quit-after 60` sạch `0` lỗi.

---

## 14. Giai đoạn 3A — Cầu nối Xuất kích Hub ↔ Combat, Trả thưởng Loot/Save & Sự kiện Ngẫu nhiên Thực chiến

* **Cầu nối Xuất kích Hub $\leftrightarrow$ Phó bản (`SortieDispatchService.gd`, `MissionTerminal.gd`, `PhoneOSManager.gd`, `HubSceneController.gd`, `ZoneTransitionManager.gd`):**
  * Tự động gắn **`MissionTerminal`** lên bàn làm việc `SenseiDesk` tại Tòa nhà Schale (`schale_building.tscn`, `schale_office.tscn`) mà không chỉnh sửa trực tiếp file scene; bấm `[E]` mở tab `MISSIONS` trên MomoTalk OS (`phone_os.tscn`).
  * `SortieDispatchService` quản lý danh mục 3 nhiệm vụ (`Tuần tra Schale` 20 AP, `Quét sạch Kivotos` 30 AP, `Tổng lực Abyss` 40 AP), cho phép chọn Challenge Modifiers (`ENEMY_SPEED_UP`, `NO_REST_ROOMS`, `DOUBLE_BOSS_PHASE`), chọn tối đa 4 Striker + 2 Special (tự động gộp học viên từ `ModLoader`), kiểm tra/trừ AP qua `DayCycleManager` và bàn giao cấu hình qua `ZoneTransitionManager.pending_combat_config`.
* **Thực thi Chiến dịch, Loot, Tiến trình & Sự kiện Ngẫu nhiên (`CombatArenaController.gd`, `SaveManager.gd`, `WaveSpawner.gd`, `DungeonLayoutGenerator.gd`, `ChibiProxyFactory.gd`):**
  * `CombatArenaController` đọc `pending_combat_config`, triển khai đúng đội hình (bao gồm học viên mod), áp dụng Challenge Modifiers (`NO_REST_ROOMS`, địch tăng tốc `1.25x`, Boss tăng 20% HP và đánh 2 vòng AoE đồng thời ở Phase $\ge 2$) và buff Bond vĩnh viễn giới hạn `+10%`.
  * Kích hoạt trực quan 3 sự kiện ngẫu nhiên (`CombatEventManager`): **`ALLY_ARTILLERY`** (vòng cảnh báo xanh cyan 2 giây nổ gây 420 sát thương địch & 500 sát thương tường), **`HIDDEN_BOSS`** (đột kích kèm vật phẩm hiếm), và **`THIRD_PARTY`** (phe thứ 3 giao chiến chéo với cả Striker lẫn địch thường).
  * Thu thập `EnemyUnit.dropped_loot`, cộng Credits theo hệ số Challenge Modifiers, tự động hoàn thành Quest chiến đấu & mở khóa thẻ Roguelike vào `SaveManager` (idempotent, tự đồng bộ lên tab `INVENTORY` của `PhoneOS` và hiển thị chi tiết trên `ResultPanel`).
* **Kiểm thử Xác minh:** Bổ sung bộ test end-to-end `tests/test_phase3a_sortie_loop.gd`; toàn bộ **26/26 suite headless pass** (`0` `SCRIPT ERROR`, `OBJECT_ORPHAN_NODE_COUNT == 0`) và smoke-test cả `combat_arena.tscn` lẫn `schale_building.tscn` sạch lỗi.
* **Backlog Hậu kỳ (sau Phase 4 / Phase 5):** Triển khai các **Phòng Boss Đặc biệt (Total Assault: Binah, Hod, ...)** trên trường `mode: "RAID_BOSS"` đã chừa sẵn trong `SortieDispatchService.MISSION_CATALOG`.








