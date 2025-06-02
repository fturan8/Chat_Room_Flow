import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import '../../models/chat_room_model.dart';
import '../../models/message_model.dart';
import '../../models/user_model.dart';
import '../../services/supabase_service.dart';
import '../../services/audio_service.dart';
import '../../widgets/audio_recording_sheet.dart';
import '../../widgets/audio_message.dart';
import 'home_screen.dart'; // unreadMessagesProvider için import

// AudioService için provider
final audioServiceProvider = Provider<AudioService>((ref) {
  final service = AudioService();
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});

class ChatRoomScreen extends StatefulHookConsumerWidget {
  final ChatRoomModel room;
  final UserModel currentUser;

  const ChatRoomScreen({
    Key? key,
    required this.room,
    required this.currentUser,
  }) : super(key: key);

  @override
  ConsumerState<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends ConsumerState<ChatRoomScreen> {
  // Yazıyor durumu kontrolü için
  bool _isTyping = false;
  Timer? _typingTimer;
  List<Map<String, dynamic>> _typingUsers = [];
  bool _showSendButton = false;
  
  // Channel referansları
  RealtimeChannel? _messageChannel;
  RealtimeChannel? _typingChannel;
  
  // Yazıyor durumunu güncelle
  void _updateTypingStatus(bool typing) {
    if (_isTyping == typing) return;
    
    setState(() {
      _isTyping = typing;
    });
    
    // Timerı iptal et
    _typingTimer?.cancel();
    
    if (typing) {
      // Yazıyor bilgisini gönder
      SupabaseService().updateTypingStatus(
        roomId: widget.room.id,
        userId: widget.currentUser.id,
        isTyping: true,
      );
      
      // Belirli süre sonra otomatik olarak yazıyor durumunu kapat
      _typingTimer = Timer(const Duration(seconds: 5), () {
        if (_isTyping) {
          _updateTypingStatus(false);
        }
      });
    } else {
      // Yazıyor durumunu kapat
      SupabaseService().updateTypingStatus(
        roomId: widget.room.id,
        userId: widget.currentUser.id,
        isTyping: false,
      );
    }
  }
  
  // Yazıyor durumundaki kullanıcıları getir
  Future<void> _loadTypingUsers() async {
    try {
      final supabaseService = SupabaseService();
      final users = await supabaseService.getTypingUsers(widget.room.id);
      
      print('Yazıyor durumundaki kullanıcılar: $users'); // Debug log
      
      // Kendi yazıyor durumunu filtrele
      setState(() {
        _typingUsers = users.where((user) => user['user_id'] != widget.currentUser.id).toList();
      });
      
      print('Filtrelenmiş yazıyor kullanıcıları: $_typingUsers'); // Debug log
    } catch (e) {
      print('Yazıyor durumundaki kullanıcılar alınırken hata: $e');
    }
  }
  
  // Yazı yazarken tetikle
  void _onTextChanged(String text) {
    print('Text changed: $text, isTyping: $_isTyping'); // Debug log
    
    if (text.isNotEmpty && !_isTyping) {
      print('Yazıyor durumu aktifleştiriliyor'); // Debug log
      _updateTypingStatus(true);
    } else if (text.isEmpty && _isTyping) {
      print('Yazıyor durumu kapatılıyor (boş metin)'); // Debug log
      _updateTypingStatus(false);
    } else if (_isTyping) {
      // Yazma süresi 5 saniye içinde resetlenir
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 5), () {
        if (_isTyping) {
          print('Yazıyor durumu kapatılıyor (zaman aşımı)'); // Debug log
          _updateTypingStatus(false);
        }
      });
    }
  }
  
  // Realtime mesaj kanalına abone ol
  void _setupMessageSubscription(Function(MessageModel) onMessageReceive) {
    final supabaseService = SupabaseService();
    
    _messageChannel = supabaseService.subscribeToMessages(
      widget.room.id,
      (MessageModel newMessage) {
        print('Yeni mesaj callback: ${newMessage.content}, type: ${newMessage.contentType}');
        
        // UI thread'de güncelleme yap
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            // Mesajı ekle
            onMessageReceive(newMessage);
            
            // Son görüntüleme zamanını güncelle
            supabaseService.updateLastRead(widget.room.id, widget.currentUser.id);
            
            // Okunmamış mesaj sayısını sıfırla (bu odada bulunduğumuz için)
            _updateUnreadCountForCurrentRoom();
          });
        }
      },
    );
  }
  
  // Bu oda için okunmamış mesaj sayısını sıfırla
  void _updateUnreadCountForCurrentRoom() {
    try {
      // Provider'a erişim
      final unreadMessages = ref.read(unreadMessagesProvider);
      if (unreadMessages.containsKey(widget.room.id)) {
        final updatedUnreadMessages = Map<String, int>.from(unreadMessages);
        updatedUnreadMessages[widget.room.id] = 0;
        
        // State güncellemesini UI döngüsünün dışında yap
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(unreadMessagesProvider.notifier).state = updatedUnreadMessages;
          }
        });
      }
    } catch (e) {
      print('Okunmamış mesaj sayısı güncellenirken hata: $e');
    }
  }
  
  // Realtime yazıyor durumu kanalına abone ol
  void _setupTypingSubscription() {
    final supabaseService = SupabaseService();
    
    print('Typing subscription başlatılıyor: ${widget.room.id}'); // Debug log
    
    _typingChannel = supabaseService.subscribeToTypingStatus(
      widget.room.id,
      (typingData) {
        // Kendi yazıyor durumunu gösterme
        print('Typing durumu değişti: $typingData'); // Debug log
        
        if (typingData['user_id'] != widget.currentUser.id) {
          print('Başka kullanıcı yazıyor: ${typingData['name']}'); // Debug log
          _loadTypingUsers();
        }
      },
    );
  }
  
  @override
  void initState() {
    super.initState();
    
    // Yazıyor kullanıcıları yükle
    _loadTypingUsers();
    
    // Yazıyor durumu aboneliğini kur 
    _setupTypingSubscription();
    
    // Son görüntüleme zamanını güncelle (odaya girdiğimizde)
    SupabaseService().updateLastRead(widget.room.id, widget.currentUser.id);
    
    // Okunmamış mesaj sayısını sıfırla - asenkron olarak yap
    Future.microtask(() {
      _updateUnreadCountForCurrentRoom();
    });
    
    // Ekstra: 1 saniye sonra abonelik durumunu kontrol et
    Future.delayed(const Duration(seconds: 1), () {
      if (_messageChannel == null) {
        print('Mesaj kanalı hala başlatılmadı, tekrar deneniyor...');
        _setupMessageSubscription((newMessage) {
          if (mounted) {
            setState(() {
              // mesaj listesini güncelleyecek
            });
          }
        });
      }
    });
  }
  
  @override
  void dispose() {
    _typingTimer?.cancel();
    _messageChannel?.unsubscribe();
    _typingChannel?.unsubscribe();
    
    // Yazıyor durumunu kapat
    SupabaseService().updateTypingStatus(
      roomId: widget.room.id,
      userId: widget.currentUser.id,
      isTyping: false,
    );
    
    // Son görüntüleme zamanını güncelle (odadan çıktığımızda)
    SupabaseService().updateLastRead(widget.room.id, widget.currentUser.id);
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = useState<List<MessageModel>>([]);
    final isLoading = useState(true);
    final messageController = useTextEditingController();
    final isSending = useState(false);
    final scrollController = useScrollController();
    final messageFocusNode = useFocusNode();

    // Mesajları yükle
    Future<void> loadMessages() async {
      isLoading.value = true;
      try {
        final supabaseService = SupabaseService();
        messages.value = await supabaseService.getMessages(widget.room.id);

        // Scroll en alta
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (scrollController.hasClients && messages.value.isNotEmpty) {
            scrollController.animateTo(
              scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Mesajlar yüklenirken hata: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        isLoading.value = false;
      }
    }

    // Yeni mesaj ekle (realtime veya manuel)
    void addNewMessage(MessageModel newMessage) {
      print('addNewMessage çağrıldı: ${newMessage.id}');
      
      // setState güvenli bir şekilde çağrılmalı
      if (!context.mounted) {
        print('Context mounted değil, mesaj eklenemedi');
        return;
      }
      
      // Aynı mesaj zaten varsa ekleme (id ile kontrol)
      if (!messages.value.any((m) => m.id == newMessage.id)) {
        print('Mesaj listeye ekleniyor: ${newMessage.id}');
        
        // setState içinde değil, doğrudan value güncelleniyor
        messages.value = [...messages.value, newMessage];
        
        // Scroll en alta
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (scrollController.hasClients) {
            scrollController.animateTo(
              scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      } else {
        print('Mesaj zaten listede var: ${newMessage.id}');
      }
    }

    // Realtime mesaj aboneliği kur
    void setupRealTimeSubscription() {
      _setupMessageSubscription((newMessage) {
        print('Yeni mesaj alındı: ${newMessage.content}');
        addNewMessage(newMessage);
      });
    }

    // İlk yüklemede mesajları getir ve realtime abonelik başlat
    useEffect(() {
      // Önce mevcut mesajları yükle
      loadMessages();
      
      // Realtime subscription kur
      setupRealTimeSubscription();
      
      // Scroll en alta - mesajlar yüklendikten sonra
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scrollController.hasClients && messages.value.isNotEmpty) {
          scrollController.animateTo(
            scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
      
      // Ekstra: Her 5 saniyede bir abonelik durumunu kontrol et
      final abonelikTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        
        // Kanal kontrolü yapın
        if (_messageChannel == null) {
          print('Mesaj kanalı bağlantısı kesildi, yeniden bağlanılıyor...');
          setupRealTimeSubscription();
        }
      });
      
      return () {
        // Widget dispose olduğunda çalışır
        abonelikTimer.cancel();
        _messageChannel?.unsubscribe();
        _typingChannel?.unsubscribe();
      };
    }, []);

    // Mesaj gönder
    Future<void> sendMessage() async {
      if (messageController.text.trim().isEmpty) return;

      isSending.value = true;
      
      // Yazıyor durumunu kapat
      _updateTypingStatus(false);
      
      try {
        final supabaseService = SupabaseService();
        final messageModel = await supabaseService.sendMessage(
          roomId: widget.room.id,
          senderId: widget.currentUser.id,
          content: messageController.text.trim(),
        );

        // Input temizle
        messageController.clear();

        // Yeni mesajı listeye ekle
        addNewMessage(messageModel);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Mesaj gönderilirken hata: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        isSending.value = false;
      }
    }

    // Resim seçme ve gönderme
    Future<void> _pickAndSendImage() async {
      final imagePicker = ImagePicker();
      final pickedFile = await imagePicker.pickImage(source: ImageSource.gallery);
      
      if (pickedFile != null) {
        try {
          final supabaseService = SupabaseService();
          final imageFile = File(pickedFile.path);
          
          // Resmi yükle ve mesaj olarak gönder
          final messageModel = await supabaseService.sendImageMessage(
            roomId: widget.room.id,
            senderId: widget.currentUser.id,
            imageFile: imageFile,
            caption: messageController.text.trim(),
          );
          
          // Input temizle
          messageController.clear();
          
          // Yeni mesajı listeye ekle
          addNewMessage(messageModel);
        } catch (e, stackTrace) {
          print('Resim gönderirken hata: $e');
          print('Hata detayı: $stackTrace');
          
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Resim gönderilirken hata oluştu'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      }
    }
    
    // Ses kaydetme ve gönderme
    Future<void> _recordAndSendAudio() async {
      // Kayıt için kullanıcı arayüzü
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => AudioRecordingSheet(
          onSend: (File audioFile) async {
            try {
              final supabaseService = SupabaseService();
              
              // Ses dosyasını yükle ve mesaj olarak gönder
              final messageModel = await supabaseService.sendAudioMessage(
                roomId: widget.room.id,
                senderId: widget.currentUser.id,
                audioFile: audioFile,
              );
              
              // Yeni mesajı listeye ekle
              addNewMessage(messageModel);
              
              // Scroll en alta
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (scrollController.hasClients) {
                  scrollController.animateTo(
                    scrollController.position.maxScrollExtent,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  );
                }
              });
            } catch (e) {
              print('Ses mesajı gönderirken hata: $e');
              
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Ses mesajı gönderilirken bir hata oluştu: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          },
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.room.title),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Mesaj listesi
          Expanded(
            child: isLoading.value
                ? const Center(child: CircularProgressIndicator())
                : messages.value.isEmpty
                    ? const Center(
                        child: Text('Henüz mesaj yok! İlk mesajı gönder.'),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: messages.value.length,
                        itemBuilder: (context, index) {
                          final message = messages.value[index];
                          final isMyMessage =
                              message.senderId == widget.currentUser.id;

                          return MessageBubble(
                            message: message,
                            isMyMessage: isMyMessage,
                          );
                        },
                      ),
          ),
          
          // Yazıyor... bildirimi
          if (_typingUsers.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              alignment: Alignment.centerLeft,
              child: Text(
                _typingUsers.length == 1
                    ? '${_typingUsers.first['name']} yazıyor...'
                    : '${_typingUsers.length} kişi yazıyor...',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            
          // Mesaj girişi
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                // Medya butonları
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      builder: (context) => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            leading: const Icon(Icons.image),
                            title: const Text('Resim Gönder'),
                            onTap: () {
                              Navigator.pop(context);
                              _pickAndSendImage();
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.mic),
                            title: const Text('Ses Kaydet'),
                            onTap: () {
                              Navigator.pop(context);
                              _recordAndSendAudio();
                            },
                          ),
                        ],
                      ),
                    );
                  },
                  color: Theme.of(context).colorScheme.primary,
                ),
                Expanded(
                  child: TextField(
                    controller: messageController,
                    focusNode: messageFocusNode,
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 1,
                    maxLines: 5,
                    decoration: InputDecoration(
                      hintText: 'Mesaj yaz...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceVariant,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      prefixIcon: IconButton(
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        onPressed: _pickAndSendImage,
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.mic_outlined),
                        onPressed: _recordAndSendAudio,
                      ),
                    ),
                    onChanged: (value) {
                      _updateTypingStatus(value.isNotEmpty);
                      
                      // Send butonu görünürlüğünü güncelleyin
                      if (value.isNotEmpty && !_showSendButton) {
                        setState(() {
                          _showSendButton = true;
                        });
                      } else if (value.isEmpty && _showSendButton) {
                        setState(() {
                          _showSendButton = false;
                        });
                      }
                    },
                  ),
                ),
                IconButton(
                  icon: isSending.value
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  onPressed: isSending.value ? null : sendMessage,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Mesaj balonu widget'ı
class MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMyMessage;

  const MessageBubble({
    Key? key,
    required this.message,
    required this.isMyMessage,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Tarih formatı
    final timeFormat = DateFormat('HH:mm');
    final dateFormat = DateFormat('dd MMM');
    final formattedTime = timeFormat.format(message.timestamp);
    final formattedDate = dateFormat.format(message.timestamp);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Align(
        alignment: isMyMessage ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isMyMessage
                ? Theme.of(context).colorScheme.primary.withOpacity(0.9)
                : Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment:
                isMyMessage ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!isMyMessage && message.senderName != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    message.senderName!,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: isMyMessage 
                          ? Colors.white.withOpacity(0.9)
                          : Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              // Mesaj içeriğini göster
              _buildMessageContent(context),
              const SizedBox(height: 4),
              Text(
                '$formattedTime, $formattedDate',
                style: TextStyle(
                  fontSize: 10,
                  color: isMyMessage 
                      ? Colors.white.withOpacity(0.8)
                      : Theme.of(context).colorScheme.onSecondaryContainer.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  // Mesaj içeriği widgetı
  Widget _buildMessageContent(BuildContext context) {
    // İçerik tipine göre farklı widget'lar döndür
    switch (message.contentType) {
      case 'image':
        return Column(
          crossAxisAlignment: isMyMessage ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (message.mediaUrl != null) 
              GestureDetector(
                onTap: () {
                  // Resmi tam ekran göster
                  showDialog(
                    context: context,
                    builder: (context) => Dialog(
                      child: Image.network(
                        message.mediaUrl!,
                        fit: BoxFit.contain,
                      ),
                    ),
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ImageWithLoadingEffect(imageUrl: message.mediaUrl!),
                ),
              ),
            if (message.content.isNotEmpty && message.content != 'Resim')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  message.content,
                  style: TextStyle(
                    color: isMyMessage 
                        ? Colors.white
                        : Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
          ],
        );
        
      case 'audio':
        return Consumer(
          builder: (context, ref, child) {
            return AudioMessage(
              audioUrl: message.mediaUrl!,
              isMyMessage: isMyMessage,
            );
          },
        );
        
      case 'text':
      default:
        return Text(
          message.content,
          style: TextStyle(
            color: isMyMessage 
                ? Colors.white
                : Theme.of(context).colorScheme.onSecondaryContainer,
          ),
        );
    }
  }
}

// Resim yüklenirken efekt göster
class ImageWithLoadingEffect extends StatefulWidget {
  final String imageUrl;
  
  const ImageWithLoadingEffect({
    Key? key,
    required this.imageUrl,
  }) : super(key: key);
  
  @override
  State<ImageWithLoadingEffect> createState() => _ImageWithLoadingEffectState();
}

class _ImageWithLoadingEffectState extends State<ImageWithLoadingEffect> {
  bool _isLoading = true;
  
  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Resim
        Image.network(
          widget.imageUrl,
          fit: BoxFit.cover,
          width: double.infinity,
          height: 200, 
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) {
              // Yükleme tamamlandı
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _isLoading) {
                  setState(() {
                    _isLoading = false;
                  });
                }
              });
              return _isLoading 
                ? ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                    child: child,
                  )
                : child;
            }
            return Container(
              height: 200,
              color: Colors.grey[200],
              child: Center(
                child: CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null 
                      ? loadingProgress.cumulativeBytesLoaded / 
                          loadingProgress.expectedTotalBytes!
                      : null,
                ),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return Container(
              height: 200,
              color: Colors.grey[300],
              child: const Center(
                child: Icon(Icons.error),
              ),
            );
          },
        ),
        
        // Yükleme göstergesi
        if (_isLoading)
          const CircularProgressIndicator(),
      ],
    );
  }
} 