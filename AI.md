# 给 AI 助手的说明

用户想把自己的 Kindle Oasis 3 做成和本仓库作者一样的电子相框。你的任务：按 [README.md](README.md) 带用户完成，每步**先核对再继续**。

**核心原则：USB 只用在安装（README 第 4 步）。** 第 6 步开启无线控制后，读日志、截屏、传文件、改设置、测试修复都由你通过 `mac/kindlectl` 自己完成，不要让用户反复插拔数据线，也不要让用户拍屏幕给你看——用 `kindlectl shot` 自己截。只有以下情况需要用户动手：在 Kindle 上点文库入口、按电源键唤醒/解锁、肉眼确认残影等截图看不到的东西。

## 硬性规则

1. 固件不是 `Kindle 5.18.2.1.1 (482111 015)` → 停止，告诉用户本项目不适用。
2. 不覆盖、不删除用户已有文件。安装/更新只用 `./install.sh`（或 `--update`）；它报冲突就停下问用户。
3. 不碰 `documents/` 里的书，不升级固件、不恢复出厂、不重复越狱、不删除密码设置、不改电源设置。
4. 私钥 `~/.ssh/kindle_album_ed25519` 不外传、不打印、不写进仓库。
5. 越狱和 KOReader 以上游官方页面当前说明为准，不要凭记忆编命令。
6. 改 Kindle 上的程序前，先 `kindlectl pull` 备份原文件。

**接手一台已安装的设备时，第一步运行 `mac/kindlectl check`**：核对 25 个程序文件与仓库一致，并给出无线控制、相册状态和最近日志。你所在的环境如果连不到用户的局域网（例如云端会话），请用户在自己的终端运行这条命令并把输出贴给你。

## 每步检查点

| 步骤 | 核对方式 | 需用户做 |
|---|---|---|
| 0 机型固件 | 数据盘 `system/version.txt` 完全匹配 | 确认是 Oasis 3、没设锁屏密码 |
| 2 越狱 | `.sh` 放进 `documents/` 后在文库显示为可运行入口 | 按官方指南操作 |
| 3 KOReader | 数据盘有 `koreader/luajit`、`koreader/dropbear`；下载包 SHA-256 `3343a916…1bbb` | 在 KOReader 打开一本书 |
| 4 安装 | `install.sh` 输出 `✓`（已装过旧版用 `--update`） | 插线 |
| 5 触屏准备 | 第 6 步连上后：`kindlectl sh 'cat /mnt/us/kindle-album/input-ready.txt'` 首行 `input_helper_ready=yes` | 拔线，点 Album Input Setup |
| 6 无线 | `kindlectl connect <IP>` 显示 `✓ 已连接` | 点 Album WiFi On，告诉你屏幕上的 IP |
| 7 首次打开 | `kindlectl start` → `kindlectl status` 显示运行中 → `kindlectl shot` 看画面 → `kindlectl logs` | README 第 7 节的锁屏/唤醒/USB 验收 |
| 8 照片 | `kindlectl add …` 输出「导入完成」；`status` 里播放列表张数增加 | 告诉你照片在哪个文件夹 |

## 关键路径（Kindle 内部）

| 内容 | 路径 |
|---|---|
| 数据盘（USB 看到的那个） | `/mnt/us` |
| 相册程序 | `/mnt/us/kindle-album/fullscreen-v2/app/` |
| 相册数据：播放列表、间隔、模式、生成图 | `/mnt/us/kindle-album/fullscreen-v2/data/`（`slides.txt` `interval.txt` `mode.txt` `assets/`） |
| 启动日志 / 会话日志 | `/mnt/us/kindle-album/fullscreen-v2/launch.log`、`data/session.log`（每次启动重写） |
| 运行时目录（只在运行时存在，RAM） | `/tmp/kindle-album-session/`（`pid`、`frame-state`、`import-log`） |
| 原图 | `/mnt/us/Photos/` |
| 触屏读取器 | `/var/local/kindle-album/app/touch-reader` |
| 无线控制 | 脚本 `/mnt/us/kindle-album/wireless/`，状态 `wireless/status.txt`；运行目录 `/var/local/kindle-album/ssh/`（dropbear 副本、公钥、主机密钥、`autostart` 标记） |

## 排错

**连不上**：Kindle 锁屏/休眠时 WiFi 是断的。请用户按电源键唤醒、解锁，几秒后重试。仍不行，请用户在文库点 Album WiFi On，看屏幕上的 IP 是否变了。失败原因会写在数据盘 `kindle-album/wireless/status.txt`（这时才需要 USB 读一次）。

**相册起不来**：`kindlectl logs` 看 launch.log，再对照 `kindle/kindle-album/fullscreen-v2/app/album.sh` 开头的启动检查（退出码 77–101 各对应一项）：
- 存在 `/var/local/system/userpasswdenabled`（设了密码）→ 96
- 触屏读取器缺失 / 哈希不符 → 94 / 95（回到第 5 步）
- `data/project-id` 不对 → 79；帧缓冲 / 旋转 → 81 / 82
- `data/slides.txt` 为空、超 500 行或缺少对应 `assets/*.png` → 83–85
- `data/interval.txt` 不是 10/30/60/300 → 86；`data/mode.txt` 不是 crop/contain → 93
- `preventScreenSaver` 不是 0 → 89；电源状态不是 active → 97

用 `kindlectl sh 'sh -x /mnt/us/kindle-album/fullscreen-v2/app/album.sh 2>&1 | head -50'` 可以看到停在哪一行（注意：检查都通过时它会真的启动相册，之后用 `kindlectl stop` 停掉）。

**导入不生效**：导入由 `app/photo-import.sh` 调用 `/mnt/us/koreader/luajit` 运行 `photo-import.lua`，只在相册启动时扫描 `Photos/` 第一层的 `.jpg/.jpeg/.png`。结果写在 `session.log` 的 `photo_import_completed=… added= failed= duplicate=` 行，详情在运行时 `import-log`。导入前旧 `slides.txt` 备份在 `data/import-backups/`。

**修改并测试代码**：`kindlectl pull` 备份 → 本地改 → `kindlectl push` 到原路径 → `kindlectl restart` → `kindlectl logs` + `kindlectl shot` 验证。同时把改动提交回本仓库的 `kindle/` 目录，保持仓库与设备一致。

**卡死**：`kindlectl stop`；连不上就请用户按电源键或插 USB（相册会自动退出）；仍不行按住电源键约 40 秒重启。

更深入的原理（锁屏交接、RAM 缓存清理、USB 交还）见原始仓库 `docs/05-debugging-method.md`：https://github.com/judeyang/kindle-oasis-photo-frame
