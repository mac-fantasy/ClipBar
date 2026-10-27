# ClipBar

原生 macOS 菜单栏剪贴板历史工具。使用 Swift 6、AppKit、SwiftUI 和系统 ImageIO，通过 [Sparkle](https://sparkle-project.org/) 从 GitHub Releases 自动更新。采用 [MIT 许可证](LICENSE) 开源。

从 [最新 Release](https://github.com/lljxww/ClipBar/releases/latest) 下载通用版压缩包，解压后将 `ClipBar.app` 拖入「应用程序」目录。

## 构建和运行

运行需要 **macOS 13 或更新版本**；构建需要 **Xcode 16.3 / Command Line Tools 16.3 或更新版本**（Swift 6 和 macOS 15.4+ SDK）。CI 使用 Xcode 16.4，构建产物的最低系统版本仍为 macOS 13。

```bash
./scripts/build.sh
open dist/ClipBar.app
```

构建产物是可双击运行的 `dist/ClipBar.app`，默认构建当前 Mac 的 CPU 架构，并做本机 ad-hoc 签名。也可以将应用拖入「应用程序」目录后运行。重新构建前，请先从弹出面板退出正在运行的旧版本。

```bash
# 同时包含 Apple Silicon 和 Intel 架构，需要完整 Xcode
./scripts/build.sh --universal

# 调试构建
./scripts/build.sh --debug

# 打开源码
open Package.swift
```

跨电脑分发时，应使用自己的 Developer ID 签名并公证；本机签名不等同于 Apple 公证。

## 使用

- 启动后只有菜单栏的剪贴板图标，没有主窗口，也不在 Dock 显示。
- 自动记录纯文本、PNG / TIFF 图片，以及 Finder 复制的单个或多个文件、文件夹。
- 点击菜单栏图标查看历史。打开时不默认聚焦按钮或输入框；仍可通过 Tab 键导航。最新记录在顶部，图片显示缩略图，文件显示名称和原始位置。
- 点击任意历史记录，内容会重新写入系统剪贴板，面板关闭并返回之前的应用。按 `⌘V` 即可粘贴。
- 点击齿轮，输入 **1–100** 的整数后保存；默认 **20** 条。超出容量时删除最早的记录。调小容量立即淘汰超出的记录。
- 齿轮设置中显示当前版本，可手动「检查更新…」，或开关自动检查、自动下载并安装更新。默认启用自动更新，每 **6 小时**检查一次；安装时机由 Sparkle 管理，可能在退出后安装并在需要时提示重启。更新清单和安装包均经过 Ed25519 签名验证。
- 连续复制相同内容只保留一条；例如 A → B → A 保留三条。点击历史重新复制不会新增记录或改变顺序。
- 暂停按钮停止采集，恢复时跳过暂停期间的当前剪贴板，只采集之后的新内容。暂停状态不会跨应用重启保留。
- 垃圾桶按钮清空全部历史及缓存图片，需要在面板内确认。系统当前剪贴板不会被清空或立即重新录入。
- 在弹出面板右下角退出应用。应用不自动添加开机启动；需要时可在 macOS 的「登录项」中手动加入。

首次运行时，较新版本的 macOS 可能提示是否允许读取剪贴板。需要允许访问才能自动记录；如果禁止，面板会提示。无需辅助功能权限，因为应用只重新复制，不替其他软件执行粘贴。

## 存储和边界

剪贴板数据仅在本机保存，不会上传。启用自动更新后，应用会访问 GitHub Releases 获取更新清单和安装包；不启用系统信息统计。

```text
~/Library/Application Support/ClipBar/
├── history.json    # 历史、条数设置、文本及原始文件 URL
└── Images/         # 图片剪贴板内容，按 SHA-256 命名的 PNG
```

数据目录权限为 `0700`，历史和图片文件为 `0600`。这不是加密存储。会跳过带有 `org.nspasteboard.ConcealedType` 或 `org.nspasteboard.TransientType` 标记的内容；普通文本形式的密码、token 等无法可靠识别，需要自行暂停采集或清空历史。

**文件记录只保留原始 URL，不读取或复制原文件内容，不跟踪重命名和移动。** 从历史重新复制文件时，会检查所有原路径是否存在；如果任意文件已被移动、删除或不可访问，会提示失败并保留当前剪贴板。对于仅提供文件承诺、尚未产生本地 URL 的内容，不记录为文件。

图片保存为 PNG，TIFF 转换为静态 PNG。单张图片最多 **32 MiB / 4000 万像素**，超出后提示并跳过。淘汰记录、缩小容量和清空历史时，会清理不再被引用的图片；清理失败会记入系统日志，并在下次保存时重试。条数限制不等于总字节限制，100 张大图仍可能占用较多磁盘。

文本按纯文本保存，保留原始空白和换行；不保留富文本格式。一次复制同时含有多种表示时，优先级是 **文件 URL → 图片 → 文本**。

每 **0.6 秒**检查一次系统剪贴板的变更计数，不重复读取未变化的内容。系统调度、休眠及两次检查之间发生多次复制时，不能保证捕获中间每一次复制。退出期间不会记录；启动后会读取当前剪贴板，已有的连续重复内容不会重复入库。

历史先原子写入，再清理淘汰图片；保存失败保留内存中的上一版历史。损坏或版本不兼容的历史不会自动覆盖，应用会停止记录并提示。恢复时先退出应用并备份整个数据目录，再修复或移走 `history.json` 后重启。新历史不再引用的图片将在加载时清理，因此需要保留图片时应一起备份。

## 发布和自动更新

仓库内置 `.github/workflows/release.yml`，推送 `v主版本.次版本.修订版本` 格式的稳定版 tag 即可发布；版本号直接从 tag 写入应用，无需先修改 plist。例如：

```bash
git add .
git commit -m "Prepare release"
git tag -a v1.2.3 -m "ClipBar 1.2.3"
git push origin main
git push origin v1.2.3
```

GitHub Actions 会先运行测试，再构建 Apple Silicon / Intel 通用应用，生成以下附件，最后创建 Release 并自动生成发行说明：

- `ClipBar-1.2.3-macOS-universal.zip`：可直接安装的应用。
- `appcast.xml`：带签名的 Sparkle 更新清单，指向该 tag 下的安装包。
- `SHA256SUMS`：附件校验值。

应用使用 `https://github.com/lljxww/ClipBar/releases/latest/download/appcast.xml` 作为更新源。当前发布仅支持 `v1.2.3` 这样的稳定版本；不接受预发布、版本元数据或前导零。发布工作流通过 GitHub 的语义版本策略维护 Latest，补发旧版本时也会保留较新版本的更新入口。自动更新从包含此功能的版本开始生效，旧的 1.0.0 需要手动安装一次。

维护者在 Settings → Secrets and variables → Actions 配置两项 secret：

- `SPARKLE_PUBLIC_ED_KEY`：Base64 编码的 32 字节 Ed25519 公钥。
- `SPARKLE_PRIVATE_ED_KEY`：对应私钥的 Base64 seed，必须妥善备份；不能提交进仓库或每次发布重新生成。

公钥公开保存在 `Resources/Info.plist` 中。本地构建默认使用本仓库的更新源；Release 工作流通过 `CLIPBAR_UPDATE_REPOSITORY` 和公钥环境变量写入当前 GitHub 仓库的更新配置。Fork 后发布自己的应用时，需要生成自己的签名密钥，更新 plist 中的仓库名和公钥，并配置自己的 Actions secrets。Sparkle 自带 `generate_keys` 工具可生成密钥及使用 `-x` 导出私钥，详见 [官方配置文档](https://sparkle-project.org/documentation/)。

CI 和默认发布使用 ad-hoc 应用签名，未做 Apple Developer ID 签名或公证。Sparkle 的更新签名用于验证更新来自同一发布者，不能替代 Apple 公证；跨电脑首次打开时，macOS 可能要求在「系统设置 → 隐私与安全性」允许打开。

## 验证

```bash
swift test
python3 -m unittest discover -s Tests/BuildTests
swift format lint --strict --recursive Sources Tests scripts/generate-icon.swift Package.swift
./scripts/build.sh
codesign --verify --deep --strict dist/ClipBar.app
```

自动测试覆盖 FIFO、容量边界、连续去重、JSON 持久化、重启恢复、PNG / TIFF、图片校验及清理、多文件 URL、原文件丢失、保存失败回滚、自写回抑制、敏感标记和暂停后的变更处理，以及更新源校验、版本写入、发布清单与安装包的一致性。测试使用独立临时目录和具名测试剪贴板，不改动系统通用剪贴板。

手动验收：

1. 启动应用，确认菜单栏出现一个图标，没有主窗口和 Dock 图标。
2. 分别复制中文多行文本、截图、Finder 中多个文件，打开历史检查文本、缩略图和文件路径。
3. 点击历史，在文本编辑器、预览和 Finder 等支持相应内容的应用中按 `⌘V`，检查恢复结果。
4. 将容量设为 3，依次复制四个不同内容，确认只剩最后三条；点击历史重新复制，条数和顺序应不变。
5. 尝试输入 0、101、非整数，确认提示无效；设置 100 应成功。
6. 暂停后复制内容，恢复记录时不应补录暂停内容；之后的新复制应出现。
7. 复制文件后移动或删除源文件，点击该历史应提示失败；确认当前剪贴板仍然保持之前的内容。
8. 退出并重启，确认容量和历史保留；清空后重启，确认旧历史和图片不再出现。
9. 重复打开弹窗及关闭后重开，确认按钮和输入框没有默认焦点；按 Tab 仍可导航控件。
10. 在设置中检查更新，验证最新版本提示；关闭并重启后，自动检查和安装开关应保留选择。

可以在「控制台」筛选子系统 `local.ClipBar`，或执行：

```bash
log stream --predicate 'subsystem == "local.ClipBar"' --level info
```

## 文件结构

```text
Sources/ClipBar/
├── ClipBar.swift               # 应用入口
├── AppDelegate.swift           # 菜单栏图标、弹出面板、应用生命周期
├── HistoryView.swift           # 历史、图片缩略图、设置和操作
├── ClipboardController.swift   # 定时采集、界面状态、异常提示
├── UpdateController.swift      # Sparkle 生命周期、更新设置和手动检查
├── PasteboardAccess.swift      # AppKit 剪贴板读取及恢复
├── History.swift               # 记录模型、FIFO 和条数规则
└── HistoryRepository.swift     # 后台 actor、原子持久化、图片管理
Resources/Info.plist            # LSUIElement 和应用元数据
scripts/build.sh               # 编译、打包和本机签名
scripts/configure-bundle.py    # 版本和更新源注入
scripts/release.sh             # 通用更新包和签名 appcast
scripts/validate-appcast.py    # 发布清单与安装包一致性校验
scripts/generate-icon.swift     # 原生绘制应用图标
Tests/ClipBarTests/             # 规则、存储和独立剪贴板集成测试
Tests/BuildTests/               # 版本配置和发布清单校验测试
.github/workflows/             # CI 和 tag 发布
```
