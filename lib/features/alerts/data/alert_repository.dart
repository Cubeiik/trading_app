import 'package:hive_ce/hive_ce.dart';

import '../../../core/errors.dart';
import '../domain/price_alert.dart';

const _boxName = 'alerts';

Future<Box<PriceAlert>> openAlertsBox() async {
  try {
    return await Hive.openBox<PriceAlert>(_boxName);
  } catch (error, stackTrace) {
    logError(error, stackTrace, 'openAlertsBox');
  }

  await Hive.deleteBoxFromDisk(_boxName);
  return Hive.openBox<PriceAlert>(_boxName);
}

class AlertRepository {
  AlertRepository(this._box);

  final Box<PriceAlert> _box;

  List<PriceAlert> loadAll() => _box.values.toList(growable: false);

  Future<void> save(PriceAlert alert) async {
    try {
      await _box.put(alert.id, alert);
    } catch (error, stackTrace) {
      logError(error, stackTrace, 'AlertRepository.save');
      throw AppException('Could not save the alert.', cause: error);
    }
  }

  Future<void> delete(String id) async {
    try {
      await _box.delete(id);
    } catch (error, stackTrace) {
      logError(error, stackTrace, 'AlertRepository.delete');
      throw AppException('Could not delete the alert.', cause: error);
    }
  }
}
