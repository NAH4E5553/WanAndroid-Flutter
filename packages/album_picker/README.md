# album_picker

独立Flutter图片单选包。Android API24+、iOS15+；当前开发工具Flutter3.47.4/Dart3.13.3、AGP9.1/Kotlin2.3.10、JDK17。最低OS不等于所有版本已验收。

- 四列网格、相册名称/数量、旋转箭头、部分授权管理；进入只检查，点击授权才申请。
- 图片按全局时间/ID排序后分页；API29+含已挂载MediaStore外部卷。iOS含普通用户相册及收藏/截图智能相册，不显示隐藏或Shared Albums专用集合。
- 浏览缩略图不允许联网；云端完整图片需要用户确认。当前可读版本导出为已应用方向的静态sRGB PNG，剥离源元数据，不保留HDR/动画。
- GIF取首显示帧；Live Photo只取当前静态资源。不读取其他App私有目录或厂商云账户。

## 接入

将整个目录复制到目标Flutter仓库，以path依赖接入。包不引用WanAndroid；示例在example中。iOS宿主Info.plist需配置：

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>展示相册和照片供你选择</string>
<key>PHPhotoLibraryPreventAutomaticLimitedAccessAlert</key>
<true/>
```

后一个配置影响整个宿主的有限照片自动提醒策略。本包提供主动管理入口。Android读取权限随插件Manifest合并：API24–32旧读取、API33图片读取、API34部分选择；无视频/音频/定位/全文件管理权限。发布渠道对头像用途的广泛读取可能有限制，需独立审核。

```dart
final cancellation = AlbumCancellation(); // 离页/切号时调用cancel()
final result = await showAlbumPicker(context,
  budget: AlbumBudget.avatar,
  cancellation: cancellation,
  theme: Theme.of(context),
);
try {
  switch (result.kind) {
    case AlbumResultKind.selected:
      // 先核验宿主账号/操作代次，再有界复制result.lease到自有候选。
      // lease已经是upright PNG，不能再应用一次EXIF方向。
      break;
    case AlbumResultKind.cameraRequested:
      // 宿主调用现有相机，并负责外部页面恢复。
      break;
    case AlbumResultKind.systemPickerRequested:
      // 宿主调用系统选择器；不依赖整库授权。
      break;
    case AlbumResultKind.cancelled:
    case AlbumResultKind.failed:
      break;
  }
} finally {
  await result.lease?.release(); // 成功、失败和身份失效都必须释放
}
```

不提供相机/系统选图实现的宿主传cameraEnabled:false/systemPickerEnabled:false；生产头像接入应保留系统退路。需要嵌入自有路由时直接使用`AlbumPickerPage(onComplete: ...)`；其余参数与便利入口相同，收到selected即接管租约，配置变化应使用新Key创建会话。通过`AlbumPickerOptions(translations: {...})`覆盖文案，主题使用theme参数。纯Dart结果类型也可从`package:album_picker/models.dart`导入。

## 文件与失败

默认输入32MiB、输出64MiB，8192单边/1600万像素；头像预算输出32MiB。不缩小大图绕过限制。流式读写和解码前头部校验失败会保留原头像。PNG可能比HEIC大并超限；系统内部下载、缓存和内存不受应用字节计数保证。

准备时返回取消本次并留网格，第二次返回退出。60秒准备超时；取消后旧任务最多等5秒停止，再选不会重置期限。无法停止时明确exportUnavailable并保留系统退路，不无限启动新任务。

租约只拥有包自有导出目录；不删源资源或插件未知路径，不全局清Flutter/系统缓存。正常release幂等；失败抛出cleanupFailed、可重试，下次创建会话也重试未完成清理；宿主应记录脱敏失败而不打印路径。异常终止遗留目录超过24小时在下次初始化清扫。租约不能当永久文件路径。照片访问缩小清理会话缩略图并拒收迟到结果；系统缓存由OS管理。

## 验证

包目录执行`flutter analyze`、`flutter test`；example独立执行双端构建。`tool/native_probe/main.swift`与生产ImageExport.swift可联合swiftc运行ImageIO受控样本验证，不能替代PhotoKit/iOS真机证据。Android原生BoundedOutputStreamTest覆盖超限前拒写、取消及写入错误保留。

开发证据、性能和平台未测边界在宿主docs的相册技术验证记录中登记。当前不发布pub.dev；LICENSE的最终公开分发许可由项目负责人决定。


Android受控设备专项（API30+）：在example目录执行`flutter test integration_test/android_device_album_test.dart -d <device-id> --dart-define=ALBUM_CONTROLLED_ANDROID=true`。仅在获授权的开发设备运行；debug夹具写入8张小型纯色PNG，记录并在teardown删除自己的URI，生产宿主和Release不含此入口。系统权限框需先拒绝、再允许完整访问；原生测试之后，在`files/album_test_phase.txt`分别出现`await_cancel_back`及`await_exit_back`时，各提交一次系统返回。该脚本需要这些外部操作，不属于无人值守CI。若进程被强制终止，应保留此测试App并重新运行，让seed先清理上次记录；不要先卸载而丢失夹具清理记录。快照只含自建资源，不能替代个人整库完整性及大图库性能验收。

API34+设备可追加`--dart-define=ALBUM_TEST_LIMITED=true`：第一次拒绝，第二次选“选择部分”，仅选择本轮新建纯色图片并确认；组件显示部分授权提示后点击管理入口，再选择一张纯色图片并确认，保持部分授权完成导出和返回专项。完整授权用不带该参数的独立轮次验证。MI17实测管理入口进入重选界面；系统设置改权限会中断当前测试进程，不能要求同一轮连续跨越此修改。只验证原生权限状态及管理入口，不以自建资源的可读数量断言个人图库授权子集。小米开发设备需允许USB安装及调试点击，并保持解锁；不要在测试运行中切换调试开关，以免ADB连接中断。
