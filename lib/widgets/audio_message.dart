import 'dart:math';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../screens/home/chat_room_screen.dart';

// Aktif olarak çalan ses dosyasını takip etmek için provider
final activeAudioProvider = StateProvider<String?>((ref) => null);

class AudioMessage extends ConsumerStatefulWidget {
  final String audioUrl;
  final bool isMyMessage;
  final Duration? duration;

  const AudioMessage({
    Key? key,
    required this.audioUrl,
    required this.isMyMessage,
    this.duration,
  }) : super(key: key);

  @override
  ConsumerState<AudioMessage> createState() => _AudioMessageState();
}

class _AudioMessageState extends ConsumerState<AudioMessage> {
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _isInitialized = false;
  bool _isDragging = false;
  final List<double> _waveformHeights = List.generate(40, (index) => 0.0);
  late final AudioPlayer _player;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _generateWaveform();
    _setupAudioPlayer();
    _initializeAudio();
  }

  void _generateWaveform() {
    final random = Random(widget.audioUrl.hashCode);
    for (int i = 0; i < _waveformHeights.length; i++) {
      _waveformHeights[i] = random.nextDouble() * 15 + 5;
    }
  }

  Future<void> _initializeAudio() async {
    try {
      await _player.setUrl(widget.audioUrl);
      final duration = await _player.duration;
      if (mounted && duration != null) {
        setState(() {
          _duration = duration;
          _isInitialized = true;
        });
      }
    } catch (e) {
      print('Ses dosyası yüklenirken hata: $e');
    }
  }

  void _setupAudioPlayer() {
    // Player durumu değiştiğinde
    _player.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
          
          // Ses bittiğinde
          if (state.processingState == ProcessingState.completed) {
            _isPlaying = false;
            _position = Duration.zero;
            ref.read(activeAudioProvider.notifier).state = null;
          }
        });
      }
    });

    // Pozisyon değiştiğinde
    _player.positionStream.listen((position) {
      if (mounted && !_isDragging) {
        setState(() {
          _position = position;
        });
      }
    });
  }

  Future<void> _playPause() async {
    final currentlyPlaying = ref.read(activeAudioProvider);

    if (_isPlaying) {
      await _player.pause();
      ref.read(activeAudioProvider.notifier).state = null;
    } else {
      // Başka bir ses çalıyorsa durdur
      if (currentlyPlaying != null && currentlyPlaying != widget.audioUrl) {
        ref.read(audioServiceProvider).stopAudio();
      }

      // Eğer ses sona ulaştıysa başa sar
      if (_position >= _duration) {
        await _player.seek(Duration.zero);
        setState(() {
          _position = Duration.zero;
        });
      }

      await _player.play();
      ref.read(activeAudioProvider.notifier).state = widget.audioUrl;
    }
  }

  Future<void> _seekTo(double progress) async {
    if (!_isInitialized) return;
    
    final newPosition = Duration(
      milliseconds: (progress * _duration.inMilliseconds).round(),
    );
    
    await _player.seek(newPosition);
    setState(() {
      _position = newPosition;
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Widget _buildWaveform(Color activeColor, Color inactiveColor) {
    return GestureDetector(
      onHorizontalDragStart: (details) {
        _isDragging = true;
      },
      onHorizontalDragUpdate: (details) {
        if (!_isInitialized) return;
        final RenderBox box = context.findRenderObject() as RenderBox;
        final double width = box.size.width;
        final double dx = details.localPosition.dx.clamp(0, width);
        final double progress = dx / width;
        _seekTo(progress);
      },
      onHorizontalDragEnd: (details) {
        _isDragging = false;
      },
      onTapDown: (details) {
        if (!_isInitialized) return;
        final RenderBox box = context.findRenderObject() as RenderBox;
        final double width = box.size.width;
        final double dx = details.localPosition.dx.clamp(0, width);
        final double progress = dx / width;
        _seekTo(progress);
      },
      child: Container(
        height: 32,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final progress = _duration.inMilliseconds > 0
                ? _position.inMilliseconds / _duration.inMilliseconds
                : 0.0;
            
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _waveformHeights.asMap().entries.map((entry) {
                final double height = entry.value;
                final int index = entry.key;
                final double barProgress = index / _waveformHeights.length;
                final bool isActive = barProgress <= progress;
                
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 0.5),
                    child: Container(
                      height: height,
                      decoration: BoxDecoration(
                        color: isActive ? activeColor : inactiveColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    
    final backgroundColor = widget.isMyMessage 
        ? (isLight ? Colors.white : theme.colorScheme.surface)
        : (isLight ? Colors.white : theme.colorScheme.surface);
    
    final textColor = theme.colorScheme.primary;
    final activeWaveColor = theme.colorScheme.primary;
    final inactiveWaveColor = theme.colorScheme.primary.withOpacity(0.24);

    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Oynat/Durdur butonu
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: _playPause,
              child: Container(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  _isPlaying ? Icons.pause : Icons.play_arrow,
                  color: textColor,
                  size: 24,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Dalga formu
          Expanded(
            child: _buildWaveform(activeWaveColor, inactiveWaveColor),
          ),
          const SizedBox(width: 8),
          // Süre
          Text(
            _isInitialized 
                ? _formatDuration(_position)
                : '00:00',
            style: TextStyle(
              color: textColor.withOpacity(0.7),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
} 