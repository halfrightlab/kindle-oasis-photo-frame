# 给 AI 助手的说明

用户想把自己的 Kindle Oasis 3 做成和本仓库作者一样的电子相框。你的任务：按 [README.md](README.md) 第 0–7 步带用户完成，每步都**先核对再继续**。

你通常只能通过电脑看到 Kindle 的 USB 数据盘（macOS `/Volumes/Kindle`，Linux `/media/<user>/Kindle`；Kindle 内部同一分区叫 `/mnt/us`）。Kindle 上的点击操作由用户完成。

## 硬性规则

1. 固件不是 `Kindle 5.18.2.1.1 (482111 015)`（见数据盘 `system/version.txt`）→ 停止，告诉用户本项目不适用。
2. 不覆盖、不删除用户已有文件。复制用 `./install.sh <盘路径>`；它报冲突就停下问用户。
3. 不碰 `documents/` 里的书、不升级固件、不恢复出厂、不重复越狱、不删除密码设置。
4. “文件复制成功”不等于“在 Kindle 上运行成功”。每步以下面的检查点为准，并请用户描述屏幕实际看到什么。
5. 越狱和 KOReader 以上游官方页面的当前说明为准，不要凭记忆编命令。

## 每步检查点

| 步骤 | 在数据盘上核对 | 需用户确认 |
|---|---|---|
| 0 机型固件 | `system/version.txt` 内容完全匹配 | 机型是 Oasis 3；没设锁屏密码 |
| 1 备份 | — | 已把书和笔记拷到电脑 |
| 2 越狱 | `documents/` 下有 JAILBROKEN 相关文档 | `.sh` 放进 `documents/` 后能在文库点开运行 |
| 3 KOReader | `koreader/luajit`、`koreader/koreader.sh` 存在；下载包 SHA-256 为 `3343a916…1bbb` | 能在 KOReader 打开一本书 |
| 4 复制 | `install.sh` 输出 `✓`；`kindle-album/touch-reader` SHA-256 为 `aea0e2ce863b166654b7a9ff7122d1734d18856d5a864f259ffe8c801c56ddf7` | — |
| 5 触屏准备 | `kindle-album/input-ready.txt` 首行 `input_helper_ready=yes`；然后移走 `documents/Kindle_Album_Input_Setup.sh` | 已在 Kindle 点过 Album Input Setup |
| 6 首次打开 | `kindle-album/fullscreen-v2/launch.log`、`data/session.log` 有新内容 | README 第 6 节四项验收全部通过 |
| 7 照片 | 原图在 `Photos/` 第一层；之后 `data/slides.txt` 出现 `img-…` 行 | 屏幕在播放自己的照片 |

## 排错

**Input Setup 没生成 `input-ready.txt`**：脚本 `kindle/documents/Kindle_Album_Input_Setup.sh` 按顺序检查 root、固件、`kindle-album/project-id`、帧缓冲 8 位、旋转为 0、`/dev/input/event8` 可读、读取器哈希，任一不满足就静默退出。逐项对照找原因；如 `/var/local/kindle-album/app/touch-reader` 已存在但哈希不同，它会拒绝覆盖——这需要用户决定，不要自行删除。

**Album Fullscreen 打开即退出**：读 `kindle-album/fullscreen-v2/launch.log`，再对照 `kindle/kindle-album/fullscreen-v2/app/album.sh` 开头的启动检查（退出码 77–101 各对应一项）：
- 存在 `/var/local/system/userpasswdenabled`（设了密码）→ 96
- 触屏读取器缺失 / 哈希不符 → 94 / 95（回到第 5 步）
- `data/project-id` 不对 → 79；帧缓冲 / 旋转 → 81 / 82
- `data/slides.txt` 为空、超 500 行或缺少对应 `assets/*.png` → 83–85
- `data/interval.txt` 不是 10/30/60/300 → 86；`data/mode.txt` 不是 crop/contain → 93

**导入不生效**：导入由 `app/photo-import.sh` 调用 `/mnt/us/koreader/luajit` 运行 `photo-import.lua`；没有 KOReader 就无法导入。只认 `.jpg/.jpeg/.png`，以 `.` 开头的文件忽略。导入前旧的 `slides.txt` 会备份到 `data/import-backups/`。

**卡死**：让用户按电源键或插 USB；仍不行按住电源键约 40 秒重启。

更深入的原理（锁屏交接、RAM 缓存清理、USB 交还）见原始仓库 `docs/05-debugging-method.md`：https://github.com/judeyang/kindle-oasis-photo-frame
