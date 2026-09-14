int matterLevelToPercent(int level) {
  if (level < 1 || level > 254) {
    throw RangeError.range(level, 1, 254, 'level');
  }
  return (level * 100 / 254).round().clamp(1, 100);
}

int percentToMatterLevel(int percent) {
  if (percent < 1 || percent > 100) {
    throw RangeError.range(percent, 1, 100, 'percent');
  }
  return (percent * 254 / 100).round().clamp(1, 254);
}
