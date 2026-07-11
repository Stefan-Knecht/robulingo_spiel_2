final Map<String, String> _memoryValues = <String, String>{};

class AppKeyValueStore {
  String? getString(String key) => _memoryValues[key];

  int? getInt(String key) => int.tryParse(_memoryValues[key] ?? '');

  Future<void> setString(String key, String value) async {
    _memoryValues[key] = value;
  }

  Future<void> setInt(String key, int value) async {
    _memoryValues[key] = value.toString();
  }

  Future<void> remove(String key) async {
    _memoryValues.remove(key);
  }
}

Future<AppKeyValueStore?> openAppKeyValueStore(
  String owner,
  String operation,
) async =>
    AppKeyValueStore();
