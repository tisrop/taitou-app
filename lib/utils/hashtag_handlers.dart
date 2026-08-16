import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluxdo_render/fluxdo_render.dart'
    show hashtagIconResolver, hashtagTapHandler;

import '../models/category.dart';
import '../pages/category_topics_page.dart';
import '../pages/tag_topics_page.dart';
import '../providers/category_provider.dart';
import '../providers/core_providers.dart';
import 'discourse_url_parser.dart';
import 'font_awesome_helper.dart';
import 'tag_icon_list.dart';

/// 安装 hashtag 药丸的宿主图标解析和页面导航。
void installHashtagHandlers() {
  hashtagIconResolver = _resolveIcon;
  hashtagTapHandler = _handleTap;
}

IconData? _resolveIcon(BuildContext context, String? iconName, String href) {
  final category = _categoryFromHref(context, href);
  if (category != null) {
    var icon = FontAwesomeHelper.getIcon(category.icon)?.data;
    if (icon == null && category.parentCategoryId != null) {
      final parent = _categoryById(context, category.parentCategoryId!);
      icon = FontAwesomeHelper.getIcon(parent?.icon)?.data;
    }
    if (icon != null) return icon;
  }

  final tag = DiscourseUrlParser.parseTag(href);
  if (tag != null) {
    final icon = TagIconList.get(tag)?.icon.data;
    if (icon != null) return icon;
  }

  // Discourse 用 square-full 表示未配置图标，交给渲染包使用类型兜底。
  if (iconName != null && iconName != 'square-full') {
    return FontAwesomeHelper.getIcon(iconName)?.data;
  }
  return null;
}

bool _handleTap(BuildContext context, String href, String? ref, String label) {
  // 分类链接优先走本地 map；map 尚未预载(启动早期)时兜底从服务端拉取，
  // 避免降级成站内 WebView(丢原生导航/主题)。拉取失败或该分类不存在
  // 时再回落普通链接回调。
  final category = _categoryFromHref(context, href);
  if (category != null) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => CategoryTopicsPage(category: category)),
    );
    return true;
  }
  final categoryInfo = DiscourseUrlParser.parseCategory(href);
  if (categoryInfo != null) {
    _pushCategoryAfterLoad(context, categoryInfo.categoryId);
    return true;
  }

  final parsedTag = DiscourseUrlParser.parseTag(href);
  final explicitTag = ref?.endsWith('::tag') == true;
  if (parsedTag == null && !explicitTag) return false;

  var tag = ref ?? parsedTag ?? label;
  if (tag.endsWith('::tag')) {
    tag = tag.substring(0, tag.length - '::tag'.length);
  }
  tag = tag.trim();
  if (tag.isEmpty) return false;

  Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => TagTopicsPage(tagName: tag)));
  return true;
}

/// 分类 map 未预载时兜底：拉取分类后跳原生页；分类不存在则放弃
/// （调用方已返回 true 接管理航，此处静默不跳）。
void _pushCategoryAfterLoad(BuildContext context, int categoryId) {
  final container = ProviderScope.containerOf(context, listen: false);
  unawaited(
    () async {
      final categories = await container
          .read(discourseServiceProvider)
          .getCategories()
          .catchError((_) => <Category>[]);
      if (!context.mounted) return;
      final target = categories.where((c) => c.id == categoryId).firstOrNull;
      if (target == null) return;
      Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => CategoryTopicsPage(category: target)),
      );
    }(),
  );
}

Category? _categoryFromHref(BuildContext context, String href) {
  final info = DiscourseUrlParser.parseCategory(href);
  return info == null ? null : _categoryById(context, info.categoryId);
}

Category? _categoryById(BuildContext context, int id) {
  final container = ProviderScope.containerOf(context, listen: false);
  return container.read(categoryMapProvider).value?[id];
}
