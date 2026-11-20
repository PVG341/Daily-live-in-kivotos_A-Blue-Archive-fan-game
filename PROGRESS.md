# PROGRESS.md — Blue Archive 3D Fan Game (Godot 4.7)

* **Ngày tổng hợp:** 2026-11-20
* **Nhánh Git hiện tại:** `master` (HEAD: `591c00e`)
* **Engine & Cấu hình:** Godot `4.7.2-stable` (Forward+ / D3D12, Jolt Physics 3D, GDScript làm ngôn ngữ chính, đã bật addon `godot_ai` MCP và `GDQuest_GDScript_formatter`)
* **Tài liệu nguồn:**
  * Design Spec: [docs/superpowers/specs/2026-11-19-blue-archive-fan-game-design.md](docs/superpowers/specs/2026-11-19-blue-archive-fan-game-design.md)
  * Implementation Plan (16 Tasks): [docs/superpowers/plans/2026-11-19-blue-archive-fan-game.md](docs/superpowers/plans/2026-11-19-blue-archive-fan-game.md)
  * SDD Ledger: `.superpowers/sdd/2026-11-19-blue-archive-fan-game/progress.md`

---

## 1. Mục tiêu và Kiến trúc hiện tại của dự án

### Mục tiêu cốt lõi
Xây dựng một **3D Fan Game Blue Archive** chơi đơn trên PC (Windows), tối ưu cho cả máy yếu (8GB RAM, iGPU ≥ 30–45 FPS ở cấu hình thấp), kết hợp hai trụ cột trải nghiệm:
1. **Phó bản Chiến thuật Chibi 3D (Core Gameplay Loop):** Vượt ngục tối nhiều phòng (*Multi-Room Tactical Roguelike*) góc nhìn Isometric RTS, điều khiển micro từng đơn vị (drag-box, di chuyển, chọn cover, focus fire) kết hợp AI hành vi riêng cho 4 vai trò (**Tanker, Damage Dealer, Healer, Buffer**), 2 slot **Special** tích Cost Bar dùng **EX-Skill**, chọn 1 trong 3 thẻ bài buff giữa các phòng và các **sự kiện chiến đấu ngẫu nhiên** (pháo kích đồng minh, boss ẩn, thế lực thứ 3).
2. **Đời sống Sensei & Tương tác Học viên (Emotional Core):** Khám phá các phân khu học viện bán mở (semi-open hubs + khu phố trung gian + nội cảnh tòa nhà) với góc nhìn chuyển đổi **FPS / TPS**, tương tác cử chỉ chuột trực tiếp (*xoa đầu, nhéo má, đút đồ ăn* kèm blendshape khuôn mặt), mini-game **nấu nướng thư giãn** (không đếm ngược vội vàng, có thanh phát động canh "điểm vàng" lúc nấu thành phẩm), quản lý vòng lặp ngày/AP (có **giới nghiêm 3:00 AM**), giao diện điện thoại **MomoTalk OS**.
3. **Thân thiện Modding & DLC (Hybrid Portable Modding):** Thư mục mod đặt trực tiếp trong thư mục cài đặt game (`<game_dir>/mods/`, fallback `res://mods` trong Editor) để tránh tốn dung lượng ổ C; hỗ trợ nạp file JSON + asset rời lẫn gói `.pck`.

### Kiến trúc & Cấu trúc thư mục hiện tại
Dự án đi theo **Kiến trúc Đa phân hệ Phân tách rời & Hướng dữ liệu (Decoupled Modular & Data-Driven)**:
* **Dual-Model Pipeline:** Model 1:1 (`normal_model.glb`) cho Hub & Tương tác; Model 3D Chibi (`chibi_model.glb`) cho Phó bản chiến thuật.
* **Giao tiếp trung tâm:** `EventBus` autoload kết nối lỏng lẻo giữa các phân hệ `Core/`, `Data/`, `Hub/`, `Combat/`, `Minigames/`, `UI/`.
* **Quy trình phát triển:** Subagent-Driven Development (TDD + Review từng task).

```text
D:\This PC\Project\test
├── project.godot                     # Autoload: EventBus, DayCycleManager, _mcp_game_helper
├── docs/superpowers/
│   ├── specs/2026-11-19-blue-archive-fan-game-design.md
│   └── plans/2026-11-19-blue-archive-fan-game.md
├── scripts/
│   ├── core/
│   │   ├── EventBus.gd               # [Đã commit]
│   │   ├── DayCycleManager.gd        # [Đã commit]
│   │   └── SaveManager.gd            # [Chưa commit - đang dở & có lỗi]
│   └── data/
│       ├── StudentData.gd            # [Đã commit]
│       ├── SkillData.gd              # [Đã commit]
│       ├── ItemData.gd               # [Đã commit]
│       └── RecipeData.gd             # [Đã commit]
├── tests/
│   ├── test_data_models.gd           # [PASS]
│   ├── test_day_cycle.gd             # [PASS]
│   ├── test_save_load.gd             # [FAIL - chưa commit]
│   └── debug_save.gd                 # [File debug tạm - cần dọn]
└── addons/
    ├── godot_ai/                     # MCP kết nối live Godot Editor
    └── GDQuest_GDScript_formatter/
```

*(Các thư mục `scenes/`, `shaders/`, `scripts/hub/`, `scripts/intimacy/`, `scripts/minigames/`, `scripts/combat/`, `scripts/ui/` chưa được khởi tạo — thuộc Task 4 đến Task 16).*

---

## 2. Những tính năng đã hoàn thiện (2 / 16 Tasks)

Cả 2 task đầu tiên đã hoàn thành TDD, qua review chất lượng (verdict `ACCEPT`), commit sạch vào git và test headless đều **PASS**:

1. **Task 1 — Core Architecture, EventBus & Data Resource Definitions** (Commit `bdf94db`):
   * `scripts/data/StudentData.gd`: `CombatRole` (`TANKER`, `DAMAGE_DEALER`, `HEALER`, `BUFFER`), `SquadSlot` (`STRIKER`, `SPECIAL`), đường dẫn dual-model (`normal_model_path`, `chibi_model_path`), chỉ số chiến đấu, bond, `Array[SkillData]`, món ăn/quà yêu thích.
   * `scripts/data/SkillData.gd`, `ItemData.gd` (`ItemType`: `GIFT`, `FOOD`, `INGREDIENT`, `MATERIAL`, `AP_RESTORE`), `RecipeData.gd`.
   * `scripts/core/EventBus.gd`: 9 signal toàn cục (`student_bonded`, `ap_changed`, `day_advanced`, `mod_loaded`, `combat_room_cleared`, `item_picked_up`, `combat_event_triggered`, `save_requested`, `load_requested`), đã đăng ký Autoload trong `project.godot`.
   * Kiểm chứng: `godot --headless -s tests/test_data_models.gd` → `PASS: test_data_models`.

2. **Task 2 — Day Cycle Manager & AP System (kèm giới nghiêm 3:00 AM)** (Commit `591c00e`):
   * `scripts/core/DayCycleManager.gd`: Quản lý `current_day`, `current_hour`, `current_ap`, `max_ap`, `consume_ap()`, `restore_ap()` (clamp theo `max_ap`), `advance_day()` (reset 7:00 AM, hồi đầy AP), `advance_time()` (xử lý vòng 24h và bắt mốc vượt 3:00 AM để kích hoạt `_force_sleep()`: sang ngày mới, dậy muộn `10:30 AM`, phạt 30% AP còn 70%), `get_time_of_day()`, `is_forced_sleep_hour()`.
   * Hỗ trợ dependency injection `event_bus` phục vụ test headless sạch; đã đăng ký Autoload trong `project.godot`.
   * Kiểm chứng: `godot --headless -s tests/test_day_cycle.gd` → `PASS: test_day_cycle`.

---

## 3. Những phần đang viết dở hoặc còn lỗi

### Task 3 — Save/Load System (`SaveManager`) đang làm dở (chưa commit, chưa đăng ký Autoload, chưa review)
Subagent thực hiện Task 3 đã bị hủy giữa chừng, để lại các file untracked (`scripts/core/SaveManager.gd`, `tests/test_save_load.gd`, `tests/debug_save.gd`, `.editorconfig`) cùng các vấn đề cụ thể sau:

1. **Lỗi logic trong `scripts/core/SaveManager.gd` (dòng 118–121):**
   ```gdscript
   if state_data.has("ap"):
       current_ap = int(state_data["ap"])
   if state_data.has("max_ap"):
       current_ap = int(state_data["max_ap"])  # LỖI: ghi đè current_ap thay vì gán max_ap!
   ```
   Khi deserialize mà không gắn `day_cycle_manager`, `current_ap` bị ghi đè thành `max_ap`, còn thuộc tính `SaveManager.max_ap` không được cập nhật.

2. **Test `tests/test_save_load.gd` đang FAIL và bị treo tiến trình headless:**
   * Ở dòng 90, `save_mgr.save_game(99)` ghi trực tiếp vào `user://saves/slot_99.json`. Trong môi trường chạy CLI sandboxed, `user://` trỏ ra thư mục `%APPDATA%` trên ổ C (không có quyền ghi), gây ra `ERROR: SaveManager: Failed to write save file: user://saves/slot_99.json (error 7)` và `Assertion failed` ở dòng 91.
   * Khi `assert()` fail trước `quit(0)`, `SceneTree` trong Godot headless không tự thoát mà treo luôn tiến trình.
   * *Lưu ý thêm:* Dòng 35 gọi `JSON.parse_string("invalid json string")` vẫn hoạt động đúng logic nhưng làm Godot in thông báo `ERROR: Parse JSON failed` ra stderr — nên dùng `JSON.new()` + `json.parse()` để kiểm tra lỗi sạch sẽ hơn.

3. **Chưa hoàn tất cấu hình & dọn dẹp cho Task 3:**
   * `SaveManager` **chưa** được đăng ký trong mục `[autoload]` của `project.godot`.
   * Còn sót file debug tạm `tests/debug_save.gd` (và `.uid`) chưa xóa.
   * File `.editorconfig` đang ở trạng thái untracked (cần quyết định giữ/commit chung hay loại bỏ).
   * Chưa có báo cáo `task-3-report.md`, chưa qua bước review Task 3 và chưa ghi nhận vào SDD ledger.

### Các hạng mục chưa bắt đầu (Task 4 → Task 16)
* **Task 4:** Portable `ModLoader` (`<game_dir>/mods/`, parse JSON & nạp `.pck`, fallback placeholder model).
* **Task 5–6:** Hub Sensei 3D Controller (FPS/TPS), `ZoneTransitionManager`, DoorPortal & Static Interactables (`PickableItem`, `SittableChair`, `ToggleLight`).
* **Task 7–8:** Student Intimacy & Direct Gesture (xoa đầu, nhéo má, đút ăn, `BondProgressTracker`) + Relaxed Cooking Minigame.
* **Task 9–14:** Hệ thống Phó bản Chibi RTS (Isometric Camera, Box-select Micro, `CombatUnit` & `DamageResolver`, 4 Role AIs, Cover Grid, `EnemyUnit`/`WaveSpawner`, `CombatEventManager`, `EXSkillSystem` & Cost Bar, `DungeonLayoutGenerator` & Roguelike Card Draft).
* **Task 15–16:** UI System (Hub HUD, Combat HUD, MomoTalk Phone OS, Pause Menu, Mod Manager UI) + Cel-Shading Shader & `SettingsManager` tối ưu máy yếu.

---

## 4. Đề xuất các bước tiếp theo

Sau khi bạn xác nhận bản tóm tắt này, đề xuất thứ tự triển khai như sau:

1. **Hoàn thiện và chốt dứt điểm Task 3 (`SaveManager`):**
   * Sửa lỗi dòng 121 (`max_ap = int(state_data["max_ap"])`) và đổi `json_to_state()` sang `JSON.new().parse()` để không spam lỗi console khi gặp JSON hỏng.
   * Cập nhật `tests/test_save_load.gd` để gán `save_mgr.save_dir` trỏ vào một thư mục tạm trong workspace (và dọn sạch sau khi chạy test), bổ sung test kiểm tra `SaveManager.max_ap` và đảm bảo thoát cleanly.
   * Xóa file debug thừa `tests/debug_save.gd` (và `.uid`), đăng ký `SaveManager` vào `[autoload]` của `project.godot`.
   * Chạy lại toàn bộ 3 test (`test_data_models`, `test_day_cycle`, `test_save_load`), review Task 3, commit và cập nhật SDD ledger.
   * *(Gợi ý tùy chọn)*: Cân nhắc xem thư mục save game thực tế khi phát hành có nên đi theo hướng **portable** giống thư mục `mods/` (`<game_dir>/saves/`) hay giữ nguyên `user://saves` theo kế hoạch hiện tại.

2. **Tiếp tục thực thi nối tiếp từ Task 4 trở đi theo kế hoạch 16 Task:**
   * **Nhóm nền tảng (Task 4):** Xây `ModLoader` hoàn thiện lớp `Core/`.
   * **Nhóm Hub & Đời sống Sensei (Task 5 → Task 8):** Dựng Controller FPS/TPS, chuyển cảnh, tương tác vật thể/học sinh và nấu nướng.
   * **Nhóm Phó bản Chiến thuật Chibi (Task 9 → Task 14):** Dựng Camera RTS, Combat core, 4 Role AIs, Kẻ địch + Biến cố ngẫu nhiên, EX-Skill và Multi-room Roguelike.
   * **Nhóm Giao diện & Tối ưu (Task 15 → Task 16):** Dựng MomoTalk OS, HUD, Cel-shader và Settings cho máy yếu.

3. **Xác nhận phương thức làm việc tiếp theo:**
   * Tiếp tục theo mô hình **Subagent-driven** (từng task một + reviewer kiểm định trước khi sang task tiếp theo) hay chuyển sang **Native** (triển khai trực tiếp trong phiên này).
