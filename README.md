# Locus · 简体中文增强版

[![Build and test IPA](https://github.com/ghb997/Locus-CN/actions/workflows/build.yml/badge.svg)](https://github.com/ghb997/Locus-CN/actions/workflows/build.yml)

**ghb997 维护的 iPhone / iPad 定位模拟工具。** 保留 Locus 名称，在上游基础上补齐中文界面并修复会话和文件处理问题。
基于 [ChrisMack32/Locus](https://github.com/ChrisMack32/Locus)，按 MIT 许可证发布，保留原作者署名与提交历史。

[下载 IPA](https://github.com/ghb997/Locus-CN/releases) · [安装说明](SETUP.md) · [兼容性记录](docs/COMPATIBILITY.md) · [来源说明](NOTICE.md)

## 本版改进

- 简体中文界面、首次设置、权限提示、通知、错误和无障碍标签，保留英文资源。
- 定位命令在后台串行执行，连接期间界面可以响应；停止及模式切换使旧任务失效。
- 固定位置、路线、摇杆互斥；路线支持暂停/继续、进度、0.25–4 倍速度，到达后保持终点。
- XML 解析 GPX，支持不同属性顺序和单引号；多段轨迹由用户选择，避免自动跨段连接。
- GPX 文件大小、点数与坐标校验；导出使用标准小数点并转义 XML 特殊字符。
- RPPairing 密钥结构与匹配校验；原子替换保护原有文件。
- 隧道 IP 校验、最近发送时间、错误代码和手动恢复系统定位。
- GitHub Actions 自动测试、源码构建 IPA、产物结构检查与 SHA-256 校验。

## 系统与安装

**适配目标：iOS 17–27，部署下限 17.0。** 这是源码的目标范围；各版本的隧道、后台和定位效果仍需真机验证，详见[兼容性记录](docs/COMPATIBILITY.md)。

- iOS 17–26：在电脑上生成 RPPairing 并导入。
- iOS 27：保留上游本机配对入口，也可导入有效 RPPairing；协议可用性待验证。
- 需要开发者模式、LocalDevVPN 与有效签名，该方案不以越狱为前提。
- 发布的 **unsigned IPA 需要重签后侧载**，不含开发者证书或描述文件。
- App 名称：Locus；应用标识：`io.github.ghb997.locus`；回跳链接：`locus-cn://`。
- 与原版使用独立数据容器，收藏和配对文件需要重新导入。

## 工作原理与边界

Locus 使用 idevice FFI 通过开发者隧道向 Apple 定位模拟服务发送经纬度。
“定位指令已发送”代表服务接受了指令，不能证明其他 App 已认可位置。
停止后应等待系统刷新定位；清除失败时重连 LocalDevVPN，再点击停止或恢复。

底层原生调用不能被 Swift Task 强制终止。停止会使排队的旧指令立即失效，等待执行中的原生调用返回后发送清除。底层长时间不返回时，停止也需要等待。

骑行是速度预设，使用驾车路线；步行与跑步使用步行路线。
国内 GCJ-02 / WGS-84 边界尚待真机确认，本版未自动添加坐标转换。
系统可能限制后台存活，开发者模拟定位也可能被其他 App 识别。

收藏、最近记录和配对文件保存在本机。地图搜索和路线规划访问 Apple 地图在线服务；本项目没有分析统计或账号系统。

## 构建

Windows 可使用 **Actions → Build and test IPA → Run workflow**，完成后下载产物并解压获取 IPA。

本地编译需要 macOS、Xcode 26 或更新版，以及 XcodeGen：

```sh
brew install xcodegen
python3 scripts/validate_project.py
swift test
xcodegen generate
open Locus.xcodeproj
```

需要签名安装时，在 Xcode 的 Signing & Capabilities 中选择自己的开发团队。
`project.yml` 是工程配置来源；修改后重新执行 XcodeGen。
核心回归测试引用 `Locus/Core` 中的生产代码；构建校验原生依赖哈希。
完整打包与发行流程见 [.github/workflows/build.yml](.github/workflows/build.yml)。

## 许可证

[MIT](LICENSE)。原版由 ChrisMack32 / Locus contributors 提供，本仓库由 ghb997 维护。
idevice 许可证与依赖来源见 [Vendor/idevice/PROVENANCE.md](Vendor/idevice/PROVENANCE.md)。
