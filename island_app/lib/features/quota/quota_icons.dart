import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/theme/island_colors.dart';
import '../../core/theme/island_metrics.dart';
import '../../core/theme/island_typography.dart';

/// 官方品牌图标；优先使用站点返回的 logo，缺失时退回内置资源或文字标记。
class QuotaProviderIcon extends StatelessWidget {
  const QuotaProviderIcon({
    super.key,
    required this.id,
    required this.fallback,
    required this.color,
    required this.size,
    this.logo,
  });

  final String id;
  final String fallback;
  final Color color;
  final double size;

  /// 站点图标 data URI，只在 New API 站点提供。
  final String? logo;

  static const Map<String, String> _assets = {
    'glm': 'assets/icons/zai.svg',
    'deepseek': 'assets/icons/deepseek.svg',
    'opencode': 'assets/icons/opencode.svg',
    'newapi': 'assets/icons/newapi.png',
    'krill': 'assets/icons/krill.png',
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final custom = _dataUri(logo);
    if (custom != null) {
      if (custom.mime == 'image/svg+xml') {
        return SvgPicture.memory(
          custom.bytes,
          width: size,
          height: size,
          errorBuilder: (_, _, _) =>
              _fallback(colors, asset: _assetFor(id)),
        );
      }
      return Image.memory(
        custom.bytes,
        width: size,
        height: size,
        cacheWidth: (size * 3).round(),
        cacheHeight: (size * 3).round(),
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => _fallback(colors, asset: _assetFor(id)),
      );
    }
    final asset = _assetFor(id);
    if (asset == null) return _fallback(colors);
    if (asset.endsWith('.png')) {
      return Image.asset(
        asset,
        width: size,
        height: size,
        cacheWidth: (size * 3).round(),
        cacheHeight: (size * 3).round(),
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => _fallback(colors),
      );
    }
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }

  static String? _assetFor(String id) =>
      _assets[id] ?? (id.startsWith('newapi:') ? _assets['newapi'] : null);

  static ({String mime, Uint8List bytes})? _dataUri(String? value) {
    if (value == null || value.isEmpty) return null;
    final comma = value.indexOf(',');
    if (!value.startsWith('data:') || comma < 0) return null;
    final meta = value.substring(5, comma);
    final mime = meta.split(';').first;
    try {
      return (mime: mime, bytes: base64Decode(value.substring(comma + 1)));
    } catch (_) {
      return null;
    }
  }

  Widget _fallback(IslandColors colors, {String? asset}) {
    if (asset != null && asset.endsWith('.png')) {
      return Image.asset(
        asset,
        width: size,
        height: size,
        cacheWidth: (size * 3).round(),
        cacheHeight: (size * 3).round(),
        filterQuality: FilterQuality.medium,
      );
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.chip,
        borderRadius: BorderRadius.circular(IslandMetrics.radiusTag),
      ),
      child: Text(
        fallback,
        maxLines: 1,
        style: IslandTypography.microStrong.tint(color),
      ),
    );
  }
}
