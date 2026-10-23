# Kindle Oasis 3 → 离线电子相框

把 Kindle Oasis 3 变成全屏轮播照片的相框：按电源键正常锁屏休眠，唤醒后接着播同一张；插 USB 自动退出；原生阅读和 KOReader 照常可用。

照着下面 7 步做完，你的设备就和作者的一样。也可以把这个仓库直接交给 AI，让它按 [AI.md](AI.md) 带你做。

---

## 0. 先确认能不能用（不满足就停）

| 条件 | 怎么看 |
|---|---|
| 机型：**Kindle Oasis 3（2019，第 10 代）** | 设置 → 设备选项 → 设备信息 |
| 固件：**5.18.2.1.1** | 同上。不是这个版本就不要继续 |
| **没有设置锁屏密码** | 有密码时相册会拒绝启动 |
| 屏幕方向为默认竖屏 | 不要旋转 |
| 一台电脑 + 能传数据的 USB 线 | 插上后电脑能看到 `Kindle` 盘 |

> 其他型号、其他固件都**没验证过**，外观相近也不能套用。

## 1. 备份

插上电脑，把 `documents/` 里你在乎的书和笔记拷一份到电脑。

## 2. 越狱

按 KindleModding 官方流程用 **SpiderCat** 越狱：

1. 打开 [kindlemodding.org/jailbreaking](https://kindlemodding.org/jailbreaking/)，确认你的机型/固件可用。
2. 按 [SpiderCat 指南](https://kindlemodding.org/jailbreaking/SpiderCat/) 操作（把入口书放进 `documents/`，在 Kindle 上打开，等它跑完重启）。
3. 成功标志：文库出现 `JAILBROKEN` 文档，并且放进 `documents/` 的 `.sh` 文件会显示成可以点开运行的入口（Scriptlets）。

完成后 `SpiderCat`、`JAILBROKEN` 两个文库条目可以移走。**不要重复越狱。**

## 3. 安装 KOReader

相册导入照片要借用 KOReader 的图片库，所以必须装。

1. 下载 [KOReader v2026.07.1](https://github.com/koreader/koreader/releases/tag/v2026.07.1) 里的 `koreader-kindlehf-v2026.07.1.zip`
   SHA-256：`3343a916d12f36c01b59df1f65bd83ff5616e6c2a4dfbe919e7fa1400b8b1bbb`
2. 解压，把里面的 `koreader/` 和 `extensions/` 复制到 Kindle 根目录（按 [官方说明](https://github.com/koreader/koreader/wiki/Installation-on-Kindle-devices)）。
3. 弹出、拔线，在 Kindle 上打开 KOReader，随便开一本书确认能翻页。

## 4. 复制相册文件

本仓库的 `kindle/` 目录**就是 Kindle 数据盘的结构**，把里面的东西放进 Kindle 根目录即可。

**方式 A（推荐，macOS / Linux）**：在仓库目录执行

```sh
./install.sh /Volumes/Kindle
```

脚本会检查固件和 KOReader，只新增文件；发现同名但内容不同的文件会直接停下，不覆盖任何东西。

**方式 B（手动 / Windows）**：把 `kindle/` 里的文件逐个复制到 Kindle 对应位置：

```
documents/Kindle_Album_Fullscreen_Start.sh   ← 文库入口「Album Fullscreen」
documents/Kindle_Album_Fullscreen_Stop.sh    ← 备用停止
documents/Kindle_Album_Input_Setup.sh        ← 一次性准备，用完移走
kindle-album/project-id
kindle-album/touch-reader
kindle-album/fullscreen-v2/app/   （整个目录）
kindle-album/fullscreen-v2/data/  （整个目录，自带 3 张测试图）
Photos/                           （新建空文件夹）
```

> ⚠️ macOS 访达里**不要把 `kindle/documents` 文件夹整个拖到 Kindle 上**，那会替换掉整个 `documents`，书会没了。要么用 `install.sh`，要么打开文件夹只拖里面的 `.sh` 文件。

## 5. 在 Kindle 上做一次触屏准备

1. 安全弹出、拔线。
2. Kindle 文库里点 **Album Input Setup**（几秒内结束，屏幕不会有明显变化）。
3. 重新插电脑，确认 `kindle-album/input-ready.txt` 存在且第一行是 `input_helper_ready=yes`。
4. 把 `documents/Kindle_Album_Input_Setup.sh` 移出 Kindle（以后不用了）。

没有生成 `input-ready.txt`：说明某项检查没过（不是 root / 固件不符 / 文件不全 / 屏幕旋转了）。不要反复越狱，看第 8 节。

## 6. 第一次打开 + 验收

弹出、拔线，文库点 **Album Fullscreen**。应该看到全屏测试图，然后依次确认：

- [ ] 轻触一下出现底部按钮，5 秒不动自动隐藏
- [ ] 按电源键 → 正常锁屏 → 等一会儿真正休眠
- [ ] 再按电源键唤醒、解锁 → 回到**同一张**照片，过一个间隔后自动换下一张
- [ ] 相册开着时插 USB → 自动退出，电脑能看到 Kindle 盘

全部通过，就和作者的设备一样了。

## 7. 放自己的照片

1. 插电脑，把 **JPG / JPEG / PNG 原图**放进 Kindle 根目录的 `Photos/`（只认第一层，不读子文件夹）。
2. 弹出、拔线，打开 **Album Fullscreen**。屏幕显示“正在导入照片”，完成后自动播放。

- 方向、灰度、缩放都在 Kindle 上处理，原图不动；重复照片只导入一次。
- 第一次导入自己的照片后，测试图自动从播放列表中移除。
- 限制：单张 ≤ 64 MB，最多 500 张；HEIC 不支持（改扩展名也不行）；坏图会跳过。
- 从 `Photos/` 删除原图**不会**从相册中删除（目前没有删除功能）。

---

## 日常使用

| 操作 | 方法 |
|---|---|
| 打开相册 | 文库点 **Album Fullscreen** |
| 显示按钮 | 轻触照片一次（按钮隐藏时轻触不会误操作） |
| 上一张 / 下一张 | 底部按钮 |
| 换图间隔 | 按钮循环 10 / 30 / 60 / 300 秒 |
| 裁切 / 完整 | 裁切 = 填满屏幕；完整 = 显示整张留白 |
| 退出 | 轻触后点右下 **退出阅读**；不行就点文库的 **Album Fullscreen Stop** |
| 看书 | KOReader，或原生阅读器，互不影响 |

注意：设备真正深睡时不会定时唤醒换图，这是有意的（省电）。

## 8. 出问题怎么办

| 现象 | 处理 |
|---|---|
| 点 Album Fullscreen 没反应、立刻回文库 | 插电脑看 `kindle-album/fullscreen-v2/launch.log`。最常见：设了锁屏密码、没做第 5 步、文件没复制全 |
| 导入后没出现新照片 | 确认在 `Photos/` 第一层、扩展名正确、不是 HEIC |
| 触屏完全没反应 | 先按电源键让系统锁屏/唤醒；或插 USB，相册会自动退出 |
| 彻底卡死 | 按住电源键约 40 秒强制重启（确保没有正在拷贝的文件） |
| 想卸载 | 删除 `documents/Kindle_Album_*.sh`、`kindle-album/` 即可；`Photos/` 里的原图自行处理 |

不要为修相册去重新越狱、升级固件或恢复出厂。

## 当前验证状态（如实说明）

- ✅ 锁屏 / 休眠 / 唤醒续播 / 自动换图 / USB 退出：作者设备完整实测通过。
- ⚠️ 在 Kindle 上自动导入原图（第 7 步）和一次性触屏准备（第 5 步）：本地测试全部通过，但还没在第二台设备上实测。遇到问题欢迎提 Issue。
- ❌ 没验证：带锁屏密码、长期耗电、长期残影。

## 仓库结构

```
kindle/     原样复制到 Kindle 根目录的全部文件
install.sh  安全复制脚本（不覆盖）
AI.md       给 AI 助手的执行说明
source/     触屏读取器源码（4560 字节 ARMv7 静态程序，只读 /dev/input/event8，不联网）
```

完整的探索过程、调试记录、本地测试套件见原始仓库 [judeyang/kindle-oasis-photo-frame](https://github.com/judeyang/kindle-oasis-photo-frame)。

灵感来自 [Niraj Rajgor 的 Kindle 相框文章](https://nirajrajgor.com/blog/kindle-photo-frame-with-ai)。越狱工具与 KOReader 归各自上游所有，本仓库不分发它们。
