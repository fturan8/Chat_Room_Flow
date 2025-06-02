import 'package:flutter/foundation.dart';

// Mesaj içerik tipi
enum MessageContentType {
  text,
  image,
  audio
}

class MessageModel {
  final String id;
  final String roomId;
  final String senderId;
  final String senderName;
  final String content;
  final String contentType;
  final String? mediaUrl;
  final DateTime timestamp;

  MessageModel({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.senderName,
    required this.content,
    this.contentType = 'text',
    this.mediaUrl,
    required this.timestamp,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      id: json['id'],
      roomId: json['room_id'],
      senderId: json['sender_id'],
      senderName: json['sender_name'] ?? 'Unknown',
      content: json['content'],
      contentType: json['content_type'] ?? 'text',
      mediaUrl: json['media_url'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'room_id': roomId,
      'sender_id': senderId,
      'sender_name': senderName,
      'content': content,
      'content_type': contentType,
      'media_url': mediaUrl,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  // String'den enum'a dönüştürme
  static MessageContentType _parseContentType(String? type) {
    if (type == null) return MessageContentType.text;
    
    switch (type) {
      case 'image':
        return MessageContentType.image;
      case 'audio':
        return MessageContentType.audio;
      case 'text':
      default:
        return MessageContentType.text;
    }
  }
  
  // Enum'dan string'e dönüştürme
  static String _contentTypeToString(MessageContentType type) {
    switch (type) {
      case MessageContentType.image:
        return 'image';
      case MessageContentType.audio:
        return 'audio';
      case MessageContentType.text:
      default:
        return 'text';
    }
  }

  @override
  String toString() => 'MessageModel(id: $id, content: $content, type: $contentType)';
} 