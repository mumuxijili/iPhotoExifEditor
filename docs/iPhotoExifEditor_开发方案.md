# iPhotoExifEditor：iOS 照片元数据编辑工具开发方案（第一阶段）

> 目标环境：Windows + VS Code 开发；GitHub Actions 的 macOS Runner 编译；SideStore 侧载到 iOS 26。
> 核心 API：Apple PhotoKit 的公开接口 `PHAssetChangeRequest.location` 和 `PHAssetChangeRequest.creationDate`。
> 文档版本：2026-10-09（第一阶段范围调整）。

## 1. 目标与边界

实现一个自用 iOS App，名称为 **iPhotoExifEditor**。第一阶段只修改 PhotoKit 公开支持的照片资产属性，不实现任意 EXIF 字段写入：

1. 读取系统「照片」图库中的照片，以缩略图网格显示用户已授权访问的照片。
2. 用户从网格选择一张目标照片，进入包含 GPS 和拍摄日期两个 Tab 的编辑模式。
3. GPS 支持查看当前位置、复制为 JSON、在系统地图上长按选择新位置，以及从另一张照片导入位置。
4. 拍摄日期支持查看和手工修改，并可从另一张照片导入日期。
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

照片资产、编辑草稿、复制的 JSON 与最终写入值统一使用 **WGS-84**。中国大陆地图底图若出现偏移，用户可启用“**中国大陆地图校正（GCJ-02）**”：显示标注时执行 WGS-84 → GCJ-02，地图长按选点后立即执行 GCJ-02 → WGS-84，再进入草稿和写入流程。转换只发生在地图边界，不能把 GCJ-02 写入 PHAsset.location。

MapKit 没有提供稳定、公开的运行时接口来判断当前底图是否要求 GCJ-02，因此该校正是持久化的显式开关，默认关闭，避免已经由系统处理坐标时发生二次偏移。转换使用粗略经纬度范围；香港、澳门和边界地区也可能落在该范围内，需在设置中关闭校正或用已知地标进行真机核对。

界面使用 SwiftUI 点坐标、安全区和可用容器尺寸进行布局，照片预览、地图高度、内容边距与网格列数均随屏幕变化；不按具体机型像素写死分支。因此 iPhone 16、17、18 系列及对应 Pro、Max 尺寸由同一套规则覆盖，并同时支持横竖屏和较大字体。

### 2.5 页面结构与编辑流程

第一阶段采用“选择目标照片 → 编辑草稿 → 对比变化 → 二次确认写入”的交互。进入最终确认前，所有改动只存在于 App 内存中的草稿，不调用 PhotoKit 写入。

#### 主界面：照片网格

1. 首次进入时，通过明确的用户操作申请照片库读写权限。
2. 授权后使用 `PHImageManager.requestImage` 加载缩略图，以网格形式显示当前授权范围内的照片。
3. 点击一张照片，将其作为目标照片进入编辑模式。主界面不提供删除操作。右上角提供设置入口，集中显示中国大陆地图校正开关以及版本、Build 号。
4. 在 `.limited` 权限下只显示已授权照片。右上角“添加可访问照片”在应用内打开系统有限照片授权选择页；选择页关闭后刷新网格。选择器由实际显示的 UIKit 宿主页面在 `viewDidAppear` 之后呈现。
5. 网格按需加载缩略图，不一次请求原图；支持滚动时的请求取消和缓存，避免大量照片导致内存压力。

#### 编辑模式

1. 页面上部显示目标照片预览，并保留其 `localIdentifier` 作为本次编辑的稳定标识。
2. 页面下部使用两个可切换的 Tab：**GPS**和**拍摄日期**。
3. 每个 Tab 分别保存原始值和草稿值。切换 Tab、返回 GPS 编辑页面或选择导入来源都不能直接修改图库。
4. 退出存在未保存草稿的编辑模式时，提示用户放弃草稿或继续编辑。

建议的数据状态：

```swift
struct PhotoEditDraft {
    let targetAssetID: String
    let originalLocation: CLLocation?
    var pendingLocation: CLLocation?
    let originalCreationDate: Date?
    var pendingCreationDate: Date?
}
```

实现时还需要单独记录“未修改”和“明确清除”两种状态，不能只依赖可选值 `nil` 区分。第一阶段若暂不提供清除位置，则只需要“未修改”和“设置为新位置”。

#### GPS Tab

1. 使用系统 MapKit 地图显示目标照片的当前位置；没有 GPS 时显示明确的空状态。
2. 地图下方提供“编辑”和“复制”按钮。
3. “复制”把当前 GPS 编码为 UTF-8 JSON，并写入系统剪贴板。没有 GPS 时禁用该按钮或显示原因。
4. JSON 使用稳定版本字段，第一版格式如下；没有可靠值的可选字段应省略，不伪造为 `0`：

```json
{
  "format": "iPhotoExifEditor.location",
  "version": 1,
  "coordinateSystem": "WGS84",
  "latitude": 22.3193,
  "longitude": 114.1694,
  "altitude": 12.5,
  "horizontalAccuracy": 5.0,
  "timestamp": "2026-10-09T10:30:00+08:00"
}
```

其中 `latitude` 和 `longitude` 必须存在；其余字段按原始 `CLLocation` 是否提供有效值决定是否输出。复制只操作剪贴板，不修改照片。

#### GPS 编辑页面

1. 页面主体是 MapKit 地图，初始显示目标照片原来的位置；无原位置时显示适当的默认区域，并提示用户长按选择位置。
2. 用户长按地图后，将长按点转换为经纬度并保存为候选位置。再次长按空白处可移动候选位置；长按橙色候选标记后可拖动微调，拖动结束时更新 WGS-84 草稿。蓝色原位置标记不可拖动。
3. 页面提供“从其他照片导入”按钮。点击后打开与主界面一致的照片网格选择器，从另一张可访问照片读取 `PHAsset.location`。
4. 导入用的照片只作为位置来源，不成为写入目标。来源照片没有 GPS、与目标相同或读取失败时显示原因，不改变已有草稿。
5. 提供地点和地址搜索。用户点选 MapKit 搜索结果后，将该位置设为候选位置并返回地图；候选位置仍需用户确认。
6. GPS 编辑页面的“确认”只把候选位置写入编辑草稿并返回编辑模式；“取消”丢弃本次候选值。

优先复用应用自己的 PhotoKit 网格选择器完成“从其他照片导入”。这样可以直接取得 `PHAsset` 及其 `location`，并与有限照片权限保持一致；系统 `PhotosPicker` 主要返回可传输的图片内容，不适合作为获取现有 `PHAsset.location` 的主要路径。

#### 新旧位置对比与最终写入

1. GPS 草稿发生变化后，编辑模式中的地图同时显示原位置和新位置，使用不同颜色及“原位置”“新位置”标签；只有一个位置时仍应明确它的含义。
2. 页面底部显示“取消”和“确认”。“取消”丢弃 GPS 草稿并恢复原始显示。
3. 点击“确认”后弹出第二次确认，展示目标照片、旧坐标、新坐标，以及“不会删除、生成或替换图片”的说明。
4. 用户再次确认后，重新按 `targetAssetID` 获取目标 `PHAsset`，确认目标仍存在且草稿对应同一资产，再调用 `PHAssetChangeRequest.location`。
5. 写入期间禁用重复提交。成功后重新读取资产并核对实际位置；失败时显示 PhotoKit 返回的错误，不能把草稿显示成已成功写入。

#### 拍摄日期 Tab

拍摄日期采用相同的草稿和确认机制：显示原日期，允许手工选择新日期或从另一张照片导入，返回编辑模式后展示新旧日期，点击确认后再进行二次确认，最后才写入 `PHAssetChangeRequest.creationDate`。界面必须同时显示日期、时间和当前时区，避免只显示本地时间造成误解。

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

## 4. API 验证原型与项目骨架

目录结构：

```text
iPhotoExifEditor/
├── README.md
├── project.yml
├── Sources/
│   ├── Assets.xcassets/
│   ├── ContentView.swift
│   ├── CoordinateConverter.swift
│   ├── GPSEditorView.swift
│   ├── iPhotoExifEditorApp.swift
│   ├── LocationClipboardPayload.swift
│   ├── LocationMapView.swift
│   ├── LimitedLibraryPickerView.swift
│   ├── LocationSearchView.swift
│   ├── SettingsView.swift
│   ├── PhotoAssetImageView.swift
│   ├── PhotoEditDraft.swift
│   ├── PhotoEditorView.swift
│   ├── PhotoLibraryStore.swift
│   └── PhotoSourcePickerView.swift
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
    deploymentTarget: "17.0"
    sources:
      - Sources
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.example.iphotoexifeditor
        SWIFT_VERSION: "5.0"
        TARGETED_DEVICE_FAMILY: "1,2"
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_NSPhotoLibraryUsageDescription: "需要读取并修改所选照片的位置和拍摄日期"
        INFOPLIST_KEY_PHPhotoLibraryPreventAutomaticLimitedAccessAlert: YES
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

下面的 `PhotoLibraryModel` 是 PhotoKit 读写能力的验证代码。正式界面必须按 2.5 节实现缩略图网格、编辑草稿、地图选点、来源照片选择和二次确认；模型还需要补充缩略图请求、按标识重新获取资产及写入后校验。

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

以上 `ContentView` 仅用于验证 PhotoKit 调用和构建流程，不作为第一阶段正式界面。正式实现应拆分为照片网格、照片编辑、GPS 编辑和来源照片选择等视图，并遵循 2.5 节的草稿及二次确认流程；不能直接沿用此处以文字 Picker 选择源/目标照片的交互。

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

1. **权限与网格**：验证完全授权、有限照片访问和拒绝访问；有限权限下点击右上角按钮应在应用内打开系统授权选择页，增加照片并关闭后网格自动刷新；缩略图滚动稳定且不会加载全部原图。
2. **目标选择**：点击网格中的照片后，编辑页预览、`localIdentifier`、GPS 和日期都对应同一资产。
3. **无 GPS 来源**：从其他照片导入时应拒绝没有位置的来源，并保持原有草稿不变。
4. **同一照片**：来源照片与目标照片相同时拒绝导入。
5. **地图选点与草稿**：长按生成或移动候选位置；拖动橙色标记可微调并保持当前地图缩放；搜索结果点选后成为候选位置。在 GPS 编辑页确认后只更新草稿，不立即修改 `PHAsset`。
6. **JSON 复制**：检查格式标识、版本、经纬度精度及可选字段；复制操作不改变照片。
7. **新旧位置与取消**：原位置和新位置标记正确；取消后恢复原值，退出未保存编辑时正确提示。
8. **二次确认**：确认框显示正确目标及新旧坐标；取消二次确认不得写入，连续点击不得重复提交。
9. **成功写入**：最终确认后目标 `PHAsset.location` / `creationDate` 更新，重新读取值一致，图库中没有新照片。
10. **删除与覆盖保护**：核对操作前后的照片数量及 `localIdentifier`，确认没有照片被删除，原有图片文件未被替换。
11. **日期和时区**：验证手工输入、从照片导入、新旧值对比、跨时区显示及复制日期的一致性。
12. **保留画质**：确认未使用图片重新编码操作。
13. **iCloud 照片**：测试云端资产、下载中状态及同步后在其他设备上的表现。
14. **导出 EXIF**：AirDrop 到另一设备或导出原件/当前版本后，用 ExifTool 分别检查 GPS。注意“导出未修改的原件”和“导出当前版本”可能得到不同结果。
15. **中国大陆坐标**：使用已知地标分别验证校正开关关闭和开启状态；开启时检查 WGS-84 标注转换到 GCJ-02 后与底图重合，并检查地图选点反向转换为 WGS-84 后再写入。
16. **覆盖升级**：构建号递增，重新经 SideStore 安装，确认旧版被更新且设置保留。

在电脑上可使用 ExifTool 检查实际文件：

```bash
exiftool -GPSLatitude -GPSLongitude -GPSLatitudeRef -GPSLongitudeRef -n photo.heic
```

## 8. 后续增强建议

按优先级：

1. **批量应用**：一个来源照片的位置写入多个目标照片；每个目标分别记录成功/失败，并在写入前显示目标数量。
2. **手工输入坐标**：接受十进制度和 DMS（度分秒），检查纬度 [-90, 90]、经度 [-180, 180]。
3. **清除位置**：将 `PHAssetChangeRequest.location` 设为 `nil`，并明确区分“未修改”和“清除位置”。
4. **批量修改拍摄日期**：支持统一日期或按时间差平移。
5. **EXIF 文件编辑模式（明确不属于第一阶段）**：若以后需要修改文件元数据，另行评估 ImageIO 方案；生成结果必须另存，不得删除或覆盖原始图片及任何已有图片。

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
