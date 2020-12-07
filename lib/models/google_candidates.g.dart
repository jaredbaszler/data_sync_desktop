// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'google_candidates.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GoogleCandidates _$GoogleCandidatesFromJson(Map<String, dynamic> json) {
  return GoogleCandidates(
    url: json['url'] as String,
    candidates: (json['candidates'] as List)
        ?.map((e) =>
            e == null ? null : Candidates.fromJson(e as Map<String, dynamic>))
        ?.toList(),
    status: json['status'] as String,
  );
}

Map<String, dynamic> _$GoogleCandidatesToJson(GoogleCandidates instance) =>
    <String, dynamic>{
      'url': instance.url,
      'candidates': instance.candidates,
      'status': instance.status,
    };
