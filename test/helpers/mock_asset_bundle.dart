import 'package:flutter/services.dart';
import 'package:mocktail/mocktail.dart';

class MockAssetBundle extends Mock implements AssetBundle {}

MockAssetBundle assetBundleWith(String contents) {
  final bundle = MockAssetBundle();
  when(() => bundle.loadString(any())).thenAnswer((_) async => contents);
  return bundle;
}
