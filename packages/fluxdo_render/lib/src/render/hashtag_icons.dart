import 'package:flutter/widgets.dart';

/// 把 cooked hashtag 的图标名映射为宿主所用的 [IconData]。
///
/// 子包不依赖具体图标库；宿主也可以结合 [href] 查分类或标签配置。
typedef HashtagIconResolver =
    IconData? Function(BuildContext context, String? iconName, String href);

/// 启动期由宿主安装一次。返回 null 时渲染器使用分类/标签默认图标。
HashtagIconResolver? hashtagIconResolver;

/// 点击 hashtag 药丸时由宿主决定是否接管导航。
///
/// [ref] 是 cooked 的 `data-ref`/`data-slug` 原值；[label] 是去掉前导
/// `#` 的显示文本。返回 false 时继续走普通链接回调。
typedef HashtagTapHandler =
    bool Function(BuildContext context, String href, String? ref, String label);

/// 启动期由宿主安装一次。
HashtagTapHandler? hashtagTapHandler;
