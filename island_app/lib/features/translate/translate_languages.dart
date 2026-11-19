/// 翻译目标语言与引擎的展示文案。语言代码与 sidecar 的映射表保持一致。
class TranslateLanguage {
  const TranslateLanguage(this.code, this.label);

  final String code;
  final String label;
}

const List<TranslateLanguage> translateLanguages = [
  TranslateLanguage('zh-CN', '中文（简体）'),
  TranslateLanguage('zh-TW', '中文（繁體）'),
  TranslateLanguage('en', 'English'),
  TranslateLanguage('ja', '日本語'),
  TranslateLanguage('ko', '한국어'),
  TranslateLanguage('fr', 'Français'),
  TranslateLanguage('de', 'Deutsch'),
  TranslateLanguage('es', 'Español'),
  TranslateLanguage('ru', 'Русский'),
  TranslateLanguage('pt', 'Português'),
  TranslateLanguage('it', 'Italiano'),
];

const List<TranslateLanguage> translateSourceLanguages = [
  TranslateLanguage('auto', '自动识别'),
  ...translateLanguages,
];

class TranslateProviderOption {
  const TranslateProviderOption(this.id, this.label, this.detail);

  final String id;
  final String label;
  final String detail;
}

const List<TranslateProviderOption> translateProviders = [
  TranslateProviderOption('auto', '自动', '按已配置的 Key 依次选择大模型、DeepL、微软、MyMemory'),
  TranslateProviderOption('llm', '大模型', 'OpenAI 兼容的 chat completions'),
  TranslateProviderOption('deepl', 'DeepL', '免费版 Key 以 :fx 结尾时自动走 api-free'),
  TranslateProviderOption('caiyun', '彩云小译', '官方测试 Token 免密钥可用；填个人 Token 更稳定'),
  TranslateProviderOption('microsoftFree', '微软（免密钥）', 'Edge 内部接口，无需 Key，可能随时失效'),
  TranslateProviderOption('mymemory', 'MyMemory', '免密钥兜底，匿名每天约 5000 字符'),
];

String translateLanguageLabel(String code) =>
    translateLanguageLabelIn(translateLanguages, code);

String translateLanguageLabelIn(List<TranslateLanguage> options, String code) {
  for (final language in options) {
    if (language.code == code) return language.label;
  }
  return code;
}

String translateProviderLabel(String id) {
  for (final provider in translateProviders) {
    if (provider.id == id) return provider.label;
  }
  return id;
}

/// 岛体顶栏空间有限，用短名称。
String translateProviderShortLabel(String id) {
  return switch (id) {
    'llm' => '大模型',
    'deepl' => 'DeepL',
    'caiyun' => '彩云',
    'microsoftFree' => '微软免密',
    'mymemory' => 'MyMemory',
    _ => '自动',
  };
}
