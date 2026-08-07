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
