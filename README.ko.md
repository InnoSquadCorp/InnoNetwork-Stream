# InnoNetwork-Stream

[English](README.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Deutsch](README.de.md) · [简体中文](README.zh-Hans.md) · [日本語](README.ja.md) · [Русский](README.ru.md)

[6.1.1](https://github.com/InnoSquadCorp/InnoNetwork-Stream/releases/tag/6.1.1)

<!-- section:1 -->
## 범위

HLS 파싱, 상한이 있는 VOD·오프라인 다운로드, 라이브·DVR, 네이티브 재생·FairPlay 연동, 디코딩 오디오를 제공합니다. 플레이어 UI, CDN, 트랜스코더, DRM 서비스는 아닙니다. 통합 InnoNetwork-Stream 제품 또는 InnoNetworkHLS, InnoNetworkHLSLive, InnoNetworkHLSAVFoundation, InnoNetworkHLSAudio 개별 제품을 선택하세요. Swift 모듈은 이 네 이름이며 InnoNetworkStream 모듈은 없습니다.

일곱 빠른 시작 문서는 같은 안정 릴리스의 설치, 예제, 수명 주기, 마이그레이션을 다룹니다. 상세 영문 가이드는 공통 심화 자료입니다. 번역에 원어민 검수가 이루어졌다는 뜻은 아닙니다.

<!-- section:2 -->
## 요구 사항

Swift 6.2 이상, Swift 6 언어 모드. Apple 플랫폼 전용: iOS 16+, macOS 14+, tvOS 16+, watchOS 9+, visionOS 1+. Core 의존성은 InnoNetwork 6.1.1로 정확히 고정됩니다.

디코딩 오디오 선언은 추가로 Swift 6.4/Xcode 27 및 지원되는 OS 27 API가 필요합니다. 심볼별 가용성을 확인하세요. Swift 6.2의 공개 표면과 같지 않습니다. 여섯 워크플로 매크로는 모두 오류를 던지는 validated 설정 팩터리를 사용하며 configuration()은 네트워크 작업을 시작하지 않습니다.

<!-- section:3 -->
## 설치

패키지 의존성을 추가한 뒤 사용하는 타깃에 제품을 연결하세요.

```swift
.package(url: "https://github.com/InnoSquadCorp/InnoNetwork-Stream.git", from: "6.1.1"),
```

```swift
.product(name: "InnoNetwork-Stream", package: "InnoNetwork-Stream"),
```

<!-- section:4 -->
## 빠른 시작

아래 예제는 소스와 대조한 예제이며 새 컴파일이나 기기 테스트 결과가 아닙니다. URL, 자격 증명, 전송 정책은 앱이 관리합니다.

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
## 소유권과 실패

작업 핸들을 유지하세요. 이벤트 관찰자나 receipt 대기를 취소해도 생산자는 멈추지 않습니다. cancel()을 명시적으로 호출하거나 예제처럼 태스크 취소를 전달하세요. receipt()가 최종 결과의 기준이며 events()는 최대 64개 구독에 각각 최신 16개 이벤트와 순번·누락 정보를 유지합니다. 완료된 출력은 늦은 취소로 삭제되지 않습니다. 호출자가 오류를 처리하고 타입이 있는 실패·인시던트 계약을 확인하세요. 로그에 URL, 자격 증명, 미디어 본문을 남기지 마세요.

비동기 오프라인 downloadPackage는 호출 태스크에서 실행되어 그 취소를 따릅니다. 명시적 start 핸들은 관찰과 취소가 분리됩니다. 네이티브 백그라운드 작업은 시스템 복원 계약을 따릅니다. FairPlay 자격 증명, 권한, 키 저장은 앱 책임이며 라이브러리 출시는 서비스·기기 인증이 아닙니다.

<!-- section:6 -->
## 마이그레이션

기존 Core HLS 제품에서 이전할 때 이 형제 패키지를 추가하되 개별 import는 유지합니다. 미출시 InnoStream 체크아웃에서는 URL, 패키지 식별자, 제품의 package: 인자를 변경하세요. 과거 공개 태그나 리디렉션을 가정하지 마세요. 마이그레이션 가이드는 기존 스트림 소유 다운로드와 현재 핸들 소유 작업, 파서가 생성하는 플레이리스트 문서를 구분합니다.

<!-- section:7 -->
## 문서와 검증

다음 검사는 이 저장소에서 실행합니다. 정적 검사는 Swift 빌드, 매크로 확장, DocC, 기기·서비스 검증을 대체하지 않습니다. 공개 의존성 그래프를 확인할 때 INNONETWORK_LOCAL_PATH를 해제하세요.

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
