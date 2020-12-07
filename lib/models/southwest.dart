import 'package:json_annotation/json_annotation.dart';

part 'southwest.g.dart';

@JsonSerializable()
class Southwest  {
	@JsonKey(name: 'lat')
	double lat;
	@JsonKey(name: 'lng')
	double lng;

	Southwest({this.lat, this.lng});

	factory Southwest.fromJson(Map<String, dynamic> json) => _$SouthwestFromJson(json);

	Map<String, dynamic> toJson() => _$SouthwestToJson(this);


}
