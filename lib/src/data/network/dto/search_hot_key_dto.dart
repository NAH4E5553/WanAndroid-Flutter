import 'package:json_annotation/json_annotation.dart';

part 'search_hot_key_dto.g.dart';

@JsonSerializable(createToJson: false)
class SearchHotKeyDto {
  const SearchHotKeyDto({required this.id, required this.name, this.order = 0});

  factory SearchHotKeyDto.fromJson(Map<String, dynamic> json) =>
      _$SearchHotKeyDtoFromJson(json);

  final int id;
  final String name;
  final int order;
}
