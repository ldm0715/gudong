import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// 邮箱服务商标识。常用邮箱使用官方图标资源，其余使用品牌图标。
/// 颜色由调用方决定：设置窗口用品牌色，岛体用主题色。
class MailProviderBadge extends StatelessWidget {
  const MailProviderBadge({
    super.key,
    required this.provider,
    required this.color,
    this.size = 26,
    this.email,
  });

  final String provider;
  final Color color;
  final double size;

  /// 自定义 IMAP 用它识别 2925 等已知服务。
  final String? email;

  @override
  Widget build(BuildContext context) {
    final asset = _asset(provider, email);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.26),
      ),
      child: asset != null
          ? Image.asset(
              asset,
              width: size * 0.72,
              height: size * 0.72,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              cacheWidth: (size * 3).round(),
              cacheHeight: (size * 3).round(),
            )
          : _fallbackIcon(provider, size * 0.58, color),
    );
  }
}

Widget _fallbackIcon(String provider, double size, Color color) => switch (provider) {
  'gmail' => FaIcon(FontAwesomeIcons.google, size: size, color: color),
  'icloud' => FaIcon(FontAwesomeIcons.apple, size: size, color: color),
  'custom' => FaIcon(FontAwesomeIcons.server, size: size, color: color),
  _ => FaIcon(FontAwesomeIcons.envelope, size: size, color: color),
};

String? _asset(String provider, String? email) => switch (provider) {
  'qq' => 'assets/mail/qq.png',
  '163' => 'assets/mail/163.png',
  '126' => 'assets/mail/126.png',
  'exmail' => 'assets/mail/exmail.png',
  'custom' when (email ?? '').toLowerCase().endsWith('@2925.com') =>
    'assets/mail/2925.png',
  _ => null,
};
