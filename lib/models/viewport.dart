import 'package:json_annotation/json_annotation.dart';
import "northeast.dart";
import "southwest.dart";

part 'viewport.g.dart';

@JsonSerializable()
class Viewport  {
	@JsonKey(name: 'northeast')
	Northeast northeast;
	@JsonKey(name: 'southwest')
	Southwest southwest;

	Viewport({this.northeast, this.southwest});

	factory Viewport.fromJson(Map<String, dynamic> json) => _$ViewportFromJson(json);

	Map<String, dynamic> toJson() => _$ViewportToJson(this);


}
