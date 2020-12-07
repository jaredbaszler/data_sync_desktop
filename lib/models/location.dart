import 'package:json_annotation/json_annotation.dart';

part 'location.g.dart';

@JsonSerializable()
class Location  {
	@JsonKey(name: 'lat')
	double lat;
	@JsonKey(name: 'lng')
	double lng;

	Location({this.lat, this.lng});

	factory Location.fromJson(Map<String, dynamic> json) => _$LocationFromJson(json);

	Map<String, dynamic> toJson() => _$LocationToJson(this);


}
