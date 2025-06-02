import 'dart:io';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  // Singleton
  static final PermissionService _instance = PermissionService._internal();
  factory PermissionService() => _instance;
  PermissionService._internal();
  
  // iOS için özel method channel
  static const MethodChannel _iOSMicrophoneChannel = MethodChannel('com.example.chat_flow_new/microphone');
  
  // Mikrofon izni iste - platform bazlı
  Future<bool> requestMicrophonePermission() async {
    try {
      print('PermissionService: Mikrofon izni isteniyor...');
      
      if (Platform.isIOS) {
        // iOS için native method channel kullan
        print('PermissionService: iOS için native mikrofon izni isteniyor...');
        final bool? result = await _iOSMicrophoneChannel.invokeMethod('requestMicrophonePermission');
        print('PermissionService: iOS mikrofon izni sonucu: $result');
        return result ?? false;
      } else {
        // Android için permission_handler kullan
        print('PermissionService: Android için permission_handler mikrofon izni isteniyor...');
        final result = await Permission.microphone.request();
        print('PermissionService: Android mikrofon izni sonucu: $result');
        return result.isGranted;
      }
    } catch (e) {
      print('PermissionService: Mikrofon izni hatası: $e');
      return false;
    }
  }
  
  // Mikrofon izni durumunu kontrol et
  Future<bool> checkMicrophonePermission() async {
    try {
      if (Platform.isIOS) {
        // iOS için native kontrol
        final bool? result = await _iOSMicrophoneChannel.invokeMethod('checkMicrophonePermission');
        return result ?? false;
      } else {
        // Android için permission_handler kontrol
        final status = await Permission.microphone.status;
        return status.isGranted;
      }
    } catch (e) {
      print('PermissionService: Mikrofon izni kontrol hatası: $e');
      return false;
    }
  }
  
  // Kayıt için gerekli tüm izinleri iste
  Future<bool> requestAllRequiredPermissions() async {
    try {
      // Önce mikrofon izni - olmadan devam edemeyiz
      final hasMicPermission = await requestMicrophonePermission();
      if (!hasMicPermission) {
        return false;
      }
      
      // Platform bazlı diğer izinler
      if (Platform.isAndroid) {
        await _requestAndroidStoragePermission();
      } else if (Platform.isIOS) {
        await _requestIOSMediaPermission();
      }
      
      return true;
    } catch (e) {
      print('İzin isteme hatası: $e');
      return false;
    }
  }
  
  // Android için depolama izni
  Future<void> _requestAndroidStoragePermission() async {
    try {
      if (Platform.isAndroid) {
        // Android sürümüne göre farklı izinler
        if (_isAndroid13OrHigher()) {
          await Permission.audio.request();
        } else {
          await Permission.storage.request();
        }
      }
    } catch (e) {
      print('Android depolama izni hatası: $e');
    }
  }
  
  // iOS için medya kitaplığı izni
  Future<void> _requestIOSMediaPermission() async {
    try {
      if (Platform.isIOS) {
        await Permission.mediaLibrary.request();
      }
    } catch (e) {
      print('iOS medya izni hatası: $e');
    }
  }
  
  // Android 13 veya üstü mü kontrol et
  bool _isAndroid13OrHigher() {
    if (!Platform.isAndroid) return false;
    
    try {
      final versionStr = Platform.operatingSystemVersion;
      final mainVersion = int.tryParse(versionStr.split('.').first) ?? 0;
      return mainVersion >= 13;
    } catch (e) {
      return false;
    }
  }
} 