Locus 1.1.1 简体中文增强版，由 ghb997 维护，基于 ChrisMack32/Locus（MIT）。

- Bundle ID 恢复为原版的 `com.chrismack.locus`，构建号升至 5。
- 配对文件类型和 URL 注册标识同步恢复到原版命名空间。
- 保留 1.1.0 的中文界面、定位会话修复、路线和 GPX 改进；App 名称仍为 Locus。
- 更新打包校验与安装说明，确保 IPA 内实际使用原版 Bundle ID。

**下载说明：** `Locus-CN-1.1.1-unsigned.ipa` 是未签名的 arm64 真机包，需要重签后安装。
重签时保留 `com.chrismack.locus`；能否覆盖原版安装并保留数据取决于签名证书与配置。
1.1.0 独立标识版本的数据不会自动迁移到本版，如需使用原有配对记录，可重新导入有效 RPPairing。

**验证范围：** iOS 部署下限为 17.0，17–27 为适配目标；尚未逐版本真机验证。
新系统配对与隧道、后台运行和国内地图偏移仍需验证。
安装步骤见 [SETUP.md](https://github.com/ghb997/Locus-CN/blob/main/SETUP.md)，
系统状态见[兼容性记录](https://github.com/ghb997/Locus-CN/blob/main/docs/COMPATIBILITY.md)。
