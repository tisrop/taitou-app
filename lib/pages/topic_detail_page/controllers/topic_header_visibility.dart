/// 当话题头部尚未挂载时，判断列表是否真的位于话题顶部。
///
/// 详情列表以进入楼层为中心锚定：第一页尚未加载时，即使滚动 offset
/// 接近 0，也可能仍有更早楼层位于上方，因此必须同时确认首帖已加载。
bool shouldTreatMissingTopicHeaderAsTop({
  required bool hasFirstPost,
  required bool hasScrollClients,
  required double scrollOffset,
  required double appBarHeight,
}) {
  return hasFirstPost && hasScrollClients && scrollOffset <= appBarHeight;
}

/// 首帖状态没有发生变化时，是否仍需重新检查缺失的标题头部。
///
/// 从中途楼层进入时，首批数据可能连续多次都不包含首帖。此时状态保持
/// false，但内容首帧已经挂载，需要主动刷新 AppBar 的 scrolled-under
/// 状态；首帖已加载后的 true → true 则无需重复检查。
bool shouldRecheckMissingTopicHeader({
  required bool previousHasFirstPost,
  required bool nextHasFirstPost,
}) {
  return previousHasFirstPost == nextHasFirstPost && !nextHasFirstPost;
}
