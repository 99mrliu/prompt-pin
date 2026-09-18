# Prompt Pin

一个轻巧的 macOS 菜单栏提示词收纳工具。按项目整理常用提示词，随时搜索、编辑和一键复制。

原生 SwiftUI + AppKit，绿色、圆角和轻弹反馈。无网络请求、无账户、无第三方依赖。

## 使用

双击 `Prompt Pin.app`，点击屏幕顶部菜单栏的图钉图标。应用不占用 Dock，关闭弹出窗口后仍在后台运行。

- 左侧选择项目，或查看全部提示词、常用置顶。
- 点击“新建提示词”（⌘N），填写标题、项目、正文，⌘S 保存。
- 点击提示词内容打开编辑器，点击“复制提示词”复制完整原文。
- ⌘F 搜索当前分类下的标题、正文和项目名。
- 点击图钉置顶；卡片右上角菜单可编辑、复制一份或删除。
- “我的项目”旁的 + 新建项目；右键项目可重命名或删除。
- 左下角设置菜单提供导入、导出、数据文件夹、登录时自动启动和退出。
- 编辑中的提示词不会因点击窗口外部而丢失；取消修改会二次确认。

首次启动提供三个可编辑的示例。所有快捷键均在应用窗口获得焦点时生效。

## 数据保存

数据独立于源码和应用包，保存在：

```text
~/Library/Application Support/PromptPin/library.json
~/Library/Application Support/PromptPin/library.backup.json
```

点击保存后立即写入磁盘；重启电脑、退出应用、重新构建或替换应用包都不会清除数据。仅保存成功后更新界面，失败时保留编辑内容并显示错误。

使用原子写入防止半截 JSON，下一次写入前保存上一版有效数据。目录权限为 700，数据文件为 600。JSON 是本地明文文件，没有应用级加密。建议使用系统 FileVault，并定期导出备份到其他位置。

文件损坏时停止编辑和写入，可从恢复界面恢复上一版。恢复前将原文件另存为 `library.unreadable-<UUID>.json`。未知版本的数据也不会被自动覆盖。

导出生成可迁移的 JSON 文件。导入按 UUID 合并：已有项目和提示词保留，新记录加入，多次导入同一份文件不会重复。导入不会覆盖同一 ID 的现有编辑。上一版自动备份不是完整历史，不能替代长期备份。

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
Sources/PromptPin/          菜单栏、SwiftUI 界面、剪贴板和登录项
Sources/PromptPinCore/      数据模型、校验、原子存储与备份恢复
Tests/PromptPinCoreTests/   持久化与损坏恢复测试
scripts/                   应用打包、图标生成、可选工具链兼容
```

设计上不采集使用数据，也不发送提示词到任何服务。项目仅依赖系统框架。

系统接口参考：[SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)、[NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem)。
