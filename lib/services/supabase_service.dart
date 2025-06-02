import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import '../models/chat_room_model.dart';
import '../models/message_model.dart';
import 'package:flutter/widgets.dart';

class SupabaseService {
  // Supabase için URL ve Anahtar değerlerini burada tanımlayın
  static const String supabaseUrl = 'https://rypmtmncokdzvhfmxrau.supabase.co';
  static const String supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ5cG10bW5jb2tkenZoZm14cmF1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDg2OTQ5MDcsImV4cCI6MjA2NDI3MDkwN30._PXofq-x_5gEBHT11RSitkJhe4ALpdbFbWaxIfT1zeE';

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseKey,
      realtimeClientOptions: const RealtimeClientOptions(
        eventsPerSecond: 40,
        timeout: Duration(seconds: 10), // Bağlantı zaman aşımını kısa tut
      ),
    );
    
    // Realtime kanallarını başlat
    await _initializeRealtimeChannels();
    
    print('Supabase initialized with realtime options');
  }
  
  // Realtime kanallarını önceden başlat
  static Future<void> _initializeRealtimeChannels() async {
    try {
      // Supabase client'ı al
      final client = Supabase.instance.client;
      
      // Global messages kanalını oluştur ve başlat
      final messagesChannel = client
        .channel('public:messages')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            print('Global messages kanalı - Yeni mesaj: $payload');
          })
        .subscribe((status, [_]) {
          print('Global messages kanalı durumu: $status');
        });
      
      print('Global realtime channels initialized');
    } catch (e) {
      print('Realtime channels initialization error: $e');
    }
  }

  static SupabaseClient get client => Supabase.instance.client;

  // Auth işlemleri
  Future<AuthResponse> signUp({required String email, required String password, required String name}) async {
    try {
      final response = await client.auth.signUp(
        email: email, 
        password: password,
        data: {'name': name},
      );
      
      if (response.user != null) {
        try {
          // Kullanıcıyı users tablosuna ekle
          await client.from('users').insert({
            'id': response.user!.id,
            'name': name,
            'created_at': DateTime.now().toIso8601String(),
          });
        } catch (e) {
          // Users tablosuna ekleme hatası olursa, kayıt başarılı olduğu için
          // bu hatayı yutuyoruz, çünkü trigger ile otomatik eklenmiş olabilir
          print('Users tablosuna ekleme hatası: $e');
        }
      }
      
      return response;
    } catch (e) {
      rethrow;
    }
  }

  Future<AuthResponse> signIn({required String email, required String password}) async {
    return await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async {
    await client.auth.signOut();
  }

  // Oturum kontrolü ve otomatik giriş için
  Future<bool> isAuthenticated() async {
    final session = await client.auth.currentSession;
    return session != null;
  }

  // Kullanıcı işlemleri
  Future<UserModel?> getCurrentUser() async {
    final user = client.auth.currentUser;
    if (user == null) return null;

    try {
      final response = await client
          .from('users')
          .select()
          .eq('id', user.id)
          .single();

      return UserModel.fromJson(response);
    } catch (e) {
      print('Kullanıcı bilgileri getirilirken hata: $e');
      // Eğer users tablosunda kayıt yoksa ama auth kullanıcısı varsa,
      // kullanıcı bilgilerini users tablosuna ekle
      try {
        final userData = {
          'id': user.id,
          'name': user.userMetadata?['name'] ?? 'Kullanıcı',
          'created_at': DateTime.now().toIso8601String(),
        };
        
        await client.from('users').insert(userData);
        return UserModel.fromJson(userData);
      } catch (e) {
        print('Kullanıcı ekleme hatası: $e');
        return null;
      }
    }
  }

  // Chat odası işlemleri
  Future<List<ChatRoomModel>> getChatRooms() async {
    final response = await client
        .from('chat_rooms')
        .select()
        .order('created_at', ascending: false);

    return (response as List).map((room) => ChatRoomModel.fromJson(room)).toList();
  }

  Future<ChatRoomModel> createChatRoom({required String title, required String userId}) async {
    final response = await client
        .from('chat_rooms')
        .insert({
          'title': title,
          'created_by': userId,
          'created_at': DateTime.now().toIso8601String(),
        })
        .select()
        .single();

    return ChatRoomModel.fromJson(response);
  }

  // Medya işlemleri
  
  // Resim yükleme
  Future<String> uploadImage(File imageFile, String roomId) async {
    final user = client.auth.currentUser;
    if (user == null) throw Exception('Kullanıcı oturum açmamış');
    
    try {
      print('Resim yükleme başlıyor: ${imageFile.path}');
      
      // Dosya adını oluştur
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${path.basename(imageFile.path)}';
      final filePath = 'room_$roomId/$fileName';
      
      print('Hedef yol: $filePath');
      
      // Önce bucket kontrolü yapalım
      final buckets = await client.storage.listBuckets();
      print('Mevcut bucketlar: ${buckets.map((b) => b.name).join(', ')}');
      
      // Bucket yoksa oluşturmayı deneyelim
      if (!buckets.any((b) => b.name == 'chat.images')) {
        try {
          print('chat.images bucket bulunamadı, oluşturuluyor...');
          await client.storage.createBucket('chat.images', const BucketOptions(public: true));
          print('chat.images bucket oluşturuldu');
        } catch (e) {
          print('Bucket oluşturma hatası: $e');
          // Hatayı yutuyoruz, belki başka bir kullanıcı zaten oluşturmuştur
        }
      }
      
      // Dosyayı yükle
      print('Dosya yükleniyor...');
      final bytes = await imageFile.readAsBytes();
      await client.storage
          .from('chat.images')
          .uploadBinary(filePath, bytes);
      
      print('Dosya başarıyla yüklendi');
      
      // Dosyanın public URL'sini al
      final imageUrl = client.storage.from('chat.images').getPublicUrl(filePath);
      print('Dosya URL: $imageUrl');
      
      return imageUrl;
    } catch (e) {
      print('Resim yükleme hatası: $e');
      rethrow;
    }
  }
  
  // Ses dosyası yükleme
  Future<String> uploadAudio(File audioFile, String roomId) async {
    final user = client.auth.currentUser;
    if (user == null) throw Exception('Kullanıcı oturum açmamış');
    
    try {
      print('Ses yükleme başlıyor: ${audioFile.path}');
      
      // Dosya adını oluştur
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${path.basename(audioFile.path)}';
      final filePath = 'room_$roomId/$fileName';
      
      print('Hedef yol: $filePath');
      
      // Önce bucket kontrolü yapalım
      final buckets = await client.storage.listBuckets();
      print('Mevcut bucketlar: ${buckets.map((b) => b.name).join(', ')}');
      
      // Bucket yoksa oluşturmayı deneyelim
      if (!buckets.any((b) => b.name == 'chat.voices')) {
        try {
          print('chat.voices bucket bulunamadı, oluşturuluyor...');
          await client.storage.createBucket('chat.voices', const BucketOptions(public: true));
          print('chat.voices bucket oluşturuldu');
        } catch (e) {
          print('Bucket oluşturma hatası: $e');
          // Hatayı yutuyoruz, belki başka bir kullanıcı zaten oluşturmuştur
        }
      }
      
      // Dosyayı yükle
      print('Ses dosyası yükleniyor...');
      final bytes = await audioFile.readAsBytes();
      await client.storage
          .from('chat.voices')
          .uploadBinary(filePath, bytes);
      
      print('Ses dosyası başarıyla yüklendi');
      
      // Dosyanın public URL'sini al
      final audioUrl = client.storage.from('chat.voices').getPublicUrl(filePath);
      print('Ses dosyası URL: $audioUrl');
      
      return audioUrl;
    } catch (e) {
      print('Ses yükleme hatası: $e');
      rethrow;
    }
  }

  // Mesaj işlemleri
  Future<List<MessageModel>> getMessages(String roomId) async {
    final response = await client
        .from('messages')
        .select('''
          *,
          users(name)
        ''')
        .eq('room_id', roomId)
        .order('timestamp', ascending: true);

    return (response as List).map((message) {
      // users tablosundan gelen name bilgisini ekleyelim
      final userData = message['users'] as Map<String, dynamic>;
      message['sender_name'] = userData['name'];
      return MessageModel.fromJson(message);
    }).toList();
  }

  // Metin mesajı gönderme
  Future<MessageModel> sendMessage({
    required String roomId,
    required String senderId,
    required String content,
  }) async {
    try {
      print('Mesaj gönderiliyor: $content');
      
      final response = await client
          .from('messages')
          .insert({
            'room_id': roomId,
            'sender_id': senderId,
            'content': content,
            'timestamp': DateTime.now().toIso8601String(),
            'content_type': 'text',
          })
          .select('''
            *,
            users (name)
          ''')
          .single();

      print('Mesaj veritabanına eklendi: $response');
      
      final userData = response['users'] as Map<String, dynamic>;
      response['sender_name'] = userData['name'];
      
      return MessageModel.fromJson(response);
    } catch (e) {
      print('Mesaj gönderme hatası: $e');
      rethrow;
    }
  }
  
  // Resim mesajı gönderme
  Future<MessageModel> sendImageMessage({
    required String roomId,
    required String senderId,
    required File imageFile,
    String caption = '',
  }) async {
    try {
      print('Resim mesajı gönderme başlıyor...');
      
      // Önce resim upload testi
      String? imageUrl;
      try {
        // Resmi yükle ve URL'ini al
        imageUrl = await uploadImage(imageFile, roomId);
        print('Resim URL alındı: $imageUrl');
      } catch (e) {
        print('Resim yükleme hatası (ilk upload denemesi): $e');
        
        // Basit bir URL oluştur - daha sonra tekrar dene
        imageUrl = 'https://example.com/placeholder.jpg';
      }
      
      // Mesajı veritabanına ekle
      print('Mesaj ekleniyor, content_type: image, media_url: $imageUrl');
      
      final response = await client
          .from('messages')
          .insert({
            'room_id': roomId,
            'sender_id': senderId,
            'content': caption.isEmpty ? 'Resim' : caption,
            'timestamp': DateTime.now().toIso8601String(),
            'content_type': 'image',
            'media_url': imageUrl,
          })
          .select('''
            *,
            users (name)
          ''')
          .single();

      print('Mesaj veritabanına eklendi: $response');
      
      final userData = response['users'] as Map<String, dynamic>;
      response['sender_name'] = userData['name'];
      
      return MessageModel.fromJson(response);
    } catch (e) {
      print('Resim mesajı gönderme hatası: $e');
      rethrow;
    }
  }
  
  // Ses mesajı gönder
  Future<MessageModel> sendAudioMessage({
    required String roomId,
    required String senderId,
    required File audioFile,
  }) async {
    try {
      final timestamp = DateTime.now().toIso8601String();
      final audioFileName = 'audio_message_${DateTime.now().millisecondsSinceEpoch}.m4a';
      
      // Dosyayı Supabase Storage'a yükle
      final storageResponse = await client
          .storage
          .from('chat.voices')
          .upload(
            'messages/$roomId/$audioFileName',
            audioFile,
            fileOptions: const FileOptions(
              cacheControl: '3600',
              upsert: false,
            ),
          );
      
      // Yüklenen dosyanın URL'ini al
      final audioUrl = client
          .storage
          .from('chat.voices')
          .getPublicUrl('messages/$roomId/$audioFileName');
      
      // Veritabanına mesaj kaydı ekle
      final response = await client
          .from('messages')
          .insert({
            'room_id': roomId,
            'sender_id': senderId,
            'content': 'Ses Mesajı', // Default mesaj içeriği
            'content_type': 'audio',
            'media_url': audioUrl,
            'timestamp': timestamp,
          })
          .select('''
            *,
            users(name)
          ''')
          .single();
      
      // Veritabanından dönen yanıtı MessageModel'e dönüştür
      final userData = response['users'] as Map<String, dynamic>;
      response['sender_name'] = userData['name'];
      
      return MessageModel.fromJson(response);
    } catch (e) {
      print('Ses mesajı gönderilirken hata: $e');
      rethrow;
    }
  }

  // Yazıyor durumu işlemleri için
  // Önce typing_status tablosu oluşturulmalı:
  // CREATE TABLE public.typing_status (
  //   id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  //   user_id UUID REFERENCES public.users NOT NULL,
  //   room_id UUID REFERENCES public.chat_rooms NOT NULL,
  //   is_typing BOOLEAN NOT NULL DEFAULT FALSE,
  //   updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
  //   UNIQUE(user_id, room_id)
  // );
  
  // Yazıyor durumunu güncelle
  Future<void> updateTypingStatus({
    required String roomId, 
    required String userId, 
    required bool isTyping
  }) async {
    try {
      print('updateTypingStatus: roomId=$roomId, userId=$userId, isTyping=$isTyping'); // Debug log
      
      // Upsert - insert or update
      await client.from('typing_status').upsert({
        'user_id': userId,
        'room_id': roomId,
        'is_typing': isTyping,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id, room_id');
      
      print('Typing status başarıyla güncellendi'); // Debug log
    } catch (e) {
      print('Yazıyor durumu güncellenirken hata: $e');
    }
  }
  
  // Odadaki yazıyor durumunda olan kullanıcıları getir
  Future<List<Map<String, dynamic>>> getTypingUsers(String roomId) async {
    try {
      print('getTypingUsers: roomId=$roomId'); // Debug log
      
      final response = await client
          .from('typing_status')
          .select('''
            user_id,
            is_typing,
            users (name)
          ''')
          .eq('room_id', roomId)
          .eq('is_typing', true)
          .gte('updated_at', DateTime.now().subtract(const Duration(seconds: 10)).toIso8601String());
      
      print('Typing status sorgu sonucu: $response'); // Debug log
          
      final result = (response as List).map((item) {
        final userData = item['users'] as Map<String, dynamic>;
        return {
          'user_id': item['user_id'],
          'is_typing': item['is_typing'],
          'name': userData['name'],
        };
      }).toList();
      
      print('Dönüştürülmüş typing status: $result'); // Debug log
      
      return result;
    } catch (e) {
      print('Yazıyor durumundaki kullanıcılar alınırken hata: $e');
      return [];
    }
  }
  
  // Yazıyor durumunu gerçek zamanlı dinle
  RealtimeChannel subscribeToTypingStatus(String roomId, Function(Map<String, dynamic>) onTypingChange) {
    print('subscribeToTypingStatus: roomId=$roomId'); // Debug log
    
    final channel = client
        .channel('public:typing_status')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'typing_status',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: roomId,
          ),
          callback: (payload) async {
            print('Typing status değişikliği: $payload'); // Debug log
            
            // Kullanıcı bilgisini al
            final userId = payload.newRecord?['user_id'] as String? ?? 
                           payload.oldRecord?['user_id'] as String?;
                           
            if (userId != null) {
              try {
                final userResponse = await client
                    .from('users')
                    .select('name')
                    .eq('id', userId)
                    .single();
                
                print('Kullanıcı bilgisi alındı: $userResponse'); // Debug log
                
                final typingData = {
                  'user_id': userId,
                  'is_typing': payload.newRecord?['is_typing'] ?? false,
                  'name': userResponse['name'],
                  'event_type': payload.eventType,
                };
                
                print('Typing callback çağrılıyor: $typingData'); // Debug log
                onTypingChange(typingData);
              } catch (e) {
                print('Kullanıcı bilgisi alınırken hata: $e'); // Debug log
              }
            }
          },
        );

    // Kanalı başlat
    channel.subscribe((status, [response]) {
      print('Typing status kanal durumu: $status, yanıt: $response'); // Debug log
    });
    
    return channel;
  }

  // Realtime mesaj aboneliği
  RealtimeChannel subscribeToMessages(String roomId, Function(MessageModel) onReceive) {
    print('Message subscription başlatılıyor: $roomId');
    
    // Benzersiz bir kanal ID'si oluştur (zaman damgası kullanarak)
    final channelId = 'messages_room_${roomId}_${DateTime.now().millisecondsSinceEpoch}';
    
    try {
      // ÖNEMLI: Tüm değişikliklere abone oluyoruz (insert, update, delete)
      final channel = client
          .channel(channelId)
          .onPostgresChanges(
            event: PostgresChangeEvent.insert, // Sadece yeni eklenen mesajlara abone ol
            schema: 'public',
            table: 'messages',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'room_id',
              value: roomId,
            ),
            callback: (payload) async {
              print('Mesaj değişikliği alındı: ${payload.eventType}, room: $roomId');
              print('Payload: $payload');
              
              try {
                // Yeni mesaj bilgilerini al
                final messageData = payload.newRecord;
                if (messageData == null) {
                  print('Mesaj verisi boş');
                  return;
                }
                
                // Kullanıcı bilgisini al
                final userId = messageData['sender_id'] as String;
                
                final userResponse = await client
                    .from('users')
                    .select('name')
                    .eq('id', userId)
                    .single();
                
                print('Mesaj için kullanıcı bilgisi alındı: $userResponse');
                
                final processedMessageData = {...messageData};
                processedMessageData['sender_name'] = userResponse['name'];
                
                final message = MessageModel.fromJson(processedMessageData);
                print('Oluşturulan mesaj modeli: $message');
                
                // Ana thread'de callback'i çağır
                onReceive(message);
              } catch (e, stack) {
                print('Mesaj işlenirken hata: $e');
                print('Stack trace: $stack');
              }
            },
          );

      // Kanalı başlat ve durumunu günlükle
      channel.subscribe((status, [response]) {
        print('Mesaj kanal durumu: $status, yanıt: $response');
        
        // Bağlantı hatası varsa yeniden bağlanmayı dene
        if (status == RealtimeSubscribeStatus.closed || 
            status == RealtimeSubscribeStatus.channelError) {
          print('Kanal bağlantı hatası. Yeniden bağlanılıyor...');
          Future.delayed(const Duration(seconds: 2), () {
            try {
              channel.subscribe();
            } catch (e) {
              print('Yeniden bağlanma hatası: $e');
            }
          });
        }
      });
      
      return channel;
    } catch (e, stack) {
      print('Kanal oluşturma hatası: $e');
      print('Stack trace: $stack');
      rethrow;
    }
  }

  // Son görüntüleme zamanını güncelle
  Future<void> updateLastRead(String roomId, String userId) async {
    try {
      print('Son görüntüleme zamanı güncelleniyor: roomId=$roomId, userId=$userId');
      
      // Son görüntüleme zamanını güncelle
      await client.from('last_read').upsert({
        'user_id': userId,
        'room_id': roomId,
        'last_read_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id, room_id');
      
      print('Son görüntüleme zamanı güncellendi');
    } catch (e) {
      print('Son görüntüleme zamanı güncellenirken hata: $e');
    }
  }
  
  // Odadaki okunmamış mesaj sayısını getir
  Future<int> getUnreadMessageCount(String roomId, String userId) async {
    try {
      print('Okunmamış mesaj sayısı alınıyor: roomId=$roomId, userId=$userId');
      
      // Kullanıcının son görüntüleme zamanını al
      final lastReadResponse = await client
          .from('last_read')
          .select('last_read_at')
          .eq('user_id', userId)
          .eq('room_id', roomId)
          .maybeSingle();
      
      // Son görüntüleme zamanı
      final lastReadAt = lastReadResponse != null
          ? DateTime.parse(lastReadResponse['last_read_at'])
          : DateTime.fromMillisecondsSinceEpoch(0); // Başlangıç zamanı
      
      print('Son görüntüleme zamanı: $lastReadAt');
      
      // Son görüntüleme zamanından sonraki mesajları al
      final messagesResponse = await client
          .from('messages')
          .select()
          .eq('room_id', roomId)
          .neq('sender_id', userId) // Kendi mesajlarını sayma
          .gt('timestamp', lastReadAt.toIso8601String());
      
      // Mesaj sayısını hesapla
      final unreadCount = messagesResponse.length;
      print('Okunmamış mesaj sayısı: $unreadCount');
      
      return unreadCount;
    } catch (e) {
      print('Okunmamış mesaj sayısı alınırken hata: $e');
      return 0;
    }
  }
  
  // Tüm odalar için okunmamış mesaj sayılarını getir
  Future<Map<String, int>> getAllUnreadMessageCounts(String userId) async {
    try {
      print('Tüm odalar için okunmamış mesaj sayısı alınıyor: userId=$userId');
      
      // Kullanıcının tüm son görüntüleme zamanlarını al
      final lastReadResponse = await client
          .from('last_read')
          .select('room_id, last_read_at')
          .eq('user_id', userId);
      
      // Oda ID'lerine göre son görüntüleme zamanları
      final Map<String, DateTime> lastReadTimes = {};
      for (final item in lastReadResponse) {
        lastReadTimes[item['room_id']] = DateTime.parse(item['last_read_at']);
      }
      
      // Kullanıcının tüm sohbet odalarını al
      final roomsResponse = await client
          .from('chat_rooms')
          .select('id');
      
      // Tüm odalardaki mesajları tek seferde sorgula (daha verimli)
      final messagesResponse = await client
          .from('messages')
          .select('room_id, sender_id, timestamp')
          .neq('sender_id', userId) // Kendi mesajlarını sayma
          .order('timestamp', ascending: false);
      
      // Her oda için okunmamış mesaj sayısını hesapla
      final Map<String, int> unreadCounts = {};
      
      // Önce tüm odaları 0 okunmamış mesaj sayısı ile başlat
      for (final room in roomsResponse) {
        unreadCounts[room['id']] = 0;
      }
      
      // Sonra her mesajı kontrol edip okunmamış mesajları say
      for (final message in messagesResponse) {
        final roomId = message['room_id'] as String;
        final timestamp = DateTime.parse(message['timestamp'] as String);
        final lastReadAt = lastReadTimes[roomId] ?? DateTime.fromMillisecondsSinceEpoch(0);
        
        // Eğer mesaj son görüntüleme zamanından daha yeniyse
        if (timestamp.isAfter(lastReadAt)) {
          unreadCounts[roomId] = (unreadCounts[roomId] ?? 0) + 1;
        }
      }
      
      print('Tüm odalar için okunmamış mesaj sayıları: $unreadCounts');
      return unreadCounts;
    } catch (e) {
      print('Tüm odalar için okunmamış mesaj sayıları alınırken hata: $e');
      return {};
    }
  }
} 