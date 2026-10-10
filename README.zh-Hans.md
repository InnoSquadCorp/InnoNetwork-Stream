# InnoNetwork-Stream

[English](README.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Deutsch](README.de.md) · [简体中文](README.zh-Hans.md) · [日本語](README.ja.md) · [Русский](README.ru.md)

[6.1.1](https://github.com/InnoSquadCorp/InnoNetwork-Stream/releases/tag/6.1.1)

<!-- section:1 -->
## 范围

提供 HLS 解析、有界 VOD/离线下载、直播/DVR、原生播放/FairPlay 集成和解码音频。不是播放器界面、CDN、转码器或 DRM 服务。可选择聚合产品 InnoNetwork-Stream 或 InnoNetworkHLS、InnoNetworkHLSLive、InnoNetworkHLSAVFoundation、InnoNetworkHLSAudio 单独产品。后四个名称是 Swift 模块；不存在 InnoNetworkStream 模块。

七种语言的快速入门覆盖同一稳定版本、安装、示例、生命周期和迁移。详细英文指南是共享的高级参考；翻译不代表经过母语审校。

<!-- section:2 -->
## 环境要求

Swift 6.2 及以上，Swift 6 语言模式。仅支持 Apple 平台：iOS 16+、macOS 14+、tvOS 16+、watchOS 9+、visionOS 1+。Core 精确固定为 InnoNetwork 6.1.1。

解码音频声明还需要 Swift 6.4/Xcode 27 和受支持的 OS 27 API，请检查每个符号的可用性。Swift 6.2 的接口并不相同。六种工作流宏均使用会抛出错误的 validated 配置工厂；configuration() 不发起网络操作。

<!-- section:3 -->
## 安装

添加以下包依赖，并将产品添加到使用它们的 target。

```swift
.package(url: "https://github.com/InnoSquadCorp/InnoNetwork-Stream.git", from: "6.1.1"),
```

```swift
.product(name: "InnoNetwork-Stream", package: "InnoNetwork-Stream"),
```

<!-- section:4 -->
## 快速开始

以下示例已与源代码核对，但不代表重新完成编译或设备测试。URL、凭据和传输策略由应用管理。

```swift
import Foundation
import InnoNetworkHLS

@HLSDownloadDefinition(
    maximumMediaResourceBytes: 8_388_608,
    maximumTotalDownloadBytes: 268_435_456,
    maximumConcurrentResourceTransfers: 3
)
enum MovieDownload {}

func saveMovie(source: URL, destination: URL) async throws -> HLSDownloadReceipt {
    let operation = try MovieDownload.start(
        sourceURL: source,
        destinationURL: destination
    )
    return try await withTaskCancellationHandler {
        try await operation.receipt()
    } onCancel: {
        operation.cancel()
    }
}
```

<!-- section:5 -->
## 生命周期与错误

保留操作句柄。取消事件观察者或 receipt 等待者不会停止生产者；请显式调用 cancel()，或像示例一样传递任务取消。receipt() 是最终结果依据；events() 最多允许 64 个订阅，每个保留最新 16 个事件及序号/丢弃信息。晚到的取消不会删除已完成输出。调用者应捕获错误并使用类型化失败契约，避免将 URL、凭据或媒体内容写入日志。

异步离线 downloadPackage 在调用任务内运行并继承其取消；显式 start 句柄将观察和取消分离。原生后台任务遵循系统恢复语义。FairPlay 凭据、授权和密钥存储由应用负责；发布库不代表通过服务或设备认证。

<!-- section:6 -->
## 迁移

从旧 Core HLS 产品迁移时，添加本包并保留单独 import。从未发布的 InnoStream 检出迁移时，更新 URL、包标识和产品 package: 参数。不要假设旧公开标签或重定向存在。迁移指南区分由流控制的旧下载、当前持有的句柄以及解析器生成的播放列表文档。

<!-- section:7 -->
## 文档与验证

在本仓库中运行这些检查。静态检查不能替代 Swift 构建、宏展开、DocC 或设备及服务验收。验证已发布的依赖图时，请移除环境变量 INNONETWORK_LOCAL_PATH。

- [Technical guide (English)](docs/GUIDE.md)
- [Documentation map / historical evidence](docs/README.md)
- [Migration (English)](docs/MACRO_FIRST_MIGRATION.md)
- [API stability](API_STABILITY.md)
- [AI development skill](skills/README.md)
- [Release qualification record](docs/releases/6.1.1.md)
- [Roadmap](docs/ROADMAP.md)
- [MIT License](LICENSE)

```bash
bash Scripts/validate_docs_release_state.sh
python3 Scripts/check_readme_parity.py
env -u INNONETWORK_LOCAL_PATH bash Scripts/swiftpm.sh test --force-resolved-versions --parallel
```
