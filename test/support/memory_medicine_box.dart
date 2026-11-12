import 'package:hive_ce/hive.dart';
import 'package:yakmukja/models/medicine.dart';

/// 약 상자 흉내. [throwOnAddAll] 이 있으면 다음 [addAll] 한 번만 실패한다.
class MemoryMedicineBox extends Box<Medicine> {
  MemoryMedicineBox([Iterable<Medicine> seed = const []]) {
    _items.addAll(seed);
  }

  final _items = <Medicine>[];

  /// 다음 [addAll] 이 던질 오류. 한 번 던진 뒤 비운다.
  Object? throwOnAddAll;

  @override
  String get name => 'medicines';

  @override
  bool get isOpen => true;

  @override
  String? get path => null;

  @override
  bool get lazy => false;

  @override
  Iterable<dynamic> get keys => [for (var i = 0; i < _items.length; i++) i];

  @override
  int get length => _items.length;

  @override
  bool get isEmpty => _items.isEmpty;

  @override
  bool get isNotEmpty => _items.isNotEmpty;

  @override
  dynamic keyAt(int index) => index;

  @override
  Stream<BoxEvent> watch({dynamic key}) => const Stream.empty();

  @override
  bool containsKey(dynamic key) =>
      key is int && key >= 0 && key < _items.length;

  @override
  Future<void> put(dynamic key, Medicine value) async {
    _items[key as int] = value;
  }

  @override
  Future<void> putAt(int index, Medicine value) async {
    _items[index] = value;
  }

  @override
  Future<void> putAll(Map<dynamic, Medicine> entries) async {
    entries.forEach((key, value) {
      _items[key as int] = value;
    });
  }

  @override
  Future<int> add(Medicine value) async {
    _items.add(value);
    return _items.length - 1;
  }

  @override
  Future<Iterable<int>> addAll(Iterable<Medicine> values) async {
    final error = throwOnAddAll;
    if (error != null) {
      throwOnAddAll = null;
      throw error;
    }
    final ids = <int>[];
    for (final value in values) {
      ids.add(_items.length);
      _items.add(value);
    }
    return ids;
  }

  @override
  Future<void> delete(dynamic key) async {
    if (containsKey(key)) _items.removeAt(key as int);
  }

  @override
  Future<void> deleteAt(int index) async {
    _items.removeAt(index);
  }

  @override
  Future<void> deleteAll(Iterable<dynamic> keys) async {
    final sorted = [for (final key in keys) key as int]
      ..sort((a, b) => b.compareTo(a));
    for (final key in sorted) {
      if (containsKey(key)) _items.removeAt(key);
    }
  }

  @override
  Future<void> compact() async {}

  @override
  Future<int> clear() async {
    final count = _items.length;
    _items.clear();
    return count;
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> deleteFromDisk() async {
    _items.clear();
  }

  @override
  Future<void> flush() async {}

  @override
  Iterable<Medicine> get values => List<Medicine>.unmodifiable(_items);

  @override
  Iterable<Medicine> valuesBetween({dynamic startKey, dynamic endKey}) =>
      values;

  @override
  Medicine? get(dynamic key, {Medicine? defaultValue}) {
    if (!containsKey(key)) return defaultValue;
    return _items[key as int];
  }

  @override
  Medicine? getAt(int index) => _items[index];

  @override
  Map<dynamic, Medicine> toMap() => {
    for (var i = 0; i < _items.length; i++) i: _items[i],
  };
}
