import 'package:json_annotation/json_annotation.dart';
import "geometry.dart";
import "plus_code.dart";

part 'candidates.g.dart';

@JsonSerializable()
class Candidates  {
	@JsonKey(name: 'business_status')
	String businessStatus;
	@JsonKey(name: 'formatted_address')
	String formattedAddress;
	@JsonKey(name: 'geometry')
	Geometry geometry;
	@JsonKey(name: 'icon')
	String icon;
	@JsonKey(name: 'name')
	String name;
	@JsonKey(name: 'place_id')
	String placeId;
	@JsonKey(name: 'plus_code')
	PlusCode plusCode;
	@JsonKey(name: 'types')
	List<String> types;

	Candidates({this.businessStatus, this.formattedAddress, this.geometry, this.icon, this.name, this.placeId, this.plusCode, this.types});

	factory Candidates.fromJson(Map<String, dynamic> json) => _$CandidatesFromJson(json);

	Map<String, dynamic> toJson() => _$CandidatesToJson(this);


}
