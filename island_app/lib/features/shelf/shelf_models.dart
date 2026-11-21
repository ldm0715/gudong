import 'package:flutter/material.dart';

/// 中转站条目。引用原文件路径，不保存文件内容。
class ShelfItem {
  const ShelfItem({
    required this.id,
    required this.path,
    required this.name,
    required this.kind,
    required this.size,
    required this.modifiedMs,
    required this.addedAtMs,
    required this.missing,
  });

  final String id;
  final String path;
  final String name;

  /// `image` / `video` / `audio` / `document` / `archive` / `installer` / `folder` / `file`
  final String kind;
  final int size;
  final int modifiedMs;
  final int addedAtMs;
  final bool missing;

  bool get isFolder => kind == 'folder';

  String get sizeLabel => isFolder ? '文件夹' : formatBytes(size);

  factory ShelfItem.fromJson(Map<String, dynamic> json) {
    return ShelfItem(
      id: json['id']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      kind: json['kind']?.toString() ?? 'file',
      size: (json['size'] as num?)?.toInt() ?? 0,
      modifiedMs: (json['modifiedMs'] as num?)?.toInt() ?? 0,
      addedAtMs: (json['addedAtMs'] as num?)?.toInt() ?? 0,
      missing: json['missing'] == true,
    );
  }
}

IconData shelfIconFor(String kind) => switch (kind) {
  'image' => Icons.image_outlined,
  'video' => Icons.movie_outlined,
  'audio' => Icons.audiotrack_outlined,
  'document' => Icons.description_outlined,
  'archive' => Icons.folder_zip_outlined,
  'installer' => Icons.apps_outlined,
  'folder' => Icons.folder_outlined,
  _ => Icons.insert_drive_file_outlined,
};

String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = unit == 0 ? 0 : (value < 10 ? 1 : 0);
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}
