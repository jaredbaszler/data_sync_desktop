import 'package:json_annotation/json_annotation.dart';

part 'northeast.g.dart';

@JsonSerializable()
class Northeast  {
	@JsonKey(name: 'lat')
	double lat;
	@JsonKey(name: 'lng')
	double lng;

	Northeast({this.lat, this.lng});

	factory Northeast.fromJson(Map<String, dynamic> json) => _$NortheastFromJson(json);

	Map<String, dynamic> toJson() => _$NortheastToJson(this);


}
