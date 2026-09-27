# Locus 安装与首次使用

## 1. 下载与签名

从 [Releases](https://github.com/ghb997/Locus-CN/releases) 下载 `Locus-CN-1.1.1-unsigned.ipa`，App 名称为 **Locus**。

这是未签名的 arm64 真机包。使用支持重签的 AltStore、SideStore、Sideloadly，或配合自己的有效证书使用 Feather / 其他签名工具安装。也可以在 macOS 上用 Xcode 选择自己的开发团队构建安装。签名有效期与功能受 Apple 和所用工具的规则限制。

应用标识已恢复为原版的 `com.chrismack.locus`。重签时保留此 Bundle ID；能否覆盖原版安装并保留数据取决于签名证书与配置。
此前 1.1.0 使用独立标识，其数据不会自动迁移到本版；如需使用原有配对记录，可重新导入同一份有效 RPPairing。不要把配对文件提交到 GitHub。

## 2. 打开开发者模式并配对

适配目标为 iOS 17–27，具体状态见[兼容性记录](docs/COMPATIBILITY.md)。

### iOS 17–26

1. 按 [idevice_pair](https://github.com/jkcoxson/idevice_pair/releases) 的系统与工具说明，在电脑上生成 **RPPairing**。
2. 连接并解锁 iPhone，按提示信任电脑；进入“设置 → 隐私与安全性 → 开发者模式”，按系统提示重启确认。
3. 把 RPPairing 传到手机，在 Locus 的首次引导或设置页导入。
4. 也可以复制完整 plist 文本，使用“从剪贴板粘贴 RPPairing”。

需要的是远程配对记录，不是 SideStore / lockdown 的 `.mobiledevicepairing`。
扩展名相同不代表格式相同。文件应包含匹配的 `private_key`、`public_key` 和 `identifier`，可选 `alt_irk`。导入失败保留旧文件。

### iOS 27

保留上游本机配对路径，尚需真机验证：

1. Locus → 设置 → 在此 iPhone 上配对 → 开始配对。
2. 允许本地网络、定位和通知权限，保持 App 运行。
3. 前往系统“设置 → 隐私与安全性 → 开发者模式”，寻找与 Locus / 主机配对的入口。
4. 先输入手机解锁密码，再在第二个提示中填写 Locus 显示的六位代码。
5. 成功后 App 校验并保存配对记录。

若没有对应入口或隧道连接失败，不能据此认定系统已兼容。记录完整系统版本，尝试有效 RPPairing 导入路径，并参考上游 idevice / Locus 的兼容信息。

## 3. 连接 LocalDevVPN

安装 [LocalDevVPN](https://apps.apple.com/us/app/localdevvpn/id6755608044) 并开启隧道，默认地址 `10.7.0.1`。优先在 Wi-Fi 下首次连接。
“检测到隧道接口”仅说明本机存在相应网络接口，开发者服务握手以实际发送结果为准。

## 4. 地点与路线

- 地图选点或搜索地点，点击“传送”；使用摇杆控制移动方向。
- 路线页设置起点和终点后规划，也可以绘制路线或导入 GPX。
- 多段 GPX 需要选择其中一段，避免不连续轨迹自动连接。
- 播放支持暂停/继续；路线页可以设置速度倍率；到达终点保持位置，直到点击停止。
- GPX 通常采用 WGS-84。国内地图偏移尚需真机验证，本版不自动转换坐标。

## 5. 停止与恢复

点击“停止”，等待清除完成，再在系统地图观察新位置。停止会等待已经进入底层库的调用返回，界面仍可响应。
清除错误时重新连接 LocalDevVPN，再点击停止，或使用“设置 → 定位状态 → 恢复系统定位”。
不要仅凭 App 图钉或旧系统坐标认定真实定位已经恢复。

## LiveContainer

文件选择器失效时，可在 LiveContainer 中长按 Locus → 设置 → 启用 **Fix File Picker**；也可以通过系统分享导入，或复制完整 RPPairing 文本从剪贴板导入。
容器、签名方式和系统版本可能影响本地网络、后台与 URL 回跳，需要实际验证。
