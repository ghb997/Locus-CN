# idevice 构建来源

当前发行版从 [jkcoxson/idevice](https://github.com/jkcoxson/idevice) 的固定提交
`d32c8189c51c2789496b0768039419c3705498c3`（0.1.68）构建。

- 源码与工具链锁定：[source-lock.json](source-lock.json)。
- Rust：1.98.1，使用上游 Cargo.lock 和 `--locked`。
- 构建目标：aarch64-apple-ios，`IPHONEOS_DEPLOYMENT_TARGET=17.0`。
- 特性：ring,full；不启用可选 obfuscate。
- 生成 C 头文件与静态库来自同一次编译，不混用上游自定义 ABI。
- App 本机配对接入 `pairable_host_prepare` / `pairable_host_accept_fd`；Bonjour 仍由 iOS Network.framework 发布。

运行 `bash scripts/build_native.sh` 构建依赖。此脚本克隆固定提交，验证提交号、编译并生成
`build/native-build.json`，包含静态库、头文件哈希及各对象的最低 iOS 版本。
若任何原生对象要求高于 iOS 17.0，检查会失败。生成的静态库不再直接提交 Git。

上游 Locus 原始二进制来自 `83c8fb324983728e8f44759cfd834dc637ee38b5`，
SHA-256 为 `05e6f58f082ee9f866a60763debe9b016e003005d424ac227b8d459686a2b575`。
检查发现其中 167 个对象声明 iOS 18.0 下限，因此本版改为从源码重建，并未只修改安装包版本限制。

idevice 采用 MIT，许可证见 [LICENSE.txt](LICENSE.txt)。底层协议与真实定位结果仍需手机验证。
