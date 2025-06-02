import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../services/audio_service.dart';
import '../services/permission_service.dart';
import 'package:just_audio/just_audio.dart';
import '../screens/home/chat_room_screen.dart';
import 'package:permission_handler/permission_handler.dart';

class AudioRecordingSheet extends ConsumerStatefulWidget {
  final Function(File audioFile) onSend;

  const AudioRecordingSheet({
    Key? key,
    required this.onSend,
  }) : super(key: key);

  @override
  ConsumerState<AudioRecordingSheet> createState() => _AudioRecordingSheetState();
}

class _AudioRecordingSheetState extends ConsumerState<AudioRecordingSheet> {
  bool _isRecording = false;
  bool _hasRecording = false;
  String? _recordingPath;
  int _recordingDuration = 0;
  Timer? _durationTimer;
  bool _permissionDenied = false;
  bool _isCheckingPermissions = false;
  
  late final AudioService _audioService;
  final _permissionService = PermissionService();
  
  @override
  void initState() {
    super.initState();
    _audioService = ref.read(audioServiceProvider);
    
    // Ses kaydedici durumunu dinle
    _isRecording = _audioService.isRecording;
    
    // İzinleri başlangıçta kontrol et
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPermissions();
    });
  }
  
  @override
  void dispose() {
    _durationTimer?.cancel();
    super.dispose();
  }

  // İzinleri kontrol et
  Future<void> _checkPermissions() async {
    setState(() {
      _isCheckingPermissions = true;
    });
    
    try {
      print('İzin kontrolü başlatılıyor...');
      
      // Platform bazlı izin kontrolü
      final hasPermission = await _permissionService.checkMicrophonePermission();
      print('Mevcut mikrofon izni durumu: $hasPermission');
      
      // İzin yoksa iste
      if (!hasPermission) {
        print('Mikrofon izni yok, isteniyor...');
        final result = await _permissionService.requestMicrophonePermission();
        print('Mikrofon izni istek sonucu: $result');
        
        setState(() {
          _permissionDenied = !result;
        });
      } else {
        // Zaten izin var
        setState(() {
          _permissionDenied = false;
        });
      }
    } catch (e) {
      print('İzin kontrolü hatası: $e');
      setState(() {
        _permissionDenied = true;
      });
    } finally {
      setState(() {
        _isCheckingPermissions = false;
      });
    }
  }
  
  // Kaydı başlat
  Future<void> _startRecording() async {
    try {
      print('Ses kaydı başlatma denemesi');
      
      // Platform bazlı izin kontrolü
      final hasPermission = await _permissionService.checkMicrophonePermission();
      print('Mikrofon izin durumu: $hasPermission');
      
      if (!hasPermission) {
        // Eğer izin verilmediyse, izin iste
        final result = await _permissionService.requestMicrophonePermission();
        
        if (!result) {
          // İzin alınamadıysa kullanıcıya bildir
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Ses kaydı için mikrofon izni gereklidir.'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 3),
                action: SnackBarAction(
                  label: 'Ayarlar',
                  onPressed: () => openAppSettings(),
                ),
              ),
            );
          }
          return;
        }
      }
      
      // İzin varsa kayıt başlat
      final success = await _audioService.startRecording();
      
      if (!success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ses kaydı başlatılamadı. Lütfen tekrar deneyin.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }
      
      setState(() {
        _isRecording = true;
        _recordingDuration = 0;
        _permissionDenied = false;
      });
      
      // Kayıt süresini takip et
      _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          _recordingDuration++;
        });
      });
    } catch (e) {
      print('Kayıt başlatma hatası: $e');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ses kaydı hatası: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
  
  // Kaydı durdur
  Future<void> _stopRecording() async {
    _durationTimer?.cancel();
    
    final path = await _audioService.stopRecording();
    if (path != null) {
      setState(() {
        _isRecording = false;
        _hasRecording = true;
        _recordingPath = path;
      });
    } else {
      setState(() {
        _isRecording = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ses kaydı durdurulamadı'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  // Kaydı iptal et
  Future<void> _cancelRecording() async {
    _durationTimer?.cancel();
    await _audioService.cancelRecording();
    
    if (mounted) {
      setState(() {
        _isRecording = false;
        _hasRecording = false;
        _recordingPath = null;
      });
    }
  }
  
  // Kayıt dinle
  Future<void> _playRecording() async {
    if (_recordingPath != null) {
      await _audioService.playAudio(_recordingPath!);
    }
  }
  
  // Kayıt durdur
  Future<void> _stopPlaying() async {
    await _audioService.stopAudio();
  }
  
  // Kaydı gönder
  Future<void> _sendRecording() async {
    if (_recordingPath != null) {
      final file = File(_recordingPath!);
      if (await file.exists()) {
        Navigator.pop(context);
        widget.onSend(file);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ses dosyası bulunamadı'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
  
  // Süreyi formatlı göster
  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    // Player durumunu dinle
    final playerStateStream = _audioService.playerStateStream;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 5,
          ),
        ],
      ),
      child: _isCheckingPermissions 
        ? const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('İzinler kontrol ediliyor...'),
              ],
            ),
          )
        : Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Başlık
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                _isRecording ? 'Kayıt Yapılıyor...' : 
                  _hasRecording ? 'Kaydı Gözden Geçir' : 'Ses Kaydı',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            
            // İzin uyarısı
            if (_permissionDenied)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.mic_off, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Mikrofon izni olmadan ses kaydı yapılamaz.',
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () async {
                                  // İzinleri tekrar iste
                                  final granted = await _permissionService.requestMicrophonePermission();
                                  setState(() {
                                    _permissionDenied = !granted;
                                  });
                                },
                                style: TextButton.styleFrom(
                                  backgroundColor: Colors.red.shade50,
                                ),
                                child: Text(
                                  'İzin İste',
                                  style: TextStyle(color: Colors.red.shade700),
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: () => openAppSettings(),
                                style: TextButton.styleFrom(
                                  backgroundColor: Colors.red.shade50,
                                ),
                                child: Text(
                                  'Ayarlara Git',
                                  style: TextStyle(color: Colors.red.shade700),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            
            // Kayıt süresi / Dalga gösterimi
            Container(
              height: 100,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: _isRecording ? 
                // Kayıt ekranı
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.mic, color: Colors.red, size: 32),
                    const SizedBox(width: 16),
                    Text(
                      _formatDuration(_recordingDuration),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ) : 
                _hasRecording ?
                  // Kayıt yapıldı
                  StreamBuilder<PlayerState>(
                    stream: playerStateStream,
                    builder: (context, snapshot) {
                      final playerState = snapshot.data;
                      final playing = playerState?.playing ?? false;
                      
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Oynat/Durdur butonu
                          IconButton(
                            icon: Icon(
                              playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
                              size: 40,
                            ),
                            onPressed: playing ? _stopPlaying : _playRecording,
                          ),
                          const SizedBox(width: 16),
                          Text(
                            _formatDuration(_recordingDuration),
                            style: const TextStyle(
                              fontSize: 18,
                            ),
                          ),
                        ],
                      );
                    }
                  ) :
                  // Henüz kayıt yapılmadı
                  const Text(
                    'Kaydetmeye başlamak için aşağıdaki butona basın',
                    textAlign: TextAlign.center,
                  ),
            ),
            
            const SizedBox(height: 20),
            
            // Kontrol butonları
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                if (_isRecording) ...[
                  // Kayıt durduruluyor
                  IconButton(
                    onPressed: _cancelRecording,
                    icon: const Icon(Icons.delete_outline),
                    color: Colors.red,
                    tooltip: 'Kaydı İptal Et',
                  ),
                  FloatingActionButton(
                    onPressed: _stopRecording,
                    backgroundColor: Colors.red,
                    child: const Icon(Icons.stop),
                  ),
                  const SizedBox(width: 48), // Placeholder
                ] else if (_hasRecording) ...[
                  // Kayıt yapıldı, gönderme seçenekleri
                  IconButton(
                    onPressed: _cancelRecording,
                    icon: const Icon(Icons.delete_outline),
                    color: Colors.red,
                    tooltip: 'Kaydı Sil',
                  ),
                  FloatingActionButton(
                    onPressed: _startRecording,
                    child: const Icon(Icons.mic),
                  ),
                  FloatingActionButton(
                    onPressed: _sendRecording,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: const Icon(Icons.send),
                  ),
                ] else ...[
                  // Kayıt başlatma
                  const SizedBox(width: 48), // Placeholder
                  FloatingActionButton(
                    onPressed: () async {
                      // Platform bazlı izin iste
                      await _permissionService.requestMicrophonePermission();
                      // Kaydı başlat
                      _startRecording();
                    },
                    backgroundColor: _permissionDenied 
                        ? Colors.grey 
                        : Theme.of(context).colorScheme.primary,
                    child: const Icon(Icons.mic),
                  ),
                  const SizedBox(width: 48), // Placeholder
                ],
              ],
            ),
          ],
        ),
    );
  }
} 