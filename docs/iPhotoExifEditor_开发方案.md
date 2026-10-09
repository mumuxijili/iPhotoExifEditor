# iPhotoExifEditor：iOS 照片元数据编辑工具开发方案（第一阶段）

> 目标环境：Windows + VS Code 开发；GitHub Actions 的 macOS Runner 编译；SideStore 侧载到 iOS 26。
> 核心 API：Apple PhotoKit 的公开接口 `PHAssetChangeRequest.location` 和 `PHAssetChangeRequest.creationDate`。
> 文档版本：2026-10-09（第一阶段范围调整）。

## 1. 目标与边界

实现一个自用 iOS App，名称为 **iPhotoExifEditor**。第一阶段只修改 PhotoKit 公开支持的照片资产属性，不实现任意 EXIF 字段写入：

1. 读取系统「照片」图库中的照片及其 `PHAsset.location`。
2. 选择**源照片 A**和**目标照片 B**。
3. 将 A 的 `CLLocation` 复制给 B；手工设置/清除 GPS 作为第一阶段后续迭代（地图选点再往后）。
4. 读取、手工设置照片的 `PHAsset.creationDate`；支持把 A 的拍摄日期复制给 B（最小示例已包含）。
5. 修改后仍然是同一个 `PHAsset`，**不在图库中增加第二张照片**，不重新编码图片。
6. 通过 Windows 编写源码、GitHub Actions 生成**未签名 IPA**，再由 SideStore 进行签名和安装。

**重要边界：** `PHAssetChangeRequest.location` / `.creationDate` 修改的是 Photos 管理的照片资产属性。Apple 没有承诺它会原地覆盖原始 JPEG/HEIC 文件中的 EXIF GPS 或 EXIF 拍摄时间字节。第一阶段**不使用 ImageIO 写出新文件，不提供 ISO、光圈、快门、设备型号、版权、任意 EXIF 键值等编辑功能**。若要求“原始文件的 EXIF 本身永久变化”，那属于以后单独设计的 ImageIO 文件编辑路线。AirDrop/导出时最终携带何种 GPS，需对实际导出文件做验证，不应直接假定与原始资源相同。

### 1.1 全阶段照片安全约束

以下约束适用于第一阶段及所有后续功能，新增功能和代码评审必须逐项确认：

1. **绝不删除照片**：不调用 `PHAssetChangeRequest.deleteAssets`，不提供删除图库照片或原始文件的操作；失败、取消或清理临时文件时也不能删除用户已有照片。
2. **绝不覆盖已有图片文件**：第一阶段不生成新图片，只修改用户明确选定的现有 `PHAsset` 的位置或日期属性。修改资产属性不等于替换其图片文件。
3. **未来若生成新图片，必须另存**：生成结果使用新的文件路径和唯一文件名，并采用拒绝覆盖已有文件的写入方式；遇到同名文件时重新命名或停止并提示。不得写回原始资源路径，也不得静默替换图库中已有资产。
4. **写入前确认目标**：界面展示源照片、目标照片及将修改的字段，由用户确认后再提交；批量功能还须展示目标数量。目标不明确或无法保证上述约束时停止操作并说明原因。
5. **持续验证**：每次增加导入、导出、批量或文件编辑能力，都要验证原有照片没有被删除，原有图片文件和同名输出文件没有被覆盖。

## 2. API 与工作机制

### 2.1 使用的公开 API

- `PHPhotoLibrary.requestAuthorization(for: .readWrite)`：申请读取、修改图库权限。
- `PHAsset.fetchAssets(with:options:)`：获取用户授权可访问的照片资产。
- `PHAsset.location`：读取照片资产的位置，类型为 `CLLocation?`。
- `PHAsset.creationDate`：读取照片资产的拍摄/创建时间，类型为 `Date?`。
- `PHPhotoLibrary.shared().performChanges`：提交照片库修改事务。
- `PHAssetChangeRequest(for: asset).location = ...`：修改现有资产的位置。
- `PHAssetChangeRequest(for: asset).creationDate = ...`：修改现有资产的创建时间。

核心调用：

```swift
import Photos
import CoreLocation

func copyLocation(from source: PHAsset, to target: PHAsset,
                  completion: @escaping (Bool, Error?) -> Void) {
    guard let sourceLocation = source.location else {
        completion(false, NSError(domain: "iPhotoExifEditor", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "源照片没有位置数据"]))
        return
    }
    guard source.localIdentifier != target.localIdentifier else {
        completion(false, NSError(domain: "iPhotoExifEditor", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "源照片与目标照片不能相同"]))
        return
    }
    PHPhotoLibrary.shared().performChanges {
        PHAssetChangeRequest(for: target).location = sourceLocation
    } completionHandler: { success, error in
        completion(success, error)
    }
}
```

注意：必须取得 `.authorized` 或 `.limited` 的照片库读写权限；在 `.limited` 状态下只能操作用户授权的资产。`source.location` 可能是 `nil`。修改操作可能因权限、iCloud 状态或资产类型等原因失败，应展示实际错误。

### 2.2 第一阶段允许修改的字段

| 字段 | 读取 API | 写入 API | 是否实现 |
|---|---|---|---|
| GPS 经纬度及 `CLLocation` 包含的位置属性 | `PHAsset.location` | `PHAssetChangeRequest.location` | 是 |
| 拍摄/创建日期 | `PHAsset.creationDate` | `PHAssetChangeRequest.creationDate` | 是 |
| 收藏、隐藏 | `PHAsset.isFavorite` / `.isHidden` | 对应 ChangeRequest 属性 | API 支持，但第一阶段不做 |
| ISO、光圈、快门、焦距、相机/镜头型号 | 需要文件元数据读取 | PhotoKit 无通用字段写入 | 不做 |
| EXIF、IPTC、XMP 任意字段 | 需要文件元数据读取 | PhotoKit 无通用字段写入 | 不做 |

日期用 `Date` 表示绝对时间，UI 必须明确本地时区的显示/输入含义；不要把 `creationDate` 与 EXIF 的 `DateTimeOriginal` 字节改写混为一谈。

### 2.3 是否会覆盖原始 EXIF？

| 方式 | 相册里增加一张照片？ | 重新编码图像？ | 原始文件 EXIF 保证被改写？ |
|---|---|---|---|
| `PHAssetChangeRequest.location` | 否 | 否 | **否** |
| ImageIO 输出新 JPEG/HEIC | 不一定，取决于是否导入 | 可视具体写出方法避免不必要的重新压缩 | 新输出文件可携带修改后的 GPS |
| 直接改写 Photos 原始资源文件 | — | — | 没有供第三方直接修改原始文件字节的公开 PhotoKit API |

### 2.4 坐标系注意事项

本工具复制的是原有 `CLLocation`，**不做任何 WGS-84 / GCJ-02 转换**。不要仅根据中国大陆地图底图的显示偏移，推断需要转换照片中的坐标。未来加入 MapKit 地图选点时，应对照真实位置、原始 EXIF、`PHAsset.location` 和地图选点返回值进行实机验证。

## 3. 开发环境

### 3.1 Windows

必需：

- VS Code（建议安装 `swiftlang.swift-vscode` 扩展）。
- Git 与 GitHub 仓库。
- 能编辑 YAML / Swift 的文本编辑器。

**不要求在 Windows 安装 Swift SDK。** Windows 原生 Swift 工具链无法提供 iOS 的 SwiftUI、Photos、MapKit SDK，也不能在 Windows 本机完成标准 iOS IPA 编译。完整 Swift 语义诊断需要相应工具链；不安装时主要使用基础编辑功能，并以云端 Xcode 编译错误为准。

### 3.2 云端编译

- GitHub Actions macOS Runner。
- Xcode 和 iOS SDK（在 Runner 上）。
- XcodeGen：从 `project.yml` 生成 `.xcodeproj`。
- `xcodebuild`：编译 iPhone 真机版 `.app`。
- `zip`：打包为 `Payload/*.app` 结构的 `.ipa`。

### 3.3 iPhone

- iOS 26。
- 已配置的 SideStore。
- 授予 App 照片库**读写**权限。

SideStore 是否成功安装取决于其签名和侧载能力、账号限制、扩展/Entitlements 等；“未签名 IPA 能编译成功”不等于保证一定能安装。

## 4. 最小可运行项目

目录结构：

```text
iPhotoExifEditor/
├── project.yml
├── Sources/
│   ├── iPhotoExifEditorApp.swift
│   ├── PhotoLibraryModel.swift
│   └── ContentView.swift
└── .github/
    └── workflows/
        └── build.yml
```

### 4.1 `project.yml`

```yaml
name: iPhotoExifEditor
options:
  bundleIdPrefix: com.example

targets:
  iPhotoExifEditor:
    type: application
    platform: iOS
    deploymentTarget: "16.0"
    sources:
      - Sources
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.example.iphotoexifeditor
        SWIFT_VERSION: "5.0"
        TARGETED_DEVICE_FAMILY: "1,2"
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_NSPhotoLibraryUsageDescription: "需要读取并修改所选照片的位置和拍摄日期"
        MARKETING_VERSION: "1.0.0"
        CURRENT_PROJECT_VERSION: "1"
        CODE_SIGNING_ALLOWED: NO
```

`PRODUCT_BUNDLE_IDENTIFIER` 应改为你自己长期固定使用的唯一标识，例如 `com.yourname.iphotoexifeditor`。后续升级保持它不变。应用的显示名称、IPA 文件名不是识别同一 App 的依据；SideStore 重新签名后，最终安装身份也必须与旧版兼容。

### 4.2 `Sources/iPhotoExifEditorApp.swift`

```swift
import SwiftUI

@main
struct iPhotoExifEditorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### 4.3 `Sources/PhotoLibraryModel.swift`

这个最小版本只列出最近最多 300 张授权可访问的图片，并支持复制 GPS、复制日期、手动设置日期。正式产品可以换成缩略图网格、分页和相册筛选。

```swift
import Foundation
import Photos
import CoreLocation

struct PhotoEntry: Identifiable {
    let asset: PHAsset
    var id: String { asset.localIdentifier }

    var title: String {
        let date = asset.creationDate.map {
            DateFormatter.localizedString(from: $0, dateStyle: .short,
                                          timeStyle: .short)
        } ?? "未知日期"
        let gps = asset.location.map {
            String(format: "%.6f, %.6f", $0.coordinate.latitude,
                   $0.coordinate.longitude)
        } ?? "无 GPS"
        return "\(date) · \(gps)"
    }
}

final class PhotoLibraryModel: ObservableObject {
    @Published var photos: [PhotoEntry] = []
    @Published var status = "尚未读取照片"
    @Published var isWorking = false

    func requestAccessAndLoad() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .authorized, .limited:
                    self.loadPhotos()
                default:
                    self.status = "没有照片库读写权限，请到系统设置中授权"
                }
            }
        }
    }

    func loadPhotos() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 300
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var items: [PhotoEntry] = []
        result.enumerateObjects { asset, _, _ in
            items.append(PhotoEntry(asset: asset))
        }
        photos = items
        status = "已加载 \(items.count) 张照片（最多显示 300 张）"
    }

    func copyDate(sourceID: String, targetID: String) {
        guard sourceID != targetID,
              let source = photos.first(where: { $0.id == sourceID })?.asset,
              let target = photos.first(where: { $0.id == targetID })?.asset else {
            status = "请选择不同的源照片和目标照片"
            return
        }
        guard let date = source.creationDate else {
            status = "源照片没有拍摄日期"
            return
        }
        updateDate(asset: target, date: date)
    }

    func updateDate(targetID: String, date: Date) {
        guard let target = photos.first(where: { $0.id == targetID })?.asset else {
            status = "请先选择目标照片"
            return
        }
        updateDate(asset: target, date: date)
    }

    private func updateDate(asset: PHAsset, date: Date) {
        isWorking = true
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest(for: asset).creationDate = date
        } completionHandler: { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isWorking = false
                self.status = success ? "拍摄日期修改成功" :
                    "拍摄日期修改失败：\(error?.localizedDescription ?? "未知错误")"
                if success { self.loadPhotos() }
            }
        }
    }

    func copyGPS(sourceID: String, targetID: String) {
        guard sourceID != targetID else {
            status = "请选择不同的源照片和目标照片"
            return
        }
        guard let source = photos.first(where: { $0.id == sourceID })?.asset,
              let target = photos.first(where: { $0.id == targetID })?.asset else {
            status = "请先选择两张照片"
            return
        }
        guard let location = source.location else {
            status = "源照片没有 GPS 位置"
            return
        }
        isWorking = true
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest(for: target).location = location
        } completionHandler: { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isWorking = false
                self.status = success ? "修改成功" :
                    "修改失败：\(error?.localizedDescription ?? "未知错误")"
                if success { self.loadPhotos() }
            }
        }
    }
}
```

### 4.4 `Sources/ContentView.swift`

```swift
import SwiftUI

struct ContentView: View {
    @StateObject private var library = PhotoLibraryModel()
    @State private var sourceID = ""
    @State private var targetID = ""
    @State private var selectedDate = Date()
    @State private var pendingEdit: PendingEdit?
    @State private var showWriteConfirmation = false

    private enum PendingEdit {
        case copyDate(sourceID: String, targetID: String)
        case setDate(targetID: String, date: Date)
        case copyGPS(sourceID: String, targetID: String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("照片库") {
                    Button("读取 / 刷新照片") {
                        library.requestAccessAndLoad()
                    }
                    Text(library.status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("源照片（复制它的位置）") {
                    Picker("源照片", selection: $sourceID) {
                        Text("请选择").tag("")
                        ForEach(library.photos) { photo in
                            Text(photo.title).tag(photo.id)
                        }
                    }
                }

                Section("目标照片（修改它的位置）") {
                    Picker("目标照片", selection: $targetID) {
                        Text("请选择").tag("")
                        ForEach(library.photos) { photo in
                            Text(photo.title).tag(photo.id)
                        }
                    }
                }

                Section("拍摄日期") {
                    Button("将源照片拍摄日期复制到目标照片") {
                        pendingEdit = .copyDate(sourceID: sourceID, targetID: targetID)
                        showWriteConfirmation = true
                    }
                    .disabled(library.isWorking || sourceID.isEmpty ||
                              targetID.isEmpty || sourceID == targetID)

                    DatePicker("设置目标拍摄日期", selection: $selectedDate,
                               displayedComponents: [.date, .hourAndMinute])
                    Button("写入所选日期") {
                        pendingEdit = .setDate(targetID: targetID, date: selectedDate)
                        showWriteConfirmation = true
                    }
                    .disabled(library.isWorking || targetID.isEmpty)
                }

                Section("GPS") {
                    Button("将源照片 GPS 写入目标照片") {
                        pendingEdit = .copyGPS(sourceID: sourceID, targetID: targetID)
                        showWriteConfirmation = true
                    }
                    .disabled(library.isWorking || sourceID.isEmpty ||
                              targetID.isEmpty || sourceID == targetID)
                }
            }
            .navigationTitle("iPhotoExifEditor")
            .confirmationDialog("确认修改照片", isPresented: $showWriteConfirmation,
                                titleVisibility: .visible) {
                Button("确认写入") {
                    guard let edit = pendingEdit else { return }
                    pendingEdit = nil
                    switch edit {
                    case let .copyDate(sourceID, targetID):
                        library.copyDate(sourceID: sourceID, targetID: targetID)
                    case let .setDate(targetID, date):
                        library.updateDate(targetID: targetID, date: date)
                    case let .copyGPS(sourceID, targetID):
                        library.copyGPS(sourceID: sourceID, targetID: targetID)
                    }
                }
                Button("取消", role: .cancel) { pendingEdit = nil }
            } message: {
                Text(confirmationText)
            }
            .onAppear { library.requestAccessAndLoad() }
        }
    }

    private func photoLabel(_ id: String) -> String {
        let title = library.photos.first(where: { $0.id == id })?.title ?? "未知照片"
        return "\(title)（ID: \(id)）"
    }

    private var confirmationText: String {
        guard let edit = pendingEdit else { return "未选择修改操作。" }
        let detail: String
        switch edit {
        case let .copyDate(sourceID, targetID):
            detail = "将源照片 \(photoLabel(sourceID)) 的日期复制到目标 \(photoLabel(targetID))。"
        case let .setDate(targetID, date):
            let value = DateFormatter.localizedString(from: date, dateStyle: .medium,
                                                        timeStyle: .short)
            detail = "将目标 \(photoLabel(targetID)) 的日期设为 \(value)（当前时区）。"
        case let .copyGPS(sourceID, targetID):
            detail = "将源照片 \(photoLabel(sourceID)) 的位置复制到目标 \(photoLabel(targetID))。"
        }
        return detail + " 不会删除、生成或替换图片。"
    }
}
```

这是一版功能验证界面：提供 GPS 复制、日期复制和日期手工编辑，并在每次写入前确认目标；GPS 手工输入/清除可作为下一次迭代。没有缩略图，因此相近拍摄时间的照片不容易区分。建议先验证 API 和安装流程，再增加缩略图选择器。若实际使用照片很多，优先实现分页/网格而不是一次列出所有照片。

## 5. GitHub Actions 编译未签名 IPA

创建 `.github/workflows/build.yml`：

```yaml
name: Build iPhotoExifEditor IPA

on:
  workflow_dispatch:
  push:
    branches: [master]

jobs:
  build:
    runs-on: macos-26
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Show Xcode
        run: xcodebuild -version

      - name: Install XcodeGen
        run: brew install xcodegen

      - name: Generate Xcode project
        run: xcodegen generate

      - name: Build for iPhone
        run: |
          xcodebuild \
            -project iPhotoExifEditor.xcodeproj \
            -scheme iPhotoExifEditor \
            -configuration Release \
            -sdk iphoneos \
            -destination 'generic/platform=iOS' \
            -derivedDataPath build \
            CODE_SIGNING_ALLOWED=NO \
            build

      - name: Package IPA
        run: |
          mkdir -p Payload
          cp -R build/Build/Products/Release-iphoneos/iPhotoExifEditor.app Payload/
          zip -qry iPhotoExifEditor.ipa Payload
          unzip -l iPhotoExifEditor.ipa | head -30

      - name: Upload IPA
        uses: actions/upload-artifact@v4
        with:
          name: iPhotoExifEditor-IPA
          path: iPhotoExifEditor.ipa
```

**说明：** `macos-26` 的实际可用性和预装 Xcode 版本取决于 GitHub Actions 当前 Runner 环境。如果仓库不支持该标签，改用 GitHub 官方当前支持的 macOS Runner 标签，并确认其 `xcodebuild -version`。`brew install xcodegen` 需要网络与 Homebrew 可用。这里使用 `build` 而非 `archive/exportArchive`，因为目标是供 SideStore 重新签名的未签名 IPA。

操作流程：

1. 将上述文件提交到 GitHub 仓库的 `master` 分支。
2. 打开仓库 **Actions** → **Build iPhotoExifEditor IPA** → **Run workflow**（也可直接 Push 触发）。
3. 等待 Build 成功。
4. 在该 Workflow Run 页面下载 Artifact `iPhotoExifEditor-IPA`。
5. 解压 GitHub 下载的 Artifact ZIP，取得内部的 `iPhotoExifEditor.ipa`。
6. 将 IPA 传到 iPhone，在 SideStore 中导入并安装。
7. 首次运行时允许照片库读写访问，选择源照片、目标照片并测试。

## 6. 版本升级与 SideStore

- **通常不需要先卸载旧版**：在 SideStore 中安装新版 IPA，若最终 Bundle ID 和签名身份兼容，系统通常会作为同一 App 的更新处理。
- 固定 `PRODUCT_BUNDLE_IDENTIFIER`，例如始终为 `com.yourname.iphotoexifeditor`。
- 每次构建建议增加 `CURRENT_PROJECT_VERSION`，例如 1 → 2 → 3；需要时增加 `MARKETING_VERSION`。
- SideStore 可能重写 Bundle ID 或采用特定签名方式。若发生覆盖安装失败，先检查最终签名后的 App 身份，而不是立即卸载。
- 卸载会丢失 App 沙盒数据并可能重置权限；PhotoKit 写入系统照片库的修改不等同于 App 沙盒数据。

### Windows 上检查 IPA 标识

```python
import zipfile
import plistlib

with zipfile.ZipFile("iPhotoExifEditor.ipa") as ipa:
    plist_path = next(p for p in ipa.namelist()
                      if p.startswith("Payload/") and p.endswith(".app/Info.plist"))
    info = plistlib.loads(ipa.read(plist_path))
    for key in ("CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion"):
        print(key, info.get(key))
```

这检查的是**IPA 内原始标识**，不一定等于 SideStore 重新签名后的最终标识。

## 7. 测试计划

1. **权限**：完全授权、有限照片访问、拒绝访问三种情况。
2. **无 GPS 源照片**：应拒绝写入并显示原因。
3. **同一照片**：禁止源和目标相同。
4. **成功写入**：目标 `PHAsset.location` / `creationDate` 更新，图库中没有新照片。
5. **删除与覆盖保护**：在测试图库中核对操作前后的照片数量及 `localIdentifier`，确认没有照片被删除，原有图片文件未被替换。未来生成新图片时，再测同名文件和重复导入，确认已有文件及资产均未被覆盖。
6. **日期和时区**：验证 `DatePicker` 输入、跨时区显示、照片库排序及复制日期的一致性。
7. **保留画质**：确认未使用图片重新编码操作。
8. **iCloud 照片**：测试云端资产和同步后在其他设备上的表现。
9. **导出 EXIF**：AirDrop 到另一设备或导出原件/当前版本后，用 ExifTool 分别检查 GPS。注意“导出未修改的原件”和“导出当前版本”可能得到不同结果。
10. **中国大陆坐标**：选取已知实际位置，比较原始 EXIF、`PHAsset.location`、Apple 地图显示位置；不要在未验证前自动套用 GCJ-02 转换。
11. **覆盖升级**：构建号递增，重新经 SideStore 安装，确认旧版被更新且设置保留。

在电脑上可使用 ExifTool 检查实际文件：

```bash
exiftool -GPSLatitude -GPSLongitude -GPSLatitudeRef -GPSLongitudeRef -n photo.heic
```

## 8. 后续增强建议

按优先级：

1. **缩略图网格**：使用 `PHImageManager.requestImage` 展示授权照片，明确区分源/目标。
2. **批量应用**：一个源照片的位置写入多个目标照片；每个目标分别记录成功/失败。
3. **手工输入坐标**：接受十进制度和 DMS（度分秒），检查纬度 [-90, 90]、经度 [-180, 180]。
4. **MapKit 地图选点**：显示选点经纬度，并在中国大陆实际验证坐标一致性。
5. **清除位置**：将 `PHAssetChangeRequest.location` 设为 `nil`（需要确认具体资产操作是否成功）。
6. **批量修改拍摄日期**：支持统一日期或按时间差平移。
7. **EXIF 文件编辑模式（明确不属于第一阶段）**：若以后需要修改文件元数据，另行评估 ImageIO 方案；生成结果必须另存，不得删除或覆盖原始图片及任何已有图片。

## 9. 常见问题

**Q：必须购买 Apple Developer 会员吗？**
A：以上云端构建未签名 IPA 的过程不需要。SideStore 侧载仍受 Apple ID、签名证书、安装数量、刷新周期等机制约束。

**Q：Windows 能直接运行 iOS 模拟器吗？**
A：没有成熟通用的 Windows iOS 26 模拟器可运行这类 SwiftUI + PhotoKit App。需要真机测试或 macOS 上的官方 Simulator；PhotoKit 对真实照片库的修改尤其应在真机验证。

**Q：调用 `PHAssetChangeRequest` 是私有 API 吗？**
A：不是，它是 Apple 公开的 PhotoKit API，第三方应用可在权限允许的前提下调用。

**Q：照片原始 EXIF 一定会跟着改变吗？**
A：不保证。该 API 修改的是 Photos 资产的位置属性，不是公开的原始文件字节编辑接口。

**Q：SideStore 更新 App 要先删除旧版吗？**
A：通常不需要。保持 Bundle ID 和签名身份兼容，直接安装新版即可；具体取决于 SideStore 的重签名结果。

## 10. 官方资料

- [Apple — PHAssetChangeRequest](https://developer.apple.com/documentation/photos/phassetchangerequest)
- [Apple — PHAssetChangeRequest.location](https://developer.apple.com/documentation/photos/phassetchangerequest/location)
- [Apple — PHAssetChangeRequest.creationDate](https://developer.apple.com/documentation/photos/phassetchangerequest/creationdate)
- [Apple — PHPhotoLibrary](https://developer.apple.com/documentation/photos/phphotolibrary)
- [Apple — PHAsset](https://developer.apple.com/documentation/photos/phasset)
- [Apple — ImageIO](https://developer.apple.com/documentation/imageio)
- [GitHub — Actions macOS Runner](https://github.com/actions/runner-images)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- [SideStore](https://sidestore.io/)

---

**推荐起步路线：** 先用上面的最小工程验证「读取位置/日期 → 修改目标 `PHAsset.location` / `.creationDate` → SideStore 覆盖安装」，然后再开发缩略图选择器、手工 GPS 和地图选点。第一阶段禁止引入 ImageIO 文件改写、任意 EXIF 编辑、GCJ-02 自动转换。
