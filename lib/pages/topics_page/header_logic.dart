import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart' show ScrollSpringSimulation, Simulation, SpringDescription, SpringSimulation;
import 'package:flutter/scheduler.dart' show Ticker;

import '../../utils/motion_springs.dart';

/// Header 区域常量。
///
/// 顶部 = 常驻工具栏 48px（☰ + 聚合筛选菜单标题「最新 ▾」+ 右簇
/// 🔕(条件)·搜索落位·🔔）。可折叠段三段式：搜索胶囊行 48（折叠时
/// 胶囊 Rect.lerp 连续 morph 缩进常驻行右簇的落位格 —— 头部内
/// "一镜到底"）→ 分类 chips 行 40 → 条件标签行 36。
const toolbarRowHeight = 48.0;
const capsuleRowHeight = 48.0;
const navRowHeight = 40.0;
const tagsRowHeight = 36.0;

/// 首页运动系统统一弹簧,定义与说明见 [kHeaderMotionSpring]。
final SpringDescription kHeaderSpringLocal = kHeaderSpringDescription;

/// 顶栏收放控制器。两种收放语义分治（iOS/Telegram 搜索栏范式）：
///
/// - **胶囊段 = 位置驱动**：`capsuleOffset = pixels.clamp(0, 48)`，是
///   滚动位置的纯函数 —— 搜索胶囊只在列表顶部 48px 内擦洗展开/收起，
///   深处上滑不会冒出来（搜索是"内容的一部分"，随内容离场回场）。
/// - **工具段（chips 行 + 底栏联动）= enterAlways 增量驱动**：深处
///   上滑即回、下滑即走（chips/底栏是"工具"）;近顶被位置钳制强制
///   全展开，与胶囊段无缝衔接。
///
/// snap/展开只动本 controller 或驱动列表，头部是 overlay 层自行收放。
class HeaderCollapseController extends ChangeNotifier {
  HeaderCollapseController({
    required TickerProvider vsync,
    required this.onVisibilityChanged,
    required bool locked,
    required double extent,
  }) : _vsync = vsync,
       _locked = locked {
    _applyExtent(extent);
  }

  final TickerProvider _vsync;

  /// 可见性联动（1 - barOffset/barExtent），供底栏滑出等外部消费。
  /// 通知发生在滚动回调/动画 tick（build 之外），可同步写 provider。
  final ValueChanged<double> onVisibilityChanged;

  AnimationController? _snapAnim;
  double _capsuleOffset = 0.0;
  double _barOffset = 0.0;
  double _barExtent = capsuleRowHeight;
  double _extent = capsuleRowHeight;
  bool _locked;
  double _lastReportedVisibility = 1.0;

  /// 本次手势/滚轮会话起点的列表位置与工具段收起量（ScrollStart
  /// (drag)/滚轮会话首事件写入）。顶带吸附按起点分治迟滞;工具段
  /// 回滚判定需要起点收起量（区分"收起态被蹭开"与"展开态收到一半"，
  /// 见 _settleBarAfterScroll）。
  double gestureStartPixels = 0.0;
  double gestureStartBarOffset = 0.0;

  void noteGestureStart(double pixels) {
    gestureStartPixels = pixels;
    gestureStartBarOffset = _barOffset;
  }

  // —— 胶囊 morph 弹簧跟随器 ——
  // morph 若被滚动 1:1 擦洗，整段飞行只映射在头 48px 滚动距离里：快甩
  // 两三帧滚完 = 胶囊瞬移进角落;方向微抖 = 整段横飞反复。跟随器让
  // 滚动只改目标值，morph 以临界阻尼弹簧趋近 —— 带速度状态，目标
  // 反向时运动连续无折角（一阶指数滤波在反向瞬间有可感的"折"）。
  Ticker? _morphTicker;
  double _morph = 0.0;
  double _morphVelocity = 0.0;
  Duration? _lastMorphTick;

  /// 平滑后的胶囊 morph 进度（0=整行胶囊，1=落位图标）。
  /// **只驱动胶囊 rect 飞行与落位 spacer**（快甩不瞬移）;布局占位
  /// 用 [rowProgress]。
  double get morphProgress => _morph;

  /// 胶囊行**布局**进度：收起方向跟随滚动位置 1:1（raw），展开方向
  /// 跟随 morph 弹簧（平滑）。收起时行高与内容严格同步 —— 内容顶边
  /// 全程贴着头部下缘 8px 呼吸位滑行，首卡圆角"顶上去"清晰可见
  /// （行高若吃 morph 平滑值，快收时行还没让开、内容已到，被下缘
  /// 直线拦腰斩 = "动画开始就是直角线"）;展开时内容在远离下缘，
  /// 平滑无副作用。
  double get rowProgress {
    final raw = (_capsuleOffset / capsuleRowHeight).clamp(0.0, 1.0);
    return raw > _morph ? raw : _morph;
  }

  double get _morphTarget =>
      (_capsuleOffset / capsuleRowHeight).clamp(0.0, 1.0);

  void _syncMorph() {
    if ((_morphTarget - _morph).abs() < 0.001) return;
    final ticker = _morphTicker ??= _vsync.createTicker(_onMorphTick);
    if (!ticker.isActive) {
      _lastMorphTick = null;
      ticker.start();
    }
  }

  void _onMorphTick(Duration elapsed) {
    final last = _lastMorphTick;
    _lastMorphTick = elapsed;
    final dt =
        ((last == null ? 16.7 : (elapsed - last).inMicroseconds / 1000.0) /
                1000.0)
            .clamp(0.0, 0.05);
    final target = _morphTarget;
    // 临界阻尼弹簧半隐式积分（ω=√(stiffness/mass)，与全局弹簧
    // kHeaderSpringLocal 同参 kHeaderMotionSpring）：a = ω²·(target-x) − 2ω·v
    const omega = 22.4; // sqrt(kHeaderMotionSpring.stiffness / 1)
    final accel =
        omega * omega * (target - _morph) - 2 * omega * _morphVelocity;
    _morphVelocity += accel * dt;
    _morph = (_morph + _morphVelocity * dt).clamp(0.0, 1.0);
    if ((target - _morph).abs() < 0.003 && _morphVelocity.abs() < 0.05) {
      _morph = target;
      _morphVelocity = 0.0;
      _morphTicker?.stop();
      _lastMorphTick = null;
    }
    notifyListeners();
  }

  /// 胶囊段收起量（位置驱动，0 = 全展开胶囊，48 = 已 morph 成图标）
  double get capsuleOffset => _capsuleOffset;

  /// 工具段收起量（enterAlways 累计，0 = chips/底栏全显）
  double get barOffset => _barOffset;

  /// 工具段总量（chips+标签行高;无 chips 时退化为 48，保证底栏联动
  /// 仍有收放行程）
  double get barExtent => _barExtent;

  /// 工具段收起进度 0..1（chips 行 heightFactor 与底栏可见性共用）
  double get barProgress =>
      _barExtent <= 0 ? 0.0 : (_barOffset / _barExtent).clamp(0.0, 1.0);

  /// chip→标题飞行进度（barProgress 的语义别名：单列出来方便日后
  /// 独立调曲线而不牵动布局口径）
  double get chipFlightProgress => barProgress;

  /// 可折叠总高（胶囊 48 + chips/标签行;列表 topInset 同源）
  double get extent => _extent;

  set extent(double value) {
    if (_extent == value) return;
    // setter 在 build 期被调（_syncTabsIfNeeded 路径），不能同步
    // notify/写 provider;夹紧与可见性重报推迟到帧末。
    _applyExtent(value);
    stopSnap();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setBarOffset(_barOffset.clamp(0.0, _barExtent), force: true);
    });
  }

  void _applyExtent(double value) {
    _extent = value;
    final rest = value - capsuleRowHeight;
    _barExtent = rest > 0 ? rest : capsuleRowHeight;
  }

  bool get isSnapping => _snapAnim?.isAnimating ?? false;

  /// hideBarOnScroll 关闭时锁定全展开
  set locked(bool value) {
    if (_locked == value) return;
    _locked = value;
    if (value) {
      stopSnap();
      _setCapsuleOffset(0.0, instantMorph: true);
      _setBarOffset(0.0);
    }
  }

  /// 消化一次列表滚动：胶囊段位置驱动 + **单向粘滞**——收起方向随
  /// 位置立即走;展开方向仅在用户上滑（delta<0）进入顶部区时随位置。
  /// tab 切换遗留的"胶囊已折叠、列表在顶部"失配不会被下滑/惯性误
  /// 展开（折叠状态跨 tab 粘滞），上滑到顶自然长回。
  /// 工具段按增量累计（[accumulateBar] false = 越界回弹段不喂）;
  /// 近顶钳制：pixels < 48 时工具段强制全展开。
  void handleScroll(double delta, double pixels, {bool accumulateBar = true}) {
    if (_locked) return;
    stopSnap();
    final posOffset = pixels.clamp(0.0, capsuleRowHeight);
    if (posOffset > _capsuleOffset || delta < 0) {
      _setCapsuleOffset(posOffset);
    }
    final cap = (pixels - capsuleRowHeight).clamp(0.0, _barExtent);
    final next = accumulateBar
        ? (_barOffset + delta).clamp(0.0, cap)
        : _barOffset.clamp(0.0, cap);
    _setBarOffset(next);
  }

  /// 工具段 snap 到全显(0)或全隐([barExtent])。只动 overlay 的 chips
  /// 行与底栏，列表内容不动。统一弹簧 + 继承 [velocity]（px/s，
  /// barOffset 增大方向为正）——快甩快收、慢松缓归，跟手段与动画段
  /// 速度连续。[duration] Duration.zero = 立即跳变（外部状态同步用）。
  void snapBar(double target, {double velocity = 0, Duration? duration}) {
    if (_locked) return;
    stopSnap();
    if (duration == Duration.zero) {
      _setBarOffset(target);
      return;
    }
    if (_barOffset == target && velocity == 0) return;
    final controller = AnimationController.unbounded(vsync: _vsync);
    _snapAnim = controller;
    controller.addListener(() {
      _setBarOffset(controller.value.clamp(0.0, _barExtent));
    });
    controller
        .animateWith(
          SpringSimulation(kHeaderSpringLocal, _barOffset, target, velocity),
        )
        .whenComplete(() {
          if (identical(_snapAnim, controller)) {
            _snapAnim = null;
            _setBarOffset(target);
          }
          controller.dispose();
        });
  }

  /// 工具段兜底吸附（正常路径下物理层耦合收尾已把工具段送到边，
  /// 这里恒 no-op;只兜 extent 突变/短列表滚不动等物理层覆盖不到的
  /// 残余半开）。规则从简：过半收、不过半开;[listPixels] 提供收起
  /// 可达性门禁——内容没滚过锚位时强收会在头部下缘与内容顶边间
  /// 凭空造出空白带，一律反转为回开。
  void snapBarToNearest({double velocity = 0, double? listPixels}) {
    if (_locked) return;
    if (_barOffset <= 0 || _barOffset >= _barExtent) return;
    double target = _barOffset > _barExtent / 2 ? _barExtent : 0.0;
    if (target >= _barExtent && listPixels != null) {
      final cap = (listPixels - capsuleRowHeight).clamp(0.0, _barExtent);
      if (cap < _barExtent) target = 0.0;
    }
    snapBar(target, velocity: velocity);
  }

  /// 可折叠段当前**可见高度**（tab 自己的折叠总量 [tabExtent] 口径）：
  /// 骨架屏/错误页等非滚动态的顶部让位用 —— 它们没有滚动位置可与
  /// 头部互动，让位必须实时贴着头部下缘（胶囊折叠时少让 48px，
  /// 否则头部与内容之间露空洞）。与头部布局同源：胶囊段吃
  /// rowProgress（收起 1:1/展开平滑，与胶囊行占位一致）、工具段吃
  /// barProgress，收放/吸附全程贴合。
  double visibleExtentFor(double tabExtent) {
    final capsuleVisible = capsuleRowHeight * (1.0 - rowProgress);
    final rest = tabExtent - capsuleRowHeight;
    final barVisible = rest > 0 ? rest * (1.0 - barProgress) : 0.0;
    return capsuleVisible + barVisible;
  }

  /// 折叠锚位：内容顶边不露空洞所需的最小滚动位置 = 头部收起总量
  /// （胶囊段 + 工具段，按 tab 自己的 [tabExtent] 折算）。列表 attach
  /// /切 tab 适配用 —— 只对齐 capsuleOffset 会漏工具段收起量
  /// （chips 折叠时 pill 上方露 40px，截图实锤）。
  double collapsedAnchorFor(double tabExtent) {
    final rest = tabExtent - capsuleRowHeight;
    final barCollapsed = rest > 0 ? rest * barProgress : 0.0;
    return _capsuleOffset + barCollapsed;
  }

  /// 展开头部（切 tab 横滑起步、scrollToTop、关闭折叠偏好时调用）。
  /// 胶囊一并展开：位置驱动下一旦列表滚动会立即重新对齐，仅作为
  /// 过渡期的视觉兜底（避免相邻贴顶 tab 在横滑中露出 48px 空隙）。
  void expand({bool animate = true}) {
    if (_locked) {
      _setCapsuleOffset(0.0, instantMorph: true);
      _setBarOffset(0.0);
      return;
    }
    _setCapsuleOffset(0.0, instantMorph: !animate);
    if (animate) {
      snapBar(0.0);
    } else {
      stopSnap();
      _setBarOffset(0.0);
    }
  }

  void stopSnap() {
    final anim = _snapAnim;
    if (anim == null) return;
    _snapAnim = null;
    anim.stop();
    anim.dispose();
  }

  void _setCapsuleOffset(double value, {bool instantMorph = false}) {
    if (_capsuleOffset != value) {
      _capsuleOffset = value;
      if (instantMorph) {
        _morphTicker?.stop();
        _lastMorphTick = null;
        _morph = _morphTarget;
      } else {
        _syncMorph();
      }
      notifyListeners();
    } else if (instantMorph && _morph != _morphTarget) {
      _morphTicker?.stop();
      _lastMorphTick = null;
      _morph = _morphTarget;
      notifyListeners();
    }
  }

  void _setBarOffset(double value, {bool force = false}) {
    if (_barOffset == value && !force) return;
    _barOffset = value;
    notifyListeners();
    final visibility = (1.0 - barProgress).clamp(0.0, 1.0);
    // 0.01 节流；端点必须精确送达（底栏全隐/全显判定依赖 0.0/1.0）
    if (visibility != _lastReportedVisibility &&
        ((visibility - _lastReportedVisibility).abs() > 0.01 ||
            visibility == 0.0 ||
            visibility == 1.0)) {
      _lastReportedVisibility = visibility;
      onVisibilityChanged(visibility);
    }
  }

  @override
  void dispose() {
    stopSnap();
    _morphTicker?.dispose();
    super.dispose();
  }
}

// ─── TopicsPage ───

/// 顶带 + 深区工具段的吸附物理（**耦合收尾**定案）。
///
/// 两个战场，一个原则：**settle 期间栏与内容一体移动**——位移要么
/// 顺着手势方向补完（≤剩余行程），要么整段撤销（净位移归零），
/// 永不出现"栏自己动、内容留在原地"的错位。
///
/// 1. **胶囊带**：弹道落点停进 (0, 48) 时按手势起点分治迟滞——
///    顶部起手落点 > 36 才 commit 收起，否则回滚展开;深处起手落点
///    < 12 才 assist 全开，否则回滚收起锚位。胶囊是位置纯函数，
///    驱动列表即一体。
/// 2. **深区工具段**：chips/底栏 half-open 且弹道自己送不到边时，
///    弹簧把**列表**滚到"工具段恰好到边"的位置——增量经 enterAlways
///    记账自然驱动工具段同步，栏沿与内容行相对静止（此前 ScrollEnd
///    → snapBar 是 overlay-only：栏收回去、列表下滑位移留在原地，
///    每次短滑内容凭空多出栏漏出的高度 —— 本次翻车实锤）。同一套
///    起手锚定迟滞（75% 行程才换状态，不足全撤）。
///
/// 越界（下拉刷新）走平台物理。
class TopSnapScrollPhysics extends ScrollPhysics {
  const TopSnapScrollPhysics({required this.controller, super.parent});

  /// 读手势起点快照与工具段状态（noteGestureStart 维护）
  final HeaderCollapseController controller;

  @override
  TopSnapScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return TopSnapScrollPhysics(
      controller: controller,
      parent: buildParent(ancestor),
    );
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final base = super.createBallisticSimulation(position, velocity);
    // 越界（下拉刷新回弹等）交给平台物理
    if (position.outOfRange) return base;

    // 弹道落点（取大有限时刻：所有模拟均已收敛;不用 infinity ——
    // spring 解析解含 t·e^{-ωt} 项，无穷时刻是 inf·0 = NaN）
    final endPixels = base?.x(100.0) ?? position.pixels;
    if (!endPixels.isFinite) return base;
    const band = capsuleRowHeight;

    // —— 胶囊带：落点停进 (0, 48) ——
    if (endPixels > 0 && endPixels < band) {
      final fromDeep = controller.gestureStartPixels >= band;
      double target;
      if (fromDeep) {
        target = endPixels < band / 4 ? 0.0 : band;
      } else {
        target = endPixels > band * 3 / 4 ? band : 0.0;
      }
      if (target > position.maxScrollExtent) target = 0.0;
      if (target == position.pixels &&
          velocity.abs() < toleranceFor(position).velocity) {
        return null;
      }
      return ScrollSpringSimulation(
        kHeaderSpringLocal,
        position.pixels,
        target,
        velocity,
        tolerance: toleranceFor(position),
      );
    }

    // —— 深区工具段耦合收尾 ——
    final barExtent = controller.barExtent;
    final barOffset = controller.barOffset;
    if (position.pixels >= band &&
        barExtent > 0 &&
        barOffset > 0.5 &&
        barOffset < barExtent - 0.5) {
      // 弹道行程足以把工具段送到边（记账器吃满 delta）则不干预
      final predicted = (barOffset + (endPixels - position.pixels)).clamp(
        0.0,
        barExtent,
      );
      if (predicted <= 0.5 || predicted >= barExtent - 0.5) return base;

      // 起手锚定迟滞：从收起态起手要拉出 75% 才 commit 展开;从
      // 展开态起手要推进 75% 才 commit 收起;不足一律原路撤销
      final startBar = controller.gestureStartBarOffset;
      double targetBar;
      if (startBar >= barExtent - 0.5) {
        targetBar = barOffset <= barExtent * 0.25 ? 0.0 : barExtent;
      } else if (startBar <= 0.5) {
        targetBar = barOffset >= barExtent * 0.75 ? barExtent : 0.0;
      } else {
        targetBar = barOffset > barExtent / 2 ? barExtent : 0.0;
      }
      var listTarget = position.pixels + (targetBar - barOffset);
      // 收起可达性：滚动余量不足则反转为展开（防底部强收露空白）
      if (targetBar > barOffset && listTarget > position.maxScrollExtent) {
        listTarget = position.pixels - barOffset;
      }
      // 不越入胶囊带：expand-commit 压到 48 为止（缺口由近顶钳制
      // cap = pixels-48 收编，工具段照样到边），否则弹簧停进带内
      // 会触发二次 goBallistic 的反向修正 = 可感的二段抖
      listTarget = listTarget.clamp(band, position.maxScrollExtent);
      if (listTarget == position.pixels &&
          velocity.abs() < toleranceFor(position).velocity) {
        return null;
      }
      return ScrollSpringSimulation(
        kHeaderSpringLocal,
        position.pixels,
        listTarget,
        velocity,
        tolerance: toleranceFor(position),
      );
    }

    return base;
  }
}

/// 抽屉拖拽桥：TabBarView 的 physics（随 build 重建、不可变）与
/// State 间的可变状态通道。
class DrawerPullBridge {
  /// 手指按下的拖拽会话中（ScrollStart.dragDetails != null 维护;
  /// 挡住 ballistic 越界误触发抽屉）
  bool dragging = false;

  /// 本次手势已进入"拉抽屉"模式（首缘越界触发，手势结束前锁存：
  /// 期间全部水平位移归抽屉，含往回滑 —— 否则回滑会被 PageView
  /// 接手直接切 tab）
  bool pulling = false;
}

/// 首页 TabBarView 常驻 physics：首缘（"全部"页再向右拖）把越界量
/// 转交抽屉跟手拖出，PageView 自身**永不越界**（首缘表现为 clamping，
/// iOS 无橡皮筋残留）;进入拉抽屉模式后本次手势位移全量归抽屉。
/// 其余方向/页面完全走平台默认物理。
class DrawerPullPagerPhysics extends ScrollPhysics {
  const DrawerPullPagerPhysics({
    required this.bridge,
    required this.onPull,
    required this.onPullEnd,
    super.parent,
  });

  final DrawerPullBridge bridge;

  /// 位移增量（正 = 手指向右 = 抽屉拉出方向）
  final ValueChanged<double> onPull;

  /// 手势结束（velocityDx 正 = 向右甩）
  final ValueChanged<double> onPullEnd;

  @override
  DrawerPullPagerPhysics applyTo(ScrollPhysics? ancestor) {
    return DrawerPullPagerPhysics(
      bridge: bridge,
      onPull: onPull,
      onPullEnd: onPullEnd,
      parent: buildParent(ancestor),
    );
  }

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) {
    // 无收藏分类时 TabBarView 只有"全部"一页（min==max），默认物理
    // 拒绝手势 → 拖拽会话不建立，首缘桥永远无法介入（"没有分类栏
    // 就不能右滑"）。始终收下手势：单页下所有位移都走首缘越界分支
    // 转给抽屉。
    return true;
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    // 拉抽屉模式：手势位移全量转交（offset 正 = 手指向右）
    if (bridge.pulling) {
      onPull(offset);
      return 0;
    }
    return super.applyPhysicsToUserOffset(position, offset);
  }

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    // 首缘越界（已在第一页仍向右拖）→ 进入拉抽屉模式：越界量转交
    // 抽屉，PageView 钉在 minScrollExtent（不产生 iOS 橡皮筋）
    if (bridge.dragging &&
        value < position.minScrollExtent &&
        position.pixels <= position.minScrollExtent + precisionErrorTolerance) {
      if (!bridge.pulling) bridge.pulling = true;
      onPull(position.minScrollExtent - value);
      return value - position.minScrollExtent;
    }
    if (bridge.pulling) {
      // 模式中冻结页面（含往回滑）
      return value - position.pixels;
    }
    return super.applyBoundaryConditions(position, value);
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if (bridge.pulling) {
      bridge.pulling = false;
      // scroll velocity 正 = pixels 增大 = 手指向左;抽屉口径取反
      onPullEnd(-velocity);
      return null;
    }
    return super.createBallisticSimulation(position, velocity);
  }
}

/// tab 列表滚动控制器：初始滚动位置动态跟随胶囊折叠态。
///
/// 骨架屏 ↔ 数据列表切换会销毁/重建 Scrollable（position detach 后
/// 重新 attach），`initialScrollOffset` 是构造期快照满足不了"attach
/// 那一刻的胶囊态"——用 resolver 每次 attach 现取;attach 回调再做
/// 帧末校验兜底（PageStorage 恢复陈旧位置等杂例）。
class TabListScrollController extends ScrollController {
  TabListScrollController({
    required this.initialOffsetResolver,
    required this.onAttachPosition,
  });

  final double Function() initialOffsetResolver;
  final void Function(ScrollPosition position) onAttachPosition;

  @override
  double get initialScrollOffset => initialOffsetResolver();

  @override
  void attach(ScrollPosition position) {
    super.attach(position);
    onAttachPosition(position);
  }
}

