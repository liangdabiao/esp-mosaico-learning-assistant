# learning_assistant → Vibe Mode 0.2 移植记录（2026-10-25）

来源：`D:\esp-mo\mosaico-learning-assistant-main` v1.0.0（旧版 Recovery ABI 1 / layout 4 / GSP 1.4.0 / GSPC 0.5.0）。
移植后：本工作区 Vibe Mode 0.2（Recovery ABI 2 / GSP 1.5.1 / GSPC 0.6.1）。

## 结论（TL;DR）

**纯配置级移植，应用源码零改动。** 7 组宿主单元测试全部 PASS；固件构建通过
（`learning_assistant.bin` 10.2 MB，ota_0 11.5 MB 余量约 1.2 MB）；ui_apps 资源
包 1.97 MB（分区 3 MB，余量约 1.1 MB）；`prepare_system_update.py` 打包校验通过
（manifest + ota_0 + partition-table + ui_apps 四件套齐全）。

剩余缺口：**真机安装与验收未做**（本机无设备连接）。首次安装必须走
`python mosaico.py iris system-update --project projects/learning_assistant`
（新应用/布局由系统更新携带；绝不能 app-update 跨布局）。

## 改了什么（仅 3 个文件）

| 文件 | 改动 |
|---|---|
| `main/idf_component.yml` | `esp-gsp ==1.4.0` → `==1.5.1` + `override_path: ../../../weiqi-solution/dev/esp-gsp`（本地克隆，CDN 已 403）；`mosaico_module_camera` 补 `version: "*"` |
| `CMakeLists.txt`（根） | 删除旧版 `tools/windows_gspc.py` GSPC 0.5.0 适配器（它钉死旧版，且 explicit GSPC_EXECUTABLE 必须匹配组件版本）；改由共享 `gsp_compiler.cmake` 解析应用版 GSPC 0.6.1（同 poets_survival） |
| `tools/local.ps1` | SDK 从旧仓库 `.codex-runs/esp-idf-mosaico` 改为 `D:\esp-mo\esp-idf`（指纹已核对 `7b9cc1ac…`）；补 `Remove-Item Env:MSYSTEM` 与 `IDF_COMPONENT_CACHE_PATH`（Git Bash 父进程注入 / 组件缓存 git 坑） |

**未改**：`main/` 全部源码、`ui/`（main.json 经 GSPC 0.6.1 重编译成功，264 对象 +
preview canvas bind 无一改名）、`partitions.csv`（不变更布局——immutable 契约只锁
otadata/phy/sysmeta/factory/coredump 五个前缀分区，nvs/ota_0 尺寸/ui_apps 位置随
system-update 携带）、`sdkconfig.*`（本来就是 0.2 惯用法）。

## 为什么能零改动（API 盘点结论）

- GSP 1.5.1 保留了应用用到的全部接口：`esp_gsp_config_t.ttf/ttf_size`、
  `esp_gsp_config_set` + `ESP_GSP_FIELD_ENABLE_IMAGE_CACHE/TRANSITION_SNAPSHOTS`、
  `esp_gsp_esp_lcd_config_t` 的 `display/touch/task_stack_psram/task_stack_size_freetype`、
  `esp_gsp_canvas_push/stop`、`esp_gsp_flush`、`esp_gsp_esp_lcd_pause/resume_paused`。
- UI 资源从"嵌进 app 二进制"改为"ui_apps 分区 mmap + SHA-256 校验"——但
  `ui_bundle_open(esp_gsp_config_t*)` 签名不变（由 `esp_mosaico_gsp_bundle` 封装），
  应用侧无感。
- `iris_screen_mirror_init/attach` 由 `esp_mosaico_gsp_iris` 组件提供（与旧仓库同名）。
- 相机模块 `mosaico_module_camera` API 未见破坏性变更（`buffer_count`、
  `flash_trigger` 等都在；本工作区 BSP 还带了 flash GPIO 修复 a4bfb42）。
- Recovery 契约本来就遵守：`mosaico_idf_project.cmake` + `esp_mosaico_app_recovery`
  + `iris_ota_support_start()` + OTA writer 只在 Vibe Mode。

## 已验证

1. **宿主 7 组单测**（w64devkit gcc 手动编译，`pc/` 目录）：learning_model /
   questions / controls / speech_conversation / orientation_logic / viewport /
   provider_protocol —— 全部 PASS（provider_protocol 用 poets_survival 的
   managed_components cjson 源码）。
2. **固件构建**：`tools/local.ps1 build`（idf-low-noise-build，397.8 s 全量），
   1 条预期警告（factory 分区小于 app bin——应用本来就该进 ota_0，非问题）。
3. **打包校验**：`ui_apps.bin`（1,971,024 B）由 GSPC 0.6.1 从 `ui/main.json` 生成；
   `prepare_system_update.py` 以项目分区表完成 staging，布局校验通过。

## 待办（真机到位后）

1. `python mosaico.py iris status --all --json` / `iris list --details --json`
   确认唯一设备、Vibe Mode 就绪。
2. `python mosaico.py iris system-update --project projects/learning_assistant`
   （会现场构建完整 irisfw 并安装；不要用旧 v1.0.0 包）。
3. 验收：重启后新 Boot ID → 拍题/选题/换题 → 语音提问/确认发送 → 追问 → 朗读 →
   下拉面板/年级；摄像头插件（左侧插槽）与补光在 0.2 BSP 下的表现重点看。
4. 模拟器回放（可选）：`tools/local.ps1 sim`（GSP_SIM_DYNAMIC_FONT 已在脚本内）；
   `pc/` 的 learning_backend/sim_bridge 场景未在本次移植中重跑。

## 复现命令

```powershell
# 构建
powershell -ExecutionPolicy Bypass -File projects\learning_assistant\tools\local.ps1 build
# 打包校验（无设备）
python submodule\esp-mosaico-utils\mosaico-tools\tools\prepare_system_update.py `
  --partition-csv projects\learning_assistant\partitions.csv `
  --partition-table projects\learning_assistant\build\partition_table\partition-table.bin `
  --application projects\learning_assistant\build\learning_assistant.bin `
  --ui-apps projects\learning_assistant\build\ui_apps.bin `
  --stage-dir <stage> --release learning-assistant-vibe02
# 安装（需设备）
python mosaico.py iris system-update --project projects/learning_assistant
```
