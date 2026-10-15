# Prompt Pin

一个轻巧的 macOS 菜单栏资料工具，支持项目提示词、账号密码、密钥和备忘录。

账号关系与凭据格式分开设置，账号关系和用途均为可选下拉框，不强制填写主账号或子账号：

- 账号关系：未指定、不区分主子账号、主账号 / 根账号、子账号 / IAM 用户、服务账号 / 机器身份。
- 用途：云平台、对象存储 / 存储桶、网站 / 应用、大模型 / AI、数据库、服务器 / SSH、代码托管 / CI、企业平台、其他 / 自定义。
- 凭据格式：AK / SK、API Key、Token / Bearer Token、SSH 私钥、证书 / 私钥、连接字符串、其他凭据。通用类型用于保存凭据文本，不解析证书、不连接服务。
- 账号密码只要求名称和密码；AK/SK 只要求名称、AK 和 SK，用户名、所属主账号、资源、用途及地址均可留空。
- 例如存储桶：类型选 AK/SK，用途选对象存储，资源填写 Bucket 名，Endpoint 按需填。没有主子账号关系就选“不区分”或留空。
- 列表可按用途、账号关系和密钥类型筛选，也能搜索名称、资源和备注。
- 独立“备忘录”支持中文多行、新建、编辑、删除确认、搜索、复制和备份导入导出。

原生 SwiftUI + AppKit，绿色、圆角和轻弹反馈。无网络请求、无账户、无第三方依赖。

## 使用

双击 `Prompt Pin.app`，点击屏幕顶部菜单栏的图钉图标。应用不占用 Dock，关闭弹出窗口后仍在后台运行。

- 在任何应用中按 ⌥⌘P（或 ⌃⌘P）唤起快速搜索：同时搜索提示词、账号、密钥和备忘录，↑↓ 选择，回车直接复制后自动关闭。提示词复制全文，账号复制密码，AK/SK 复制 SK，其他密钥复制密钥内容，备忘录复制正文；也可以用鼠标点击结果。Esc 或点击窗口外部关闭。
- 左侧选择项目，或查看全部提示词、常用置顶；侧边栏「随身资料」分区可切换到账号密码、密钥和备忘录。
- 点击“新建提示词”（⌘N），填写标题、项目、正文，⌘S 保存。
- 点击提示词内容打开编辑器，点击“复制提示词”复制完整原文。
- ⌘F 搜索当前分类下的标题、正文和项目名。
- 点击图钉置顶；卡片右上角菜单可编辑、复制一份或删除。
- 账号和密钥卡片逐字段显示，密码、SK、API Key 默认打码，点眼睛临时查看，每行有独立复制按钮。
- “我的项目”旁的 + 新建项目；右键项目可重命名或删除。
- 左下角设置菜单提供导入、导出、数据文件夹、登录时自动启动和退出。
- 编辑中的提示词不会因点击窗口外部而丢失；取消修改会二次确认。

如果键盘的 Control 键被系统映射为 Command，请使用 ⌥⌘P，避免实际只发送 ⌘P。

首次启动提供三个可编辑的示例。除全局快速搜索 ⌥⌘P / ⌃⌘P 外，其他快捷键均在应用窗口获得焦点时生效。

## 数据保存

数据独立于源码和应用包，保存在：

```text
~/Library/Application Support/PromptPin/library.json
~/Library/Application Support/PromptPin/library.backup.json
```

点击保存后立即写入磁盘；重启电脑、退出应用、重新构建或替换应用包都不会清除数据。仅保存成功后更新界面，失败时保留编辑内容并显示错误。

使用原子写入防止半截 JSON，下一次写入前保存上一版有效数据。目录权限为 700，数据文件为 600。JSON 是本地明文文件，没有应用级加密。建议使用系统 FileVault，并定期导出备份到其他位置。

文件损坏时停止编辑和写入，可从恢复界面恢复上一版。恢复前将原文件另存为 `library.unreadable-<UUID>.json`。未知版本的数据也不会被自动覆盖。

导出生成可迁移的 JSON 文件，包含提示词、账号密钥和备忘录。导入按 UUID 合并：已有项目、提示词、账号、密钥和备忘录均保留，新记录加入，多次导入同一份文件不会重复。导入不会覆盖同一 ID 的现有编辑。上一版自动备份不是完整历史，不能替代长期备份。

### 旧资料兼容

版本 1 文件可以直接读取，旧主账号、子账号、密码、密钥、ID 和时间均保留。新增分类默认“未指定”，可以按需要设置。旧记录中误放在主／子账号栏的地址或资源，可以使用新增的规范字段表示；原字段继续保留，不会丢失。打开应用不会改写资料；第一次主动保存时才写为版本 2，同时保存上一版文件。旧应用会拒绝版本 2，避免旧版本忽略新增字段后覆盖资料。切换密钥格式不会清空其他格式的已有字段，切回即可查看。主账号的登录名也可单独保存，不必再填写一个虚假的子账号。

若磁盘资料被其他进程修改，保存会报错并保留当前编辑，避免用内存中的旧资料覆盖它。

读写兼容性测试（可选传入真实资料路径，只读检查，不输出资料内容）：

```bash
PROMPT_PIN_COMPAT=1 ./scripts/swift.sh run PromptPinCoreChecks "$HOME/Library/Application Support/PromptPin/library.json"
```

开发时可设置 `PROMPT_PIN_DATA_DIR` 指向独立测试目录，应用将完全使用该目录；普通启动不设置此变量，仍使用原资料目录。

## 构建

要求 macOS 13+、Swift 6 工具链（Xcode 或 Command Line Tools）。构建产物针对当前 Mac 架构。

```bash
./scripts/build-app.sh
open "dist/Prompt Pin.app"
```

建议将应用复制到 `~/Applications` 或 `/Applications` 后再开启“登录时自动启动”，避免移动路径影响登录项。该开关使用系统 `SMAppService`，系统可能要求在登录项设置中允许运行。

```bash
swift build
swift run PromptPinCoreChecks
```

如果本机 Command Line Tools 有旧版残留，出现 `PackageDescription` 符号错误或重复 `SwiftBridging` 模块，可使用项目内兼容模式：

```bash
PROMPT_PIN_COMPAT=1 ./scripts/build-app.sh
PROMPT_PIN_COMPAT=1 ./scripts/swift.sh run PromptPinCoreChecks
```

兼容配置只在 `.build/compat` 创建模块副本和文件系统映射，不修改系统工具链，不需要管理员权限。正常工具链无需开启。数据测试使用不依赖 XCTest 的可执行测试程序，因此仅安装 Command Line Tools 也能运行；断言失败时以非零状态退出。

应用经过本机 ad-hoc 签名，适合本机使用；跨机器正式分发需要 Developer ID 签名和 Apple 公证。

## 代码结构

```text
Sources/PromptPin/          菜单栏、全局快速搜索、SwiftUI 界面、剪贴板和登录项
Sources/PromptPinCore/      数据模型、校验、搜索索引、原子存储与备份恢复
Tests/PromptPinCoreTests/   持久化与损坏恢复测试
scripts/                   应用打包、图标生成、可选工具链兼容
```

设计上不采集使用数据，也不发送提示词到任何服务。项目仅依赖系统框架。

系统接口参考：[SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)、[NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem)。
