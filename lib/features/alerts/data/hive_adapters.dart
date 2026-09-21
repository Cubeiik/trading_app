import 'package:hive_ce/hive_ce.dart';

import '../../quotes/domain/quote.dart';
import '../domain/price_alert.dart';

// Order defines the typeIds: append only, never reorder or remove.
@GenerateAdapters([
  AdapterSpec<PriceAlert>(),
  AdapterSpec<QuoteSide>(),
  AdapterSpec<AlertDirection>(),
  AdapterSpec<AlertKind>(),
  AdapterSpec<AlertStatus>(),
])
part 'hive_adapters.g.dart';
