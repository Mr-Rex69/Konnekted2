enum ProgressBarStyle { waveform, line, wavy }

extension ProgressBarStyleX on ProgressBarStyle {
  String get storageValue {
    switch (this) {
      case ProgressBarStyle.waveform:
        return 'waveform';
      case ProgressBarStyle.wavy:
        return 'wavy';
      case ProgressBarStyle.line:
        return 'line';
    }
  }

  static ProgressBarStyle fromStorageValue(String? value) {
    switch (value) {
      case 'wavy':
        return ProgressBarStyle.wavy;
      case 'line':
        return ProgressBarStyle.line;
      case 'waveform':
        return ProgressBarStyle.waveform;
      default:
        return ProgressBarStyle.line;
    }
  }
}
