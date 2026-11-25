/// Backoff for scan/stamp status polls: 2 quick pings → 5s → size-aware ramp.

enum JobPollKind { scan, stamp }

int expectedJobMs(JobPollKind kind, [num? sizeBytes]) {
  final mb = ((sizeBytes ?? 0).toDouble()).clamp(0, double.infinity) / (1024 * 1024);
  final downloadMs = mb > 0 ? (mb * 900).ceil() : 8000;
  final processMs = kind == JobPollKind.stamp
      ? (12000 + mb * 2500).ceil()
      : (4000 + mb * 400).ceil();
  final floor = kind == JobPollKind.stamp ? 25000 : 12000;
  final ceiling = kind == JobPollKind.stamp ? 300000 : 220000;
  final total = downloadMs + processMs;
  if (total < floor) return floor;
  if (total > ceiling) return ceiling;
  return total;
}

/// Delay before poll attempt [index] (0-based).
int jobPollDelayMs(int index, JobPollKind kind, [num? sizeBytes]) {
  if (index <= 0) return 800;
  if (index == 1) return 1200;
  if (index == 2) return 5000;

  final mb = ((sizeBytes ?? 0).toDouble()).clamp(0, double.infinity) / (1024 * 1024);
  final large = mb >= 20 || (sizeBytes == null && kind == JobPollKind.stamp);
  final medium = mb >= 8;
  final start = large ? 4000 : medium ? 3000 : 2000;
  final step = large ? 3000 : medium ? 2000 : 1500;
  final cap = large ? 20000 : medium ? 12000 : 8000;
  final delay = start + (index - 3) * step;
  return delay > cap ? cap : delay;
}

int jobPollMaxAttempts(JobPollKind kind, [num? sizeBytes]) {
  final budget = expectedJobMs(kind, sizeBytes) + 60000;
  var elapsed = 0;
  var n = 0;
  while (elapsed < budget && n < 80) {
    elapsed += jobPollDelayMs(n, kind, sizeBytes);
    n += 1;
  }
  return n < 8 ? 8 : n;
}
