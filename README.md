# Kindle Oasis 3 → 电子相框（WiFi 控制）

把 Kindle Oasis 3 变成全屏轮播照片的相框：按电源键正常锁屏休眠，唤醒后接着播同一张；原生阅读和 KOReader 照常可用。

**装好以后不用再插线**：在 Mac 上通过 WiFi 传照片、改间隔、看日志、截屏，也可以让 AI 直接连上 Kindle 帮你调试。思路来自 [Niraj Rajgor 的文章](https://nirajrajgor.com/blog/kindle-photo-frame-with-ai)。

照着下面的步骤做完，你的设备就和作者的一样。也可以把这个仓库直接交给 AI，让它按 [AI.md](AI.md) 带你做。

---

## 0. 先确认能不能用（不满足就停）

| 条件 | 怎么看 |
|---|---|
| 机型：**Kindle Oasis 3（2019，第 10 代）** | 设置 → 设备选项 → 设备信息 |
| 固件：**5.18.2.1.1** | 同上。不是这个版本就不要继续 |
| **没有设置锁屏密码** | 有密码时相册会拒绝启动 |
| 屏幕方向为默认竖屏 | 不要旋转 |
| Mac（或 Linux）+ 能传数据的 USB 线 | 插上后能看到 `Kindle` 盘。USB 只在安装时用一次 |
| Kindle 和 Mac 连同一个 WiFi | 用于之后的无线控制 |

> 其他型号、其他固件都**没验证过**，外观相近也不能套用。

## 1. 备份

插上电脑，把 `documents/` 里你在乎的书和笔记拷一份到电脑。

## 2. 越狱

按 KindleModding 官方流程用 **SpiderCat** 越狱：

1. 打开 [kindlemodding.org/jailbreaking](https://kindlemodding.org/jailbreaking/)，确认你的机型/固件可用。
2. 按 [SpiderCat 指南](https://kindlemodding.org/jailbreaking/SpiderCat/) 操作（把入口书放进 `documents/`，在 Kindle 上打开，等它跑完重启）。
3. 成功标志：文库出现 `JAILBROKEN`，并且放进 `documents/` 的 `.sh` 文件会显示成可以点开运行的入口（Scriptlets）。

完成后 `SpiderCat`、`JAILBROKEN` 两个文库条目可以移走。**不要重复越狱。**

## 3. 安装 KOReader

相册导入照片要借用 KOReader 的图片库，无线控制要借用它自带的 SSH 服务程序，所以必须装。

1. 下载 [KOReader v2026.07.1](https://github.com/koreader/koreader/releases/tag/v2026.07.1) 里的 `koreader-kindlehf-v2026.07.1.zip`
   SHA-256：`3343a916d12f36c01b59df1f65bd83ff5616e6c2a4dfbe919e7fa1400b8b1bbb`
2. 解压，把里面的 `koreader/` 和 `extensions/` 复制到 Kindle 根目录（按 [官方说明](https://github.com/koreader/koreader/wiki/Installation-on-Kindle-devices)）。
3. 弹出、拔线，在 Kindle 上打开 KOReader，随便开一本书确认能翻页。

## 4. 复制相册文件（最后一次用 USB）

Kindle 插回电脑，在本仓库目录执行：

```sh
./install.sh /Volumes/Kindle
```

它会：检查固件和 KOReader → 把 `kindle/` 里的文件放进 Kindle → 在 Mac 上生成无线控制专用密钥 `~/.ssh/kindle_album_ed25519`，把公钥放进 Kindle。只新增文件；遇到同名但内容不同的文件会停下，不覆盖任何东西。

> 用 Windows 或想手动复制：`kindle/` 目录的结构就是 Kindle 数据盘的结构。但 macOS 访达里**不要把 `kindle/documents` 文件夹整个拖到 Kindle 上**，那会替换整个 `documents`，书会没了。手动复制时无线控制需要自己把公钥写进 `kindle-album/wireless/authorized_keys`。

## 5. 在 Kindle 上做一次触屏准备

1. 安全弹出、拔线。
2. Kindle 文库里点 **Album Input Setup**（几秒内结束，屏幕不会有明显变化）。
3. 这个入口以后不用了，下一步连上 WiFi 后可以远程删掉（见第 7 步）。

## 6. 开启无线控制

1. Kindle 连上 WiFi（不要开飞行模式）。
2. 文库里点 **Album WiFi On**。屏幕上方会出现一行 `WiFi control ON  192.168.x.x:2222`，记下这个 IP。
3. 在 Mac 上（仓库目录）：

```sh
mac/kindlectl connect 192.168.x.x
```

显示 `✓ 已连接` 就成功了。以后每次打开相册都会自动开启无线控制；想关掉就点 **Album WiFi Off**。

> 想在任何目录都能用：`ln -s "$PWD/mac/kindlectl" /usr/local/bin/kindlectl`（下文都写成 `kindlectl`）。
> 建议在路由器里给 Kindle 固定 IP，否则 IP 变了要重新 `connect`。

## 7. 第一次打开 + 验收

```sh
kindlectl sh 'rm /mnt/us/documents/Kindle_Album_Input_Setup.sh'   # 移走一次性入口
kindlectl sh 'head -1 /mnt/us/kindle-album/input-ready.txt'       # 应显示 input_helper_ready=yes
kindlectl start                                                   # 启动相册（也可以在文库点 Album Fullscreen）
kindlectl shot                                                    # 截屏看看
```

然后在 Kindle 上确认：

- [ ] 全屏测试图；轻触一下出现底部按钮，5 秒不动自动隐藏
- [ ] 按电源键 → 正常锁屏 → 等一会儿真正休眠
- [ ] 再按电源键唤醒、解锁 → 回到**同一张**照片，过一个间隔后自动换下一张
- [ ] 相册开着时插 USB → 自动退出，电脑能看到 Kindle 盘

全部通过，就和作者的设备一样了。

## 8. 放自己的照片

```sh
kindlectl add ~/Pictures/挑好的/*.jpg
```

照片通过 WiFi 传到 Kindle 的 `Photos/`，相册自动重启并导入，完成后告诉你新增了几张。

- 方向、灰度、缩放都在 Kindle 上处理，原图不动；重复照片只导入一次。
- 第一次导入自己的照片后，测试图自动从播放列表中移除。
- 支持 JPG / JPEG / PNG；单张 ≤ 64 MB，最多 500 张；HEIC 不支持（改扩展名也不行，先在 Mac 上导出为 JPG）。
- 不想用 WiFi 也可以：USB 把原图放进 `Photos/`，在 Kindle 上打开相册即可。

---

## 日常使用

**在 Mac 上**

| 想做什么 | 命令 |
|---|---|
| 全面体检（贴给 AI 排错用） | `kindlectl check` |
| 看状态（是否在播、间隔、张数、电量） | `kindlectl status` |
| 加照片 | `kindlectl add 照片...` |
| 改换图间隔 | `kindlectl interval 300`（只有 10 / 30 / 60 / 300 秒四档） |
| 裁切填满 / 完整显示 | `kindlectl mode crop` / `kindlectl mode contain` |
| 启动 / 停止 / 重启相册 | `kindlectl start` / `stop` / `restart` |
| 截屏 | `kindlectl shot` |
| 看日志 | `kindlectl logs`，持续跟踪 `kindlectl logs -f` |
| 传文件 / 取文件 | `kindlectl push 本地 远端` / `kindlectl pull 远端 本地` |
| 在 Kindle 上执行命令 | `kindlectl sh '命令'` |

**在 Kindle 上**：轻触照片显示按钮（上一张 / 下一张 / 间隔 / 裁切或完整 / 退出阅读）。备用停止入口是 **Album Fullscreen Stop**。看书用 KOReader 或原生阅读器，互不影响。

**连不上时**：Kindle 一旦锁屏/休眠（按电源键，或系统空闲自动休眠），WiFi 就会断开，这是系统行为，相册不会去改电源设置。按电源键唤醒、解锁回到相册后再试。深睡时也不会定时唤醒换图（省电）。

## 已经装过旧版（不带 WiFi）的设备

插上 USB，执行一次：

```sh
./install.sh --update /Volumes/Kindle
```

只更新程序文件（旧的先备份到 `kindle-album/backup/`），照片、播放列表和设置不动。拔线后，如果文库里出现 **Album Input Setup**，先点一下（已经装好触屏读取器的设备会直接通过），然后从第 6 步继续。这是最后一次插线。

## 出问题怎么办

| 现象 | 处理 |
|---|---|
| `kindlectl` 报「连不上」 | Kindle 是否亮屏并在相册或文库界面；WiFi 是否连着；IP 变了就重新点 Album WiFi On 看 IP，再 `connect` |
| 点 Album WiFi On 显示 FAILED | `no public key`：重新跑一次 `./install.sh`；`KOReader dropbear missing`：先装 KOReader |
| 相册起不来 | `kindlectl logs` 看 launch.log；最常见：设了锁屏密码、没做第 5 步 |
| 导入后没出现新照片 | `kindlectl logs` 看导入结果；检查格式（不是 HEIC） |
| 触屏完全没反应 | `kindlectl stop`；或按电源键；或插 USB（相册会自动退出） |
| 彻底卡死 | 按住电源键约 40 秒强制重启（确保没有正在传的文件） |
| 想卸载 | `kindlectl wifi-off`，再删除 `documents/Kindle_Album_*.sh` 和 `kindle-album/` |

不要为修相册去重新越狱、升级固件或恢复出厂。

## 安全说明

- 无线控制是 SSH（KOReader 自带的 dropbear），端口 2222，**只允许公钥登录，没有密码可猜**。私钥只在你的 Mac 上（`~/.ssh/kindle_album_ed25519`）。
- 登录后是 Kindle 的 root 权限，等同于完全控制这台 Kindle。不要把私钥给别人；不在公共 WiFi 上开启。
- 不用了就点 **Album WiFi Off**，它会关掉服务、关上防火墙端口，并取消自动开启。

## 当前验证状态（如实说明）

- ✅ 锁屏 / 休眠 / 唤醒续播 / 自动换图 / USB 退出：作者设备完整实测通过。
- ⚠️ 在 Kindle 上自动导入原图、一次性触屏准备：本地测试全部通过，还没在第二台设备实测。
- ⚠️ **WiFi 无线控制（第 6 步起）是新加的**：已用 qemu 运行 KOReader v2026.07.1 包里**原样的 ARM 版 dropbear**，按 Kindle 上的同样路径和参数完成整套测试——公钥登录成功，其他密钥和密码登录均被拒绝，3 MB 文件往返校验一致，开启/关闭/重复开启/随相册自动开启都正常。还没在真机 Kindle 上跑过（防火墙、WiFi 地址获取这两处只能在真机验证）。第一次用如果遇到问题，`Album WiFi On` 的失败原因会显示在屏幕上，并写入 `kindle-album/wireless/status.txt`。
- ❌ 没验证：带锁屏密码、长期耗电、长期残影。

## 仓库结构

```
kindle/           原样复制到 Kindle 根目录的全部文件
  documents/        文库入口：Album Fullscreen / Stop / WiFi On / WiFi Off / Input Setup
  kindle-album/     相册程序、测试素材、触屏读取器、无线控制脚本
install.sh        安装 / 更新（不覆盖照片和数据），并放入无线控制公钥
mac/kindlectl     Mac 端无线控制工具（只依赖系统自带的 python3 和 ssh）
AI.md             给 AI 助手的执行说明
source/           触屏读取器源码（4560 字节 ARMv7 静态程序，只读 /dev/input/event8，不联网）
```

完整的探索过程、调试记录、本地测试套件见原始仓库 [judeyang/kindle-oasis-photo-frame](https://github.com/judeyang/kindle-oasis-photo-frame)。越狱工具与 KOReader 归各自上游所有，本仓库不分发它们。
