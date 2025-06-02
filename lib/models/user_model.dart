import 'package:flutter/foundation.dart';

class UserModel {
  final String id;
  final String name;
  final DateTime createdAt;

  UserModel({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'created_at': createdAt.toIso8601String(),
    };
  }

  @override
  String toString() => 'UserModel(id: $id, name: $name)';
} 