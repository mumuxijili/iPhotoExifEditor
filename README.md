# iPhotoExifEditor

一个使用公开 PhotoKit API 修改照片位置和拍摄日期的自用 iOS 应用。

## 当前功能

- 申请照片库读写权限并以缩略图网格显示可访问照片；有限授权时通过右上角按钮在应用内增加可访问照片
- 查看照片当前 GPS 和拍摄日期
- 在系统地图中长按选择位置、拖动新位置标记微调，或搜索地点选取位置
- 在首页设置中控制中国大陆地图 GCJ-02 校正，并查看版本与 Build 号
- 从另一张照片导入 GPS 或拍摄日期
- 将当前显示的 GPS 以 WGS-84 坐标复制为带版本信息的 JSON
- 按可用屏幕尺寸和安全区自适应 iPhone 布局
- 在写入前显示新旧值并进行二次确认
- 写入后重新读取目标资产并校验结果

应用不会删除照片，不会生成新照片，也不会替换图片文件。最终确认只会修改明确选择的 `PHAsset.location` 或 `PHAsset.creationDate`。这些值属于照片图库资产；原始图片文件的 EXIF 不会直接改写。因此从其他应用选择原始文件发送时，接收方可能看不到在本 App 中新增的 GPS。

## 云端构建

本项目在 Windows 上编辑，通过 GitHub Actions 的 macOS Runner 编译：

1. 在 `project.yml` 中把 `PRODUCT_BUNDLE_IDENTIFIER` 改成你长期使用的唯一标识。
2. 提交并推送到 `master` 分支。
3. 打开 GitHub 仓库的 Actions 页面，等待 **Build iPhotoExifEditor IPA** 完成。
4. 在仓库的 **Releases** 页面下载 `iPhotoExifEditor.ipa`。Actions 页面仍会保留 `iPhotoExifEditor-IPA` Artifact。
5. 使用 SideStore 重签名并安装。

推送到 `master` 或在 `master` 上手动运行工作流时，编译成功后会直接创建 Release，附上本次编译的未签名 IPA。标签格式为 `v<版本号>-build<构建号>-run<运行 ID>-<尝试次数>`，每次运行都有独立标签，不查询旧版。版本号和 Build 号来自本次编译的 App。

## 抓取 iPhone 崩溃日志

稳定复现闪退后，在 iPhone 上打开 **设置 → 隐私与安全性 → 分析与改进 → 分析数据**，寻找时间最接近、文件名以 `iPhotoExifEditor` 开头的 `.ips` 报告。打开后用分享按钮保存并发送完整 `.ips` 文件；若没有同名报告，也检查对应时间的 `JetsamEvent_…`。请保留报告中的异常类型、崩溃线程和调用栈。无需安装 Xcode。

## 项目生成

GitHub Actions 使用 XcodeGen 从 `project.yml` 生成 Xcode 工程。生成的 `.xcodeproj` 不需要提交。

详细设计、安全约束和真机测试项目见 [开发方案](docs/iPhotoExifEditor_开发方案.md)。

## 开源许可

本项目采用 [MIT License](LICENSE)，版权署名为 `mumuxijili`。允许自由使用、修改、再发布及商业使用；分发本项目或其主要部分时，须保留版权声明和许可文本。应用内“设置 → 关于”也提供作者署名和完整许可证。
