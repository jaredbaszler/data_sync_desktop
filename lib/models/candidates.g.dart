// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'candidates.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Candidates _$CandidatesFromJson(Map<String, dynamic> json) {
  return Candidates(
    businessStatus: json['business_status'] as String,
    formattedAddress: json['formatted_address'] as String,
    geometry: json['geometry'] == null
        ? null
        : Geometry.fromJson(json['geometry'] as Map<String, dynamic>),
    icon: json['icon'] as String,
    name: json['name'] as String,
    placeId: json['place_id'] as String,
    plusCode: json['plus_code'] == null
        ? null
        : PlusCode.fromJson(json['plus_code'] as Map<String, dynamic>),
    types: (json['types'] as List)?.map((e) => e as String)?.toList(),
  );
}

Map<String, dynamic> _$CandidatesToJson(Candidates instance) =>
    <String, dynamic>{
      'business_status': instance.businessStatus,
      'formatted_address': instance.formattedAddress,
      'geometry': instance.geometry,
      'icon': instance.icon,
      'name': instance.name,
      'place_id': instance.placeId,
      'plus_code': instance.plusCode,
      'types': instance.types,
    };
