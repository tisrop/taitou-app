// 这个文件不是 ES Module entry,build.mjs 读它的内容塞到 esbuild banner,
// 让它在 bundle 最顶部、所有 import 副作用之前执行。
//
// ensureHead 必须最早执行：es-module-shims 启动前 document.head 必须存在。
// 该 patch 同步、容错、只在缺少 head 时生效，不会扩散副作用。

(function () {
  // ===== 1) ensureHead =====
  try {
    if (
      typeof document !== 'undefined' &&
      document.documentElement &&
      !document.head
    ) {
      document.documentElement.insertBefore(
        document.createElement('head'),
        document.documentElement.firstChild,
      );
    }
  } catch (e) {}
})();
