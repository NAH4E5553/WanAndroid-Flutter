// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'search_hot_key_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SearchHotKeyDto _$SearchHotKeyDtoFromJson(Map<String, dynamic> json) =>
    SearchHotKeyDto(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      order: (json['order'] as num?)?.toInt() ?? 0,
    );
