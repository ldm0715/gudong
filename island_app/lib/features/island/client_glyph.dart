import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/theme/island_colors.dart';

/// 微信 / QQ 的方形图标标识。
class ClientGlyph extends StatelessWidget {
  const ClientGlyph({super.key, required this.source, required this.size});

  final String source;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final qq = source == 'qq';
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: qq ? colors.qq : colors.wechat,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: FaIcon(
        qq ? FontAwesomeIcons.qq : FontAwesomeIcons.weixin,
        size: size * 0.62,
        color: Colors.white,
      ),
    );
  }
}
