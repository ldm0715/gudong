import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/settings/settings_controller.dart';
import '../../core/theme/island_colors.dart';
import 'translate_controller.dart';
import 'translate_languages.dart';

class TranslateTab extends StatefulWidget {
  const TranslateTab({
    super.key,
    required this.controller,
    required this.settings,
  });

  final TranslateController controller;
  final SettingsController settings;

  @override
  State<TranslateTab> createState() => _TranslateTabState();
}

class _TranslateTabState extends State<TranslateTab> {
  bool _copied = false;

  void _translate() {
    final settings = widget.settings.settings;
    unawaited(
      widget.controller.translate(
        widget.controller.input.text,
        to: settings.translateTarget,
        provider: settings.translateProvider,
      ),
    );
  }

  Future<void> _copy() async {
    final text = widget.controller.result;
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => _copied = true);
    Future<void>.delayed(const Duration(seconds: 1), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _setSource(String? code) {
    if (code == null) return;
    final settings = widget.settings.settings;
    if (settings.translateSource == code) return;
    unawaited(
      widget.settings.save(settings.copyWith(translateSource: code)),
    );
  }

  void _setTarget(String? code) {
    if (code == null) return;
    final settings = widget.settings.settings;
    if (settings.translateTarget == code) return;
    unawaited(
      widget.settings.save(settings.copyWith(translateTarget: code)),
    );
  }

  void _setProvider(String? id) {
    if (id == null) return;
    final settings = widget.settings.settings;
    if (settings.translateProvider == id) return;
    unawaited(
      widget.settings.save(settings.copyWith(translateProvider: id)),
    );
  }

  /// Enter 确认，Shift+Enter 换行；输入法正在选词时不拦截 Enter。
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    if (widget.controller.input.value.composing.isValid) {
      return KeyEventResult.ignored;
    }
    _translate();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final controller = widget.controller;
    final settings = widget.settings.settings;
    final source = translateSourceLanguages.any(
      (item) => item.code == settings.translateSource,
    )
        ? settings.translateSource
        : 'auto';
    final target = translateLanguages.any(
      (item) => item.code == settings.translateTarget,
    )
        ? settings.translateTarget
        : translateLanguages.first.code;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _LanguageMenu(
              value: source,
              options: translateSourceLanguages,
              tooltip: '源语言',
              onChanged: _setSource,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Icon(
                Icons.arrow_forward_rounded,
                size: 12,
                color: colors.muted,
              ),
            ),
            _LanguageMenu(
              value: target,
              options: translateLanguages,
              tooltip: '目标语言',
              onChanged: _setTarget,
            ),
            const Spacer(),
            _ProviderMenu(
              value: settings.translateProvider,
              onChanged: _setProvider,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Focus(
                  onKeyEvent: _onKey,
                  child: TextField(
                    controller: controller.input,
                    expands: true,
                    maxLines: null,
                    minLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 12,
                      height: 1.35,
                      decoration: TextDecoration.none,
                    ),
                    cursorColor: colors.accent,
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: colors.surface,
                      hintText: 'Enter 翻译\nShift+Enter 换行',
                      hintMaxLines: 2,
                      hintStyle: TextStyle(color: colors.muted, fontSize: 11),
                      contentPadding: const EdgeInsets.all(8),
                      border: _border(colors.stroke),
                      enabledBorder: _border(colors.stroke),
                      focusedBorder: _border(colors.accent),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.stroke),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '译文',
                            style: TextStyle(
                              color: colors.muted,
                              fontSize: 10,
                              decoration: TextDecoration.none,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              controller.provider.isEmpty
                                  ? ''
                                  : translateProviderLabel(controller.provider),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: colors.muted,
                                fontSize: 9,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                          if (controller.result.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: _copy,
                              borderRadius: BorderRadius.circular(4),
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: Icon(
                                  _copied
                                      ? Icons.check_rounded
                                      : Icons.copy_rounded,
                                  size: 13,
                                  color: _copied
                                      ? colors.accent
                                      : colors.muted,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Expanded(
                        child: SingleChildScrollView(
                          child: SelectableText(
                            _resultText(controller),
                            style: TextStyle(
                              color: controller.error.isNotEmpty
                                  ? colors.warning
                                  : controller.result.isEmpty
                                  ? colors.muted
                                  : colors.text,
                              fontSize: 12,
                              height: 1.4,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static OutlineInputBorder _border(Color color) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: color),
    );
  }

  static String _resultText(TranslateController controller) {
    if (controller.error.isNotEmpty) return controller.error;
    if (controller.pending) return '翻译中…';
    if (controller.result.isEmpty) return '结果会显示在这里';
    return controller.result;
  }
}

class _LanguageMenu extends StatelessWidget {
  const _LanguageMenu({
    required this.value,
    required this.options,
    required this.tooltip,
    required this.onChanged,
  });

  final String value;
  final List<TranslateLanguage> options;
  final String tooltip;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final label = translateLanguageLabelIn(options, value);
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MenuAnchor(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(colors.cardBackground),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 4),
          ),
          maximumSize: const WidgetStatePropertyAll(Size(220, 220)),
        ),
        menuChildren: [
          for (final language in options)
            MenuItemButton(
              onPressed: () => onChanged(language.code),
              style: ButtonStyle(
                foregroundColor: WidgetStatePropertyAll(colors.text),
                minimumSize: const WidgetStatePropertyAll(Size(140, 32)),
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
              child: Text(
                language.label,
                style: const TextStyle(fontSize: 12),
              ),
            ),
        ],
        builder: (context, controller, child) {
          return InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () =>
                controller.isOpen ? controller.close() : controller.open(),
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.stroke),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 110),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 11,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 15,
                    color: colors.muted,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ProviderMenu extends StatelessWidget {
  const _ProviderMenu({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return Tooltip(
      message: '翻译引擎',
      waitDuration: const Duration(milliseconds: 600),
      child: MenuAnchor(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(colors.cardBackground),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 4),
          ),
          maximumSize: const WidgetStatePropertyAll(Size(220, 220)),
        ),
        menuChildren: [
          for (final provider in translateProviders)
            MenuItemButton(
              onPressed: () => onChanged(provider.id),
              style: ButtonStyle(
                foregroundColor: WidgetStatePropertyAll(colors.text),
                minimumSize: const WidgetStatePropertyAll(Size(140, 32)),
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
              child: Text(
                provider.label,
                style: const TextStyle(fontSize: 12),
              ),
            ),
        ],
        builder: (context, controller, child) {
          return InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () =>
                controller.isOpen ? controller.close() : controller.open(),
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.stroke),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 90),
                    child: Text(
                      translateProviderShortLabel(value),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 11,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 15,
                    color: colors.muted,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
