class LogStorage {
  Future<void> init() async {
    throw UnsupportedError('LogStorage is not supported on this platform.');
  }

  Future<void> appendLine(String line) async {
    throw UnsupportedError('LogStorage is not supported on this platform.');
  }

  Future<List<String>> readLines() async {
    throw UnsupportedError('LogStorage is not supported on this platform.');
  }

  Future<bool> exists() async {
    throw UnsupportedError('LogStorage is not supported on this platform.');
  }

  Future<void> clear() async {
    throw UnsupportedError('LogStorage is not supported on this platform.');
  }
}
