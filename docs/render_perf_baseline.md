# fluxdo_render 性能 benchmark

## 阶段 1 退出标准:典型帖子 build 时间不超过 legacy ✅

测试环境:flutter widget test(无真 GPU,相对对比)
测试代码:`test/perf/render_benchmark_test.dart`
跑法:`flutter test test/perf/render_benchmark_test.dart`

## 结果(2026-06-23)

| 场景 | FluxdoRender | Legacy(ChunkedHtmlContent) | 子包优势 |
|---|---|---|---|
| 长帖冷构建(30 段 + 5 lightbox + 代码块 + quote_card)| **34.3 ms** | 539.9 ms | **15.7x** |
| 中帖暖 rebuild(8 段 + list + blockquote,setState)| **4.5 ms** | 5.0 ms | 1.1x |
| 短帖冷构建(1 段)| **6.7 ms** | 71.5 ms | **10.7x** |

## 分析

### 子包冷构建快 10-16 倍

主要原因:

1. **fwfh 工厂注册开销**:legacy 每次 build 都要走 BuildOp 注册 + tree 遍历;子包 parser 是一次性 DOM → BlockNode,build 直接 dispatch
2. **chunk 协调开销**:legacy ChunkedHtmlContent 把长帖切成多个 chunk 异步加载,首次构建有调度成本;子包同步 build 全部
3. **CSS 模拟开销**:legacy 用 fwfh 的 customStylesBuilder 走 CSS 解析;子包是直接 Flutter Padding/Container/TextStyle

### 暖 rebuild 接近

setState 重 build 时,两边都走 Element diff + 局部刷新,差距不大(子包 4.5ms / legacy 5.0ms)。但子包仍微优,因为 widget tree 更浅。

## 阶段 2 关注点

- 子包接入 callback(主项目 image / code highlighter)后,要重测一次 — callback 内部的真实 image / highlight 加载可能成主要耗时
- 滚动卡顿不是 build 时间,是 layout/paint 时间,需要真机 scroll bench

## 结论

**阶段 1 退出标准达成**:子包 build 时间显著低于 legacy(冷构建快 10-16 倍)。
可以正式 dogfood 切 New 引擎。
