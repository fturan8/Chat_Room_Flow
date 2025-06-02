import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';
import 'package:just_audio/just_audio.dart';
import 'permission_service.dart';

class AudioService {
  final _audioRecorder = AudioRecorder();
  final _audioPlayer = AudioPlayer();
  final _permissionService = PermissionService();
  
  bool _isRecording = false;
  String? _currentRecordingPath;
  
  // Platform kanalı
  static const platform = MethodChannel('com.example.chat_flow_new/permissions');
  
  // Kayıt durumunu kontrol et
  bool get isRecording => _isRecording;
  
  // Geçerli kayıt yolunu al
  String? get currentRecordingPath => _currentRecordingPath;
  
  // Player durumunu al
  Stream<PlayerState> get playerStateStream => _audioPlayer.playerStateStream;
  
  // Player'a direkt erişim
  AudioPlayer get player => _audioPlayer;

  // Ses kaydını başlat
  Future<bool> startRecording() async {
    try {
      print('AudioService: Ses kaydı başlatılıyor');
      
      // Platform bazlı mikrofon izni kontrolü
      final hasPermission = await _permissionService.checkMicrophonePermission();
      print('AudioService: Mikrofon izni kontrolü: $hasPermission');
      
      if (!hasPermission) {
        // İzin yoksa iste
        final result = await _permissionService.requestMicrophonePermission();
        print('AudioService: Mikrofon izni isteme sonucu: $result');
        
        if (!result) {
          print('AudioService: Mikrofon izni verilmedi');
          return false;
        }
      }

      // Kayıt yapılacak dizini al
      final directory = await getTemporaryDirectory();
      print('AudioService: Geçici dizin: ${directory.path}');
      
      // Kayıt yolu oluştur
      final uuid = const Uuid().v4();
      _currentRecordingPath = '${directory.path}/audio_$uuid.m4a';
      print('AudioService: Kayıt yolu: $_currentRecordingPath');
      
      // iOS için ses oturumu ayarla
      if (Platform.isIOS) {
        try {
          await _audioRecorder.hasPermission();
          print('AudioService: iOS ses oturumu hazır');
        } catch (e) {
          print('AudioService: iOS ses oturumu hatası: $e');
          return false;
        }
      }
      
      // Kaydı başlat
      await _audioRecorder.start(
        RecordConfig(
          encoder: Platform.isIOS ? AudioEncoder.aacLc : AudioEncoder.aacLc,
          bitRate: Platform.isIOS ? 64000 : 128000,  // iOS için daha düşük bit rate
          sampleRate: Platform.isIOS ? 22050 : 44100,  // iOS için daha düşük sample rate
          numChannels: 1,  // Mono kayıt
        ),
        path: _currentRecordingPath!,
      );
      
      _isRecording = true;
      print('AudioService: Ses kaydı başlatıldı: $_currentRecordingPath');
      return true;
    } catch (e) {
      print('AudioService: Ses kaydı başlatılırken hata: $e');
      _isRecording = false;
      return false;
    }
  }

  // Ses kaydını durdur
  Future<String?> stopRecording() async {
    try {
      if (!_isRecording) {
        print('Kayıt zaten durdurulmuş');
        return null;
      }
      
      // Kaydı durdur
      final path = await _audioRecorder.stop();
      _isRecording = false;
      
      print('Ses kaydı durduruldu: $path');
      return path;
    } catch (e) {
      print('Ses kaydı durdurulurken hata: $e');
      _isRecording = false;
      return null;
    }
  }

  // Ses kaydını iptal et
  Future<void> cancelRecording() async {
    try {
      if (_isRecording) {
        await _audioRecorder.stop();
        _isRecording = false;
        
        // Kaydedilen dosyayı sil
        if (_currentRecordingPath != null) {
          final file = File(_currentRecordingPath!);
          if (await file.exists()) {
            await file.delete();
            print('İptal edilen kayıt silindi: $_currentRecordingPath');
          }
        }
      }
      _currentRecordingPath = null;
    } catch (e) {
      print('Ses kaydı iptal edilirken hata: $e');
    }
  }
  
  // Ses dosyasını çal
  Future<void> playAudio(String url) async {
    try {
      print('Ses oynatma başlatılıyor: $url');
      
      // Mevcut sesler durdurulsun
      await _audioPlayer.stop();
      
      // Ses dosyası yükle ve oynat
      if (url.startsWith('http')) {
        // Uzak URL
        await _audioPlayer.setUrl(url);
      } else {
        // Yerel dosya
        await _audioPlayer.setFilePath(url);
      }
      
      await _audioPlayer.play();
      print('Ses oynatılıyor');
    } catch (e) {
      print('Ses oynatma hatası: $e');
    }
  }
  
  // Ses oynatmayı durdur
  Future<void> stopAudio() async {
    try {
      await _audioPlayer.stop();
      print('Ses oynatma durduruldu');
    } catch (e) {
      print('Ses durdurma hatası: $e');
    }
  }

  // Servis kapanırken kayıt cihazını kapat
  Future<void> dispose() async {
    await cancelRecording();
    await _audioPlayer.dispose();
  }
} 