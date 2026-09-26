Locus 1.1.0 简体中文增强版，由 ghb997 维护，基于 ChrisMack32/Locus（MIT）。

- 保留 Locus 名称，使用独立应用标识 `io.github.ghb997.locus`。
- 中文界面、首次设置、权限提示、通知、错误信息与无障碍标签，保留英文资源。
- 后台串行发送定位命令；停止、换路线、切换摇杆时使旧命令失效。
- 路线暂停/继续、进度显示、0.25–4 倍速度、终点保持。
- XML GPX 解析、多轨迹段选择、文件大小/点数/坐标范围校验，修复导出 XML 转义。
- RPPairing 密钥结构校验与原子替换；隧道 IP 校验、最近发送时间、清除失败重试。
- iOS 部署下限降至 17.0，适配目标为 17–27；保留上游 iOS 27 本机配对路径。
- 从固定版本 idevice 0.1.68 源码构建 iOS 17 原生依赖，本机配对使用正式 FD API，关闭配对页会取消套接字。
- GitHub Actions 构建、共享生产代码回归测试、IPA 结构校验与 SHA-256 校验文件。

**下载说明：** `Locus-CN-1.1.0-unsigned.ipa` 是从本仓库源码编译的未签名包，
需要用自有签名或支持重签的侧载工具安装；它不是可直接双击安装的 App Store 包。

**验证范围：** 自动构建与测试状态见 Actions；尚未对 iOS 17–27 逐版本真机测试。
底层 idevice 固定版本重建，新系统隧道兼容、后台稳定性和国内地图偏移仍需验证。
安装前阅读 [SETUP.md](https://github.com/ghb997/Locus-CN/blob/main/SETUP.md) 和
[兼容性记录](https://github.com/ghb997/Locus-CN/blob/main/docs/COMPATIBILITY.md)。
