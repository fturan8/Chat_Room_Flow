import 'package:flutter/foundation.dart';

class ChatRoomModel {
  final String id;
  final String title;
  final String createdBy;
  final DateTime createdAt;

  ChatRoomModel({
    required this.id,
    required this.title,
    required this.createdBy,
    required this.createdAt,
  });

  factory ChatRoomModel.fromJson(Map<String, dynamic> json) {
    return ChatRoomModel(
      id: json['id'] as String,
      title: json['title'] as String,
      createdBy: json['created_by'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
    };
  }

  @override
  String toString() => 'ChatRoomModel(id: $id, title: $title)';
} 