# iPhotoExifEditor

一个使用公开 PhotoKit API 修改照片位置和拍摄日期的自用 iOS 应用。

## 当前功能

- 申请照片库读写权限并以缩略图网格显示可访问照片
- 查看照片当前 GPS 和拍摄日期
- 在系统地图中长按选择新位置，并可对中国大陆底图启用 GCJ-02 显示校正
- 从另一张照片导入 GPS 或拍摄日期
- 将当前显示的 GPS 以 WGS-84 坐标复制为带版本信息的 JSON
- 按可用屏幕尺寸和安全区自适应 iPhone 布局
- 在写入前显示新旧值并进行二次确认
- 写入后重新读取目标资产并校验结果

应用不会删除照片，不会生成新照片，也不会替换图片文件。最终确认只会修改明确选择的 `PHAsset.location` 或 `PHAsset.creationDate`。

## 云端构建

本项目在 Windows 上编辑，通过 GitHub Actions 的 macOS Runner 编译：

1. 在 `project.yml` 中把 `PRODUCT_BUNDLE_IDENTIFIER` 改成你长期使用的唯一标识。
2. 提交并推送到 `master` 分支。
3. 打开 GitHub 仓库的 Actions 页面，等待 **Build iPhotoExifEditor IPA** 完成。
4. 下载 `iPhotoExifEditor-IPA` Artifact，解压得到未签名 IPA。
5. 使用 SideStore 重签名并安装。

也可以在 Actions 页面手动运行工作流。

## 项目生成

GitHub Actions 使用 XcodeGen 从 `project.yml` 生成 Xcode 工程。生成的 `.xcodeproj` 不需要提交。

详细设计、安全约束和真机测试项目见 [开发方案](docs/iPhotoExifEditor_开发方案.md)。
