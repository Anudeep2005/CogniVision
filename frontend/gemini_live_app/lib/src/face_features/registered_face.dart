import 'package:hive/hive.dart';

part 'registered_face.g.dart';

@HiveType(typeId: 0)
class RegisteredFace extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  List<double> embedding; // 128-d face embedding vector

  @HiveField(3)
  DateTime registeredAt;

  RegisteredFace({
    required this.id,
    required this.name,
    required this.embedding,
    required this.registeredAt,
  });
}
