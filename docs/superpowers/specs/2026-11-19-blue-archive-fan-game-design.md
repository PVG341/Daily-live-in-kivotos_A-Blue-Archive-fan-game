# Tài Liệu Thiết Kế (Design Document): Blue Archive 3D Fan Game

* **Ngày cập nhật:** 2026-11-19
* **Engine:** Godot Engine 4.7
* **Thể loại:** 3D Anime RPG / Tactical Squad Roguelike & Student Intimacy Simulator
* **Nền tảng mục tiêu:** PC (Windows), tối ưu hóa diện rộng cho cả máy cấu hình yếu (iGPU).

---

## 1. Tầm Nhìn & Mục Đích Dự Án (Intent & Why)

Dự án là một fan game tri ân cộng đồng người hâm mộ tựa game **Blue Archive (BA)**. Trò chơi kết hợp hài hòa giữa:
1. **Trải nghiệm chiến thuật phó bản Chibi 3D (Core Gameplay Loop):** Thử thách vượt ngục tối nhiều phòng (Multi-room Roguelike Dungeon) thời gian thực với chiều sâu chiến thuật RTS micro-management, sử dụng trực tiếp các mô hình 3D Chibi trích xuất từ BA.
2. **Đời sống Sensei & Gắn kết học viên (Emotional Core):** Khám phá các khu học viện quen thuộc dưới góc nhìn 3D FPS/TPS với mô hình tỷ lệ chuẩn (1:1 Normal Models), tương tác vật lý sống động (xoa đầu, nhéo má, nấu nướng và đút thức ăn cho học sinh).
3. **Nền tảng thân thiện với cộng đồng modding:** Cho phép người chơi tự do thêm trang phục, học sinh mới, kịch bản hội thoại, hoặc tự đóng gói bản đồ/phó bản mở rộng (DLC).

---

## 2. Mục Tiêu, Phi Mục Tiêu & Chống Mục Tiêu (Goals, Non-Goals, Anti-Goals)

### Goals
* **Vòng lặp kép gắn kết chặt chẽ:** Đi phó bản kiếm nguyên liệu/quà tặng $\rightarrow$ Nấu nướng, tặng quà & tương tác tăng Bond Level $\rightarrow$ Mở khóa kỹ năng nội tại, skin, câu chuyện MomoTalk và buff chiến đấu.
* **Cơ chế Điều khiển RTS Micro & AI Vai trò (Role AI):** Người chơi có thể chọn từng đơn vị (hoặc kéo chuột bao vùng) để chỉ định chỗ nấp, di chuyển, bắn mục tiêu cụ thể; khi không có lệnh cưỡng chế, AI của 4 vai trò (Tanker, Damage Dealer, Healer, Buffer) sẽ tự động vận hành thông minh.
* **Tương tác cử chỉ chuột đa dạng (Direct Gesture):** Tái hiện sống động các tương tác thân mật (xoa đầu, nhéo má, đút đồ ăn) với phản hồi biểu cảm realtime trên khuôn mặt và âm thanh.
* **Mini-game Nấu nướng (Cooking Minigame):** Thu thập nguyên liệu qua phó bản/công việc, chế biến các món ăn đặc trưng của Kivotos để thưởng thức cùng học sinh.
* **Hỗ trợ Modding linh hoạt (Hybrid Modding):** Hỗ trợ nạp file cấu hình JSON rời và nạp gói mã nguồn mở rộng `.pck`.
* **Khả năng mở rộng bản đồ bán mở (Semi-open Hubs):** Chia tách thành phố Kivotos thành các phân khu học viện và khu phố trung gian, có thể bước vào các tòa nhà nội cảnh.
* **Tối ưu máy yếu:** Hỗ trợ tùy chỉnh sâu về đồ họa (khoảng cách hiển thị, render scale, hiệu ứng) đảm bảo mượt mà trên máy không có card đồ họa rời.

### Non-Goals
* Không cố gắng xây dựng một bản đồ thế giới mở liền mạch không ngắt quãng (Full Seamless Open World) quy mô toàn bộ Kivotos để tránh lãng phí hiệu năng và quá tải bộ nhớ.
* Không làm hệ thống gacha hút máu bằng tiền thật; toàn bộ học sinh và trang phục được mở khóa thông qua gameplay, tiến trình chơi và mod.
* Không làm hệ thống mạng nhiều người chơi (Multiplayer/Co-op) trong giai đoạn đầu; tập trung toàn lực vào trải nghiệm chơi đơn (Single-player) mượt mà và ổn định.

### Anti-Goals
* Tránh biến việc tương tác học sinh thành các nút bấm khô khan thiếu cảm xúc hoặc chỉ là hình ảnh 2D tĩnh.
* Tránh gắn chặt các logic chiến đấu vào nhân vật khám phá thế giới (không dùng chung controller hay scene giữa Hub và Combat).
* Tránh khóa cứng dữ liệu nhân vật vào mã nguồn khiến việc modding phải build lại toàn bộ game.

---

## 3. Ràng Buộc Kỹ Thuật (Constraints)
* **Engine:** Godot 4.7 (Forward+ / Compatibility fallback).
* **Pipeline Mô hình Kép (Dual-Model Pipeline):** 
  * Khám phá thế giới / Tương tác: Mô hình tỷ lệ chuẩn 1:1 (`normal_model.glb`) với đầy đủ facial blendshapes.
  * Chiến đấu phó bản: Mô hình Chibi 3D (`chibi_model.glb`).
* **Hiệu năng:** Máy yếu (RAM 8GB, iGPU như Intel UHD 620 hoặc Vega 3/7/8) phải duy trì ổn định $\ge 30-45$ FPS ở mức thiết lập đồ họa thấp.

---

## 4. Các Hướng Tiếp Cận Kiến Trúc (Architectural Approaches)

* **Hướng 1: Kiến trúc Đa phân hệ Phân tách rời & Hướng dữ liệu (Decoupled Modular & Data-Driven) — *Đã chọn*:**
  * Tách biệt rõ ràng thành các module: `Core/`, `Hub/`, `Combat/`, `Data/`, `UI/`, `Minigames/`.
  * Tách biệt mô hình dữ liệu qua `StudentData` (Resource / JSON) hỗ trợ đồng thời cả Normal Model và Chibi Model.
  * *Lý do chọn:* Cách ly hoàn toàn lỗi, dễ bảo trì, giải quyết hoàn hảo bài toán Modding và kiểm soát tải bộ nhớ trên máy yếu.

---

## 5. Thiết Kế Chi Tiết Từng Phân Hệ (Subsystem Design)

### 5.1. Phân Hệ Đời Sống & Thế Giới Bán Mở (Hub World System)
* **Cấu trúc Không gian & Vòng đời NPC:**
  * **Học viện lớn (Major Academy Zones):** Abydos, Gehenna, Millennium, Trinity, Schale...
  * **Khu vực trung gian (Sub-zones):** Tuyến phố, trạm trung chuyển xe buýt, khu thương mại Angel 24 nối giữa các học viện.
  * **Vòng đời xuất hiện NPC (Zone Spawner):** Mỗi phân khu chỉ nạp các học sinh thuộc trường đó (tránh tràn RAM). Các học sinh được mời hoặc mở khóa sẽ xuất hiện thêm tại Văn phòng Schale và Căn tin.
  * **Nội cảnh tòa nhà (Interiors):** Phòng làm việc Schale, lớp học, câu lạc bộ, cửa hàng tiện lợi, nhà bếp Schale. Chuyển cảnh vào tòa nhà qua trigger cửa tương tác (Fade transition nhanh).
* **Điều khiển Sensei:**
  * Chuyển đổi linh hoạt giữa góc nhìn thứ nhất (FPS) và góc nhìn thứ 3 (TPS) (phím `V` hoặc con lăn chuột).
  * Di chuyển WASD, `Space` nhảy, `Shift` chạy nhanh, `E` mở menu tương tác đối tượng/nhân vật.
  * Khi lại gần ghế/vật thể tĩnh: Hiển thị prompt ngồi, bật/tắt đèn, bật đài phát thanh; có thể nhặt các vật phẩm/item tĩnh rải rác trên bản đồ (nguyên liệu, nước tăng lực, quà tặng...).
* **Vòng lặp Lượt Hoạt Động (AP & Day Cycle):**
  * Mỗi ngày trong game có lượng AP nhất định (mặc định: 100 AP).
  * Đi lại tự do, ngắm cảnh, trò chuyện thông thường: **0 AP**.
  * Đi phó bản chiến thuật: Tiêu hao AP theo độ khó (20 - 40 AP).
  * Làm việc / Nấu nướng: Tiêu hao AP (thưởng tài nguyên, đồ ăn, tiền).
  * Hết AP: Chọn "Qua ngày mới" (hồi đầy AP) hoặc dùng vật phẩm hồi AP.
  * **Cơ chế Buộc qua ngày (3AM Curfew):** Nếu đồng hồ trong game chạm mốc 3:00 AM, Sensei bị buộc đi ngủ. Hậu quả: năng lượng (AP) hôm sau bị giảm do mệt mỏi (phạt ~30%), thời gian thức dậy sẽ bị đẩy tới gần cuối buổi sáng (~10:30 AM thay vì 7:00 AM bình thường).

### 5.2. Hệ Thống Tương Tác Học Viên & Mini-game Ăn Uống (Intimacy & Dining)
* **Giao diện Kích hoạt:**
  * Khi bấm `E` vào học sinh (model 1:1), dropdown menu xuất hiện: *Trò chuyện*, *Tặng quà*, *Xoa đầu*, *Nhéo má*, *Cho ăn (Đút món)*, *Mở MomoTalk*, *Đổi trang phục*.
* **Cơ chế Cử chỉ Trực tiếp (Direct Gesture Minigame):**
  * Camera chuyển nhanh sang góc cận cảnh khuôn mặt (Portrait Close-up). Con trỏ chuột biến thành bàn tay Sensei.
  * **Hitbox & Raycast:**
    * *Đỉnh đầu:* Kéo chuột qua lại $\rightarrow$ kích hoạt blendshape mắt cười/híp, animation lắc đầu nhẹ, hiệu ứng tim bay, tăng thanh Hảo Cảm (Bond Gauge).
    * *Gò má:* Click giữ và kéo $\rightarrow$ kích hoạt blendshape phồng má/biến dạng má nhẹ, biểu cảm đỏ mặt hoặc hờn dỗi đáng yêu.
    * *Cho ăn (Feeding Gesture):* Chọn món ăn từ túi $\rightarrow$ đưa con trỏ chuột gắp thức ăn lại gần miệng học sinh $\rightarrow$ học sinh há miệng đón nhận, biểu cảm thỏa mãn, âm thanh nhai và voice line khen ngon $\rightarrow$ tăng điểm Bond lớn và nhận buff chiến đấu tạm thời.
  * Lồng tiếng phản ứng (Reaction Voice clips) và bong bóng thoại phụ đề bên cạnh.
  * **Tùy biến Mod:** Modder có thể thêm tương tác mới bằng cách định nghĩa Collider + Animation + Voice trong file cấu hình JSON.

### 5.3. Mini-game Nấu Nướng (Cooking Minigame)
* **Vị trí:** Căn bếp Văn phòng Schale hoặc CLB Nghiên cứu Ẩm thực (Gehenna).
* **Cơ chế Thư giãn (Relaxed Pace):**
  * Sử dụng nguyên liệu thu thập được từ phó bản, nhặt trong thế giới hoặc từ mini-game câu cá (thịt, rau, gia vị, hải sản...).
  * Không tạo áp lực thời gian (không đếm ngược vội vàng): Người chơi thực hiện các bước sơ chế (chặt rau, thái thịt, trộn nguyên liệu theo công thức) một cách chậm rãi, thư giãn.
  * **Cơ chế Phát Động Nấu Thành Phẩm (Cook Timing Indicator):** Ở giai đoạn nấu/xào trên bếp, có thanh chỉ báo dao động nhịp nhàng (hoặc hiệu ứng bốc khói/sôi sùng sục) báo hiệu thời điểm món chín tới. Người chơi ấn dừng đúng "điểm vàng" (Sweet Spot) để cho ra kết quả tốt nhất.
  * Chất lượng món ăn (Thường, Ngon, Hoàn hảo) quyết định chỉ số hồi phục và mức tăng độ thân thiết khi đem đút cho học sinh.

### 5.4. Phân Hệ Phó Bản Chiến Thuật (Chibi Multi-Room Tactical Roguelike)
* **Mô hình & Camera:**
  * Toàn bộ đội hình và kẻ địch sử dụng mô hình Chibi 3D.
  * Camera Isometric phong cách RTS: Panning WASD / mép màn hình, xoay góc tự do và zoom xa gần.
* **Cấu trúc Multi-Room Dungeon:**
  * Phó bản chia thành chuỗi các phòng (Rooms) nối với nhau bằng hành lang và cửa khóa.
  * Dọn sạch kẻ địch trong phòng $\rightarrow$ Cửa mở ra phòng tiếp theo $\rightarrow$ Màn hình hiển thị 3 Thẻ bài Roguelike ngẫu nhiên để người chơi chọn nâng cấp trước khi tiến vào phòng kế.
  * Máu của đội hình được bảo toàn giữa các phòng trong cùng một lượt chạy (run).
* **Cơ chế Điều khiển RTS Micro (Unit Micro-management):**
  * Kéo chuột quét hộp (Drag-box) hoặc click vào ảnh chân dung để chọn 1 hoặc nhiều học sinh.
  * Click chuột phải để ra lệnh di chuyển đến vị trí cụ thể hoặc áp sát chướng ngại vật (Cover Spot).
  * Click chuột phải vào mục tiêu địch để ra lệnh tập trung hỏa lực (Focus Fire).
  * Lệnh giữ vị trí / ngừng bắn (Hold Position / Hold Fire).
* **Hệ Thống AI Vai Trò (Combat Role AI khi không có lệnh cưỡng chế):**
  * **Tanker:** Tự động tìm vật cản tuyến đầu, thu hút hỏa lực và khiêu khích địch.
  * **Damage Dealer (DPS):** Tự tìm góc bắn thoáng (Line of Sight), ưu tiên tiêu diệt mục tiêu yếu máu hoặc mục tiêu Sensei chỉ định.
  * **Healer:** Tự động giữ vị trí an toàn phía sau, ưu tiên cứu chữa/tạo khiên cho đồng đội có % HP thấp nhất.
  * **Buffer / Debuffer:** Tự động định vị sao cho phạm vi buff bao phủ nhiều đồng đội nhất, tung kỹ năng làm suy yếu đối phương.
* **Hỗ trợ từ Special & EX-Skill:**
  * 2 Special ngoài sân tích lũy Cost bar.
  * Kéo thả vòng tròn EX-Skill lên chiến trường khi đủ Cost.
* **Sự Kiện Chiến Đấu Ngẫu Nhiên (Random Battlefield Events):**
  * Trong quá trình vượt phòng, các sự kiện ngẫu nhiên có thể bộc phát để thay đổi nhịp độ và cục diện trận đấu, tránh sự lặp lại đơn điệu:
    * *Pháo kích Đồng minh (Ally Artillery):* Vùng oanh tạc chi viện dội hỏa lực xuống cụm địch sau 2 giây cảnh báo.
    * *Boss Ẩn Đột Kích (Hidden Boss):* Một Boss/Elite phụ bất ngờ xuất hiện giữa phòng cùng hiệu ứng rung lắc màn hình và rơi loot quý.
    * *Thế Lực Thứ Ba Can Thiệp (Third-Party Intervention):* Một nhóm chiến binh phe thứ ba xuất hiện tấn công cả học sinh lẫn kẻ địch.
  * Ràng buộc: Không kích hoạt sự kiện trong 15 giây đầu của phòng hoặc khi bảng chọn thẻ bài đang mở.

### 5.5. Giao Diện Người Dùng (UI & MomoTalk OS)
* **HUD Tối giản trong Hub:** Mini-map / La bàn, Giờ trong ngày & Ngày, Thanh AP hiện tại, Tiền / Tài nguyên.
* **Điện thoại Sensei (MomoTalk OS) - Phím `Tab`:**
  * *Túi đồ (Inventory):* Vật phẩm, thức ăn đã nấu, quà tặng, vé hồi AP.
  * *Bản đồ toàn thể (World Map):* Xem toàn bộ Kivotos và thực hiện Fast Travel.
  * *Danh bạ Học sinh (Student Contacts):* Xem hồ sơ, mức độ thân thiết (Bond Level), thay đổi trang phục (Skin Selector).
  * *Nhật ký Nhiệm vụ (Missions).*
  * *Trình phát nhạc (BGM Player):* Chọn phát các bản nhạc nền Blue Archive.
* **Menu Hệ thống (Phím `ESC`):** Tiếp tục, Lưu/Tải game, Cài đặt, Thoát.

### 5.6. Kiến Trúc Hỗ Trợ Modding & DLC
* **Vị trí Thư mục Mod (Portable Mod Directory):**
  * Nằm trực tiếp trong thư mục cài đặt game (`<game_dir>/mods/` thay vì lưu trong thư mục `user://` ổ C), sử dụng `OS.get_executable_path().get_base_dir().path_join("mods")`.
  * Giúp người chơi cài đặt game trên bất kỳ ổ đĩa nào (D, E...) mà không lo chiếm dụng dung lượng phân vùng hệ thống (ổ C).
  * Cấu trúc thư mục chuẩn:
    ```text
    <game_dir>/mods/
    ├── mod_info.json
    ├── students/        # JSON định nghĩa chỉ số, role, thoại, cử chỉ
    ├── models/          # Chứa normal_model.glb và chibi_model.glb
    ├── skins/           # File trang phục thay thế .glb, texture .png
    ├── audio/           # File voice, BGM .ogg
    └── packages/        # File .pck chứa map, script, phó bản mới
    ```
* **Data-driven Schema:** File JSON định nghĩa liên kết cả 2 model (1:1 và Chibi) cho mỗi học sinh.
* **Mod Manager In-game:** Bật/tắt mod trực tiếp, kiểm tra xung đột mod và quản lý các gói DLC miễn phí.

### 5.7. Tối Ưu Hóa & Cài Đặt Đồ Họa Cho Máy Yếu
* **Shader:** Cel-shading tối ưu (Toon Shader ánh sáng nhẹ + Sobel Outline mượt mà).
* **Tùy chỉnh trong Menu Settings:**
  * Render Resolution Scale (720p scale 1080p).
  * Draw Distance (Khoảng cách render trong Hub).
  * Shadow Quality (Tắt, Thấp, Trung bình, Cao).
  * Toggles: Bật/tắt Bloom, Depth of Field, hiệu ứng hạt.

---

## 6. Lộ Trình Phân Kỳ Phát Triển (Milestones)

1. **Giai đoạn 1 (Core & Hub Intimacy):** Dựng khung Godot 4, Player Controller FPS/TPS, nạp model 1:1, hệ thống tương tác cử chỉ chuột (xoa đầu, nhéo má, đút ăn) và mini-game nấu nướng.
2. **Giai đoạn 2 (Combat RTS Micro & Multi-Room):** Dựng camera Isometric RTS, cơ chế điều khiển chọn đơn vị (box select / micro), hệ thống Cover, AI 4 vai trò (Tanker, DPS, Healer, Buffer) và logic chuyển phòng Multi-room Chibi.
3. **Giai đoạn 3 (Loop & Roguelike):** Tích hợp chu kỳ ngày/AP, hệ thống thẻ bài ngẫu nhiên giữa các phòng, tích hợp menu MomoTalk và Save/Load.
4. **Giai đoạn 4 (Modding Engine & Optimization):** Dựng ModLoader nạp JSON và file `.pck`, menu cài đặt đồ họa tối ưu cho máy yếu.
5. **Giai đoạn 5 (Content & Polish):** Mở rộng các phân khu học viện (Abydos, Gehenna, Trinity...), hoàn thiện âm thanh và hiệu ứng.
