// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hive_adapters.dart';

// **************************************************************************
// AdaptersGenerator
// **************************************************************************

class PriceAlertAdapter extends TypeAdapter<PriceAlert> {
  @override
  final typeId = 0;

  @override
  PriceAlert read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PriceAlert(
      id: fields[0] as String,
      symbol: fields[1] as String,
      side: fields[2] as QuoteSide,
      direction: fields[3] as AlertDirection,
      kind: fields[4] as AlertKind,
      targetPrice: (fields[5] as num).toDouble(),
      createdAt: fields[6] as DateTime,
      percentage: (fields[7] as num?)?.toDouble(),
      referencePrice: (fields[8] as num?)?.toDouble(),
      status: fields[9] == null ? AlertStatus.active : fields[9] as AlertStatus,
      triggeredAt: fields[10] as DateTime?,
      triggeredPrice: (fields[11] as num?)?.toDouble(),
    );
  }

  @override
  void write(BinaryWriter writer, PriceAlert obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.symbol)
      ..writeByte(2)
      ..write(obj.side)
      ..writeByte(3)
      ..write(obj.direction)
      ..writeByte(4)
      ..write(obj.kind)
      ..writeByte(5)
      ..write(obj.targetPrice)
      ..writeByte(6)
      ..write(obj.createdAt)
      ..writeByte(7)
      ..write(obj.percentage)
      ..writeByte(8)
      ..write(obj.referencePrice)
      ..writeByte(9)
      ..write(obj.status)
      ..writeByte(10)
      ..write(obj.triggeredAt)
      ..writeByte(11)
      ..write(obj.triggeredPrice);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PriceAlertAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class QuoteSideAdapter extends TypeAdapter<QuoteSide> {
  @override
  final typeId = 1;

  @override
  QuoteSide read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return QuoteSide.bid;
      case 1:
        return QuoteSide.ask;
      default:
        return QuoteSide.bid;
    }
  }

  @override
  void write(BinaryWriter writer, QuoteSide obj) {
    switch (obj) {
      case QuoteSide.bid:
        writer.writeByte(0);
      case QuoteSide.ask:
        writer.writeByte(1);
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuoteSideAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class AlertDirectionAdapter extends TypeAdapter<AlertDirection> {
  @override
  final typeId = 2;

  @override
  AlertDirection read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return AlertDirection.above;
      case 1:
        return AlertDirection.below;
      default:
        return AlertDirection.above;
    }
  }

  @override
  void write(BinaryWriter writer, AlertDirection obj) {
    switch (obj) {
      case AlertDirection.above:
        writer.writeByte(0);
      case AlertDirection.below:
        writer.writeByte(1);
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AlertDirectionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class AlertKindAdapter extends TypeAdapter<AlertKind> {
  @override
  final typeId = 3;

  @override
  AlertKind read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return AlertKind.absolute;
      case 1:
        return AlertKind.percentage;
      default:
        return AlertKind.absolute;
    }
  }

  @override
  void write(BinaryWriter writer, AlertKind obj) {
    switch (obj) {
      case AlertKind.absolute:
        writer.writeByte(0);
      case AlertKind.percentage:
        writer.writeByte(1);
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AlertKindAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class AlertStatusAdapter extends TypeAdapter<AlertStatus> {
  @override
  final typeId = 4;

  @override
  AlertStatus read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return AlertStatus.active;
      case 1:
        return AlertStatus.triggered;
      default:
        return AlertStatus.active;
    }
  }

  @override
  void write(BinaryWriter writer, AlertStatus obj) {
    switch (obj) {
      case AlertStatus.active:
        writer.writeByte(0);
      case AlertStatus.triggered:
        writer.writeByte(1);
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AlertStatusAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
