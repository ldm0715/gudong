import 'package:flutter_test/flutter_test.dart';
import 'package:island_app/features/dashboard/metrics_models.dart';

void main() {
  const snapshot = MetricsSnapshot(
    uploadBps: 128000,
    downloadBps: 1572864,
    cpuPercent: 23.4,
    memoryPercent: 61,
    memoryUsedBytes: 8589934592,
    memoryTotalBytes: 17179869184,
    cpuMhz: 3200,
    cpuMaxMhz: 4800,
    gpus: [
      GpuSnapshot(
        id: 'gpu0',
        name: 'Test GPU 0',
        utilizationPercent: 42,
        memoryUsedBytes: 4 * 1024 * 1024 * 1024,
        memoryTotalBytes: 12 * 1024 * 1024 * 1024,
        memoryPercent: 33,
      ),
      GpuSnapshot(
        id: 'gpu1',
        name: 'Test GPU 1',
        utilizationPercent: 8,
        memoryUsedBytes: 100 * 1024 * 1024,
        memoryTotalBytes: 512 * 1024 * 1024,
        memoryPercent: 19.5,
      ),
    ],
    totalUploadBytes: 1024 * 1024,
    totalDownloadBytes: 1024 * 1024 * 1024,
    updatedAtMs: 1794997775244,
  );

  test('parses a metrics snapshot and computes derived totals', () {
    final parsed = MetricsSnapshot.fromJson(const {
      'uploadBps': 1.5,
      'downloadBps': 2.5,
      'cpuPercent': 12.0,
      'memoryPercent': 48.0,
      'memoryUsedBytes': 8000,
      'memoryTotalBytes': 16000,
      'cpuMhz': 3200,
      'cpuMaxMhz': 4800,
      'gpus': [
        {
          'id': 'gpu0',
          'name': 'Test GPU',
          'utilizationPercent': 42.0,
          'memoryUsedBytes': 4000,
          'memoryTotalBytes': 12000,
          'memoryPercent': 33.0,
        },
      ],
      'totalUploadBytes': 100,
      'totalDownloadBytes': 200,
      'updatedAtMs': 1,
    });
    expect(parsed.totalBps, 4.0);
    expect(parsed.totalTrafficBytes, 300);
    expect(parsed.memoryUsedBytes, 8000);
    expect(parsed.gpus.single.name, 'Test GPU');
    expect(parsed.gpus.single.utilizationPercent, 42.0);
    expect(parsed.gpus.single.memoryTotalBytes, 12000);
  });

  test('formats rates with binary units', () {
    expect(formatRate(0), '0 B/s');
    expect(formatRate(128000), '125 KB/s');
    expect(formatRate(1572864), '1.5 MB/s');
    expect(formatRate(1572864, compact: true), '1.5M');
  });

  test('formats traffic and frequency', () {
    expect(formatTraffic(1024 * 1024), '1 MB');
    expect(formatTraffic(1024 * 1024 * 1024, compact: true), '1G');
    expect(formatFrequency(3200), '3.20 GHz');
    expect(formatFrequency(3200, compact: true), '3.2G');
    expect(formatFrequency(0), '—');
  });

  test('maps metric ids to display values', () {
    expect(DashboardMetric.byId('cpu'), DashboardMetric.cpu);
    expect(DashboardMetric.byId('gpu0'), DashboardMetric.gpu0);
    expect(DashboardMetric.byId('gpu1Memory'), DashboardMetric.gpu1Memory);
    expect(DashboardMetric.byId('gpu'), isNull);
    expect(DashboardMetric.byId('missing'), isNull);
    expect(DashboardMetric.upload.value(snapshot), '125 KB/s');
    expect(DashboardMetric.download.value(snapshot), '1.5 MB/s');
    expect(DashboardMetric.cpu.value(snapshot), '23%');
    expect(DashboardMetric.memory.value(snapshot), '61%');
    expect(DashboardMetric.gpu0.value(snapshot), '42%');
    expect(DashboardMetric.gpu0Memory.value(snapshot), '33%');
    expect(DashboardMetric.gpu1.value(snapshot), '8%');
    expect(DashboardMetric.gpu1Memory.value(snapshot), '20%');
    expect(DashboardMetric.cpuFrequency.value(snapshot), '3.20 GHz');
    expect(DashboardMetric.totalTraffic.value(snapshot), '1 GB');
    expect(DashboardMetric.cpu.value(null), '—');
  });

  test('shows a dash for a missing GPU', () {
    final single = MetricsSnapshot(
      uploadBps: 0,
      downloadBps: 0,
      cpuPercent: 0,
      memoryPercent: 0,
      memoryUsedBytes: 0,
      memoryTotalBytes: 0,
      cpuMhz: 0,
      cpuMaxMhz: 0,
      gpus: const [
        GpuSnapshot(
          id: 'gpu0',
          name: 'Only GPU',
          utilizationPercent: 10,
          memoryUsedBytes: 100,
          memoryTotalBytes: 1000,
          memoryPercent: 10,
        ),
      ],
      totalUploadBytes: 0,
      totalDownloadBytes: 0,
      updatedAtMs: 1,
    );
    expect(DashboardMetric.gpu1.value(single), '—');
    expect(DashboardMetric.gpu1Memory.value(single), '—');
    expect(DashboardMetric.gpu1.detail(single), '未检测到这块显卡');
  });

  test('hides GPU memory when the total is unknown', () {
    const unknown = MetricsSnapshot(
      uploadBps: 0,
      downloadBps: 0,
      cpuPercent: 0,
      memoryPercent: 0,
      memoryUsedBytes: 0,
      memoryTotalBytes: 0,
      cpuMhz: 0,
      cpuMaxMhz: 0,
      gpus: [
        GpuSnapshot(
          id: 'gpu0',
          name: '',
          utilizationPercent: 0,
          memoryUsedBytes: 0,
          memoryTotalBytes: 0,
          memoryPercent: 0,
        ),
      ],
      totalUploadBytes: 0,
      totalDownloadBytes: 0,
      updatedAtMs: 1,
    );
    expect(DashboardMetric.gpu0Memory.value(unknown), '—');
    expect(DashboardMetric.gpu0Memory.compactValue(unknown), '—');
    expect(DashboardMetric.gpu0Memory.detail(unknown), '未检测到显存');
  });
}
