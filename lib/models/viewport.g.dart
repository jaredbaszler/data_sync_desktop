// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'viewport.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Viewport _$ViewportFromJson(Map<String, dynamic> json) {
  return Viewport(
    northeast: json['northeast'] == null
        ? null
        : Northeast.fromJson(json['northeast'] as Map<String, dynamic>),
    southwest: json['southwest'] == null
        ? null
        : Southwest.fromJson(json['southwest'] as Map<String, dynamic>),
  );
}

Map<String, dynamic> _$ViewportToJson(Viewport instance) => <String, dynamic>{
      'northeast': instance.northeast,
      'southwest': instance.southwest,
    };
