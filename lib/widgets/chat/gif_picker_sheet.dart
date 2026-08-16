import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/s.dart';
import '../../models/chat/gif.dart';
import '../../providers/core_providers.dart';
import '../../widgets/common/visual/cached_image.dart';

/// GIF 选择面板。选中后 `Navigator.pop` 回传 [GifItem]。
///
/// 空搜索词时展示分类封面（`/gifs/categories.json`），点分类等价于用它的
/// searchterm 搜一次。
class GifPickerSheet extends ConsumerStatefulWidget {
  const GifPickerSheet({super.key});

  @override
  ConsumerState<GifPickerSheet> createState() => _GifPickerSheetState();
}

class _GifPickerSheetState extends ConsumerState<GifPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  Timer? _debounce;
  String _query = '';

  Future<List<GifCategory>>? _categoriesFuture;

  List<GifItem> _items = const [];
  String? _nextCursor;
  bool _loading = false;
  bool _loadingMore = false;
  Object? _error;

  /// 搜索请求的代次号。快速改词时，只认最后一次的结果，避免旧响应回来覆盖新的。
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _categoriesFuture = ref.read(discourseServiceProvider).getGifCategories();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels < position.maxScrollExtent - 400) return;
    unawaited(_loadMore());
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _search(value);
    });
  }

  Future<void> _search(String query) async {
    final trimmed = query.trim();
    setState(() {
      _query = trimmed;
      _items = const [];
      _nextCursor = null;
      _error = null;
      _loading = trimmed.isNotEmpty;
    });
    if (trimmed.isEmpty) return;

    final requestId = ++_requestId;
    try {
      final page = await ref.read(discourseServiceProvider).searchGifs(trimmed);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _items = page.items;
        _nextCursor = page.nextCursor;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    if (cursor == null || _loadingMore || _loading || _query.isEmpty) return;
    setState(() => _loadingMore = true);
    final requestId = _requestId;
    try {
      final page = await ref
          .read(discourseServiceProvider)
          .searchGifs(_query, cursor: cursor);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _items = [..._items, ...page.items];
        _nextCursor = page.nextCursor;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      // 翻页失败静默收尾，已有内容照常可用
      setState(() {
        _nextCursor = null;
        _loadingMore = false;
      });
    }
  }

  void _pickCategory(GifCategory category) {
    _searchController.text = category.searchTerm;
    _debounce?.cancel();
    unawaited(_search(category.searchTerm));
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final availableHeight =
        mediaQuery.size.height - mediaQuery.viewInsets.bottom;
    final panelHeight = (availableHeight * 0.72).clamp(360.0, 620.0);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final searchBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(
        color: colorScheme.outlineVariant.withValues(alpha: 0.9),
      ),
    );

    return SizedBox(
      height: panelHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
            child: TextField(
              controller: _searchController,
              onChanged: _onQueryChanged,
              textInputAction: TextInputAction.search,
              onSubmitted: (v) {
                _debounce?.cancel();
                unawaited(_search(v));
              },
              style: theme.textTheme.titleMedium,
              decoration: InputDecoration(
                hintText: context.l10n.chat_gifSearchHint,
                hintStyle: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
                  fontWeight: FontWeight.w400,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                border: searchBorder,
                enabledBorder: searchBorder,
                focusedBorder: searchBorder.copyWith(
                  borderSide: BorderSide(color: colorScheme.primary, width: 2),
                ),
                filled: true,
                fillColor: colorScheme.surface,
              ),
            ),
          ),
          if (_query.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: Text(
                context.l10n.chat_gifCategories,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w500,
                ),
              ),
            )
          else
            const SizedBox(height: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _query.isEmpty
                  ? _buildCategories(context)
                  : _buildResults(context),
            ),
          ),
          const _KlipyBrandFooter(),
        ],
      ),
    );
  }

  Widget _buildCategories(BuildContext context) {
    return FutureBuilder<List<GifCategory>>(
      future: _categoriesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final categories = snapshot.data;
        if (snapshot.hasError || categories == null || categories.isEmpty) {
          return _buildError(
            context,
            onRetry: () {
              setState(() {
                _categoriesFuture = ref
                    .read(discourseServiceProvider)
                    .getGifCategories();
              });
            },
          );
        }

        final left = <({GifCategory category, int index})>[];
        final right = <({GifCategory category, int index})>[];
        for (var index = 0; index < categories.length; index++) {
          final entry = (category: categories[index], index: index);
          (index.isEven ? left : right).add(entry);
        }

        return SingleChildScrollView(
          controller: _scrollController,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildCategoryColumn(left)),
              const SizedBox(width: 10),
              Expanded(child: _buildCategoryColumn(right)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCategoryColumn(
    List<({GifCategory category, int index})> entries,
  ) {
    return Column(
      children: [
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _CategoryTile(
              category: entry.category,
              aspectRatio: switch (entry.index % 4) {
                0 || 3 => 1,
                _ => 1.55,
              },
              onTap: () => _pickCategory(entry.category),
            ),
          ),
      ],
    );
  }

  Widget _buildResults(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _buildError(context, onRetry: () => _search(_query));
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(
          context.l10n.chat_gifNoResults,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    // 双列瀑布流：按累计高度往矮的那列放，避免 1:1 裁切把竖图切没。
    final left = <GifItem>[];
    final right = <GifItem>[];
    var leftHeight = 0.0;
    var rightHeight = 0.0;
    for (final item in _items) {
      // 用宽高比的倒数当"单位宽度下的高度"，列宽相同所以可直接比较
      final unitHeight = 1 / item.aspectRatio;
      if (leftHeight <= rightHeight) {
        left.add(item);
        leftHeight += unitHeight;
      } else {
        right.add(item);
        rightHeight += unitHeight;
      }
    }

    return SingleChildScrollView(
      controller: _scrollController,
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildColumn(left)),
              const SizedBox(width: 10),
              Expanded(child: _buildColumn(right)),
            ],
          ),
          if (_loadingMore)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }

  Widget _buildColumn(List<GifItem> items) {
    return Column(
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _GifTile(
              item: item,
              onTap: () => Navigator.pop(context, item),
            ),
          ),
      ],
    );
  }

  Widget _buildError(BuildContext context, {required VoidCallback onRetry}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.l10n.chat_gifLoadFailed,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: Text(context.l10n.chat_retry)),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.aspectRatio,
    required this.onTap,
  });

  final GifCategory category;
  final double aspectRatio;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedImage(
                url: category.image,
                fit: BoxFit.cover,
                placeholder: (_) => ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                    stops: [0.45, 1],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                  child: Text(
                    '#${category.displayName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      height: 1,
                      shadows: [
                        Shadow(
                          color: Colors.black54,
                          blurRadius: 6,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KlipyBrandFooter extends StatelessWidget {
  const _KlipyBrandFooter();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.65),
          ),
        ),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: 'POWERED BY  ',
              style: theme.textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.62),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
            const TextSpan(
              text: 'K',
              style: TextStyle(
                color: Color(0xFFF4C430),
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: -1,
              ),
            ),
            TextSpan(
              text: 'LIPY',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: -1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GifTile extends StatelessWidget {
  const _GifTile({required this.item, required this.onTap});

  final GifItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: AspectRatio(
          aspectRatio: item.aspectRatio,
          child: CachedImage(
            url: item.previewUrl,
            fit: BoxFit.cover,
            placeholder: (_) => ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ),
        ),
      ),
    );
  }
}
