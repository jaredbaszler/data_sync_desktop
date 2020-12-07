import 'package:json_annotation/json_annotation.dart';
import "candidates.dart";

part 'google_candidates.g.dart';

@JsonSerializable()
class GoogleCandidates  {
	@JsonKey(name: 'url')
	String url;
	@JsonKey(name: 'candidates')
	List<Candidates> candidates;
	@JsonKey(name: 'status')
	String status;

	GoogleCandidates({this.url, this.candidates, this.status});

	factory GoogleCandidates.fromJson(Map<String, dynamic> json) => _$GoogleCandidatesFromJson(json);

	Map<String, dynamic> toJson() => _$GoogleCandidatesToJson(this);


}
