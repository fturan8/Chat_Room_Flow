import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/chat_room_model.dart';
import '../../models/user_model.dart';
import '../../services/supabase_service.dart';
import '../auth/login_screen.dart';
import 'chat_room_screen.dart';

// Okunmamış mesaj sayıları için state provider
final unreadMessagesProvider = StateProvider<Map<String, int>>((ref) => {});

class HomeScreen extends HookConsumerWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = useState<UserModel?>(null);
    final chatRooms = useState<List<ChatRoomModel>>([]);
    final isLoading = useState(true);
    final newRoomTitleController = useTextEditingController();
    final unreadMessages = ref.watch(unreadMessagesProvider);
    final realTimeChannelRef = useState<RealtimeChannel?>(null);
    final timerRef = useRef<Timer?>(null);
    
    // Okunmamış mesaj sayılarını yükle
    Future<void> _loadUnreadMessageCounts(String userId) async {
      try {
        final supabaseService = SupabaseService();
        final unreadCounts = await supabaseService.getAllUnreadMessageCounts(userId);
        
        if (context.mounted) {
          ref.read(unreadMessagesProvider.notifier).state = unreadCounts;
        }
      } catch (e) {
        print('Okunmamış mesaj sayıları alınırken hata: $e');
      }
    }
    
    // Realtime mesaj aboneliği
    void _setupRealtimeMessageSubscription(String userId) {
      try {
        // Önce mevcut kanalı temizle
        realTimeChannelRef.value?.unsubscribe();
        
        // Supabase client
        final supabase = Supabase.instance.client;
        
        // Global mesaj kanalına abone ol (tüm mesajlar)
        final globalMsgChannel = supabase.channel('home_messages_channel');
        
        // Mesaj tablosundaki değişikliklere abone ol
        globalMsgChannel
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'messages',
              callback: (payload) {
                print('Yeni mesaj algılandı (anasayfa): ${payload.toString()}');
                
                // Mesajın odası ve gönderen bilgisini al
                final newRecord = payload.newRecord;
                if (newRecord != null) {
                  final roomId = newRecord['room_id'] as String;
                  final senderId = newRecord['sender_id'] as String;
                  
                  // Kendi mesajımız değilse okunmamış mesaj sayısını güncelle
                  if (senderId != userId) {
                    print('Başka bir kullanıcıdan yeni mesaj geldi, sayaçlar güncelleniyor');
                    
                    // Anında güncelleme için doğrudan badge sayısını arttır
                    final currentUnreadMessages = ref.read(unreadMessagesProvider);
                    final updatedUnreadMessages = Map<String, int>.from(currentUnreadMessages);
                    
                    // İlgili odanın sayacını bir arttır
                    updatedUnreadMessages[roomId] = (updatedUnreadMessages[roomId] ?? 0) + 1;
                    
                    // Provider'ı güncelle - UI döngüsünün dışında
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (context.mounted) {
                        ref.read(unreadMessagesProvider.notifier).state = updatedUnreadMessages;
                      }
                    });
                    
                    // Ayrıca tam doğruluk için veritabanından da verileri getir
                    _loadUnreadMessageCounts(userId);
                  }
                }
              })
            .subscribe((status, [error]) {
              print('Anasayfa mesaj kanalı durumu: $status');
              if (error != null) {
                print('Abonelik hatası: $error');
              }
              
              // Bağlantı sorunlarını ele al
              if (status == RealtimeSubscribeStatus.closed || 
                  status == RealtimeSubscribeStatus.channelError) {
                print('Bağlantı kesildi, yeniden bağlanılıyor...');
                Future.delayed(const Duration(seconds: 2), () {
                  _setupRealtimeMessageSubscription(userId);
                });
              }
            });
        
        // Kanal referansını güncelle
        realTimeChannelRef.value = globalMsgChannel;
        
        print('Anasayfa realtime mesaj aboneliği kuruldu');
      } catch (e) {
        print('Realtime mesaj aboneliği kurulurken hata: $e');
        
        // Hata durumunda yeniden bağlanmayı dene
        Future.delayed(const Duration(seconds: 3), () {
          _setupRealtimeMessageSubscription(userId);
        });
      }
    }
    
    // Kullanıcı ve chat odalarını yükleme fonksiyonu
    Future<void> loadData() async {
      isLoading.value = true;
      try {
        final supabaseService = SupabaseService();
        
        // Mevcut kullanıcıyı al
        currentUser.value = await supabaseService.getCurrentUser();
        
        // Chat odalarını al
        if (currentUser.value != null) {
          chatRooms.value = await supabaseService.getChatRooms();
          
          // Okunmamış mesaj sayılarını yükle
          await _loadUnreadMessageCounts(currentUser.value!.id);
          
          // Timer başlat
          if (timerRef.value != null) {
            timerRef.value!.cancel();
          }
          
          timerRef.value = Timer.periodic(const Duration(seconds: 5), (timer) {
            if (context.mounted) {
              _loadUnreadMessageCounts(currentUser.value!.id);
            } else {
              timer.cancel();
            }
          });
          
          // Realtime mesaj aboneliği kur
          _setupRealtimeMessageSubscription(currentUser.value!.id);
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Veri yüklenirken hata: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        isLoading.value = false;
      }
    }

    // Çıkış yapma fonksiyonu
    Future<void> signOut() async {
      try {
        await SupabaseService().signOut();
        if (context.mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Çıkış yapılırken hata: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }

    // Yeni chat odası oluşturma fonksiyonu
    Future<void> createChatRoom() async {
      if (newRoomTitleController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lütfen bir oda adı girin'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      try {
        final supabaseService = SupabaseService();
        final newRoom = await supabaseService.createChatRoom(
          title: newRoomTitleController.text.trim(),
          userId: currentUser.value!.id,
        );
        
        // Oda listesini güncelle
        chatRooms.value = [newRoom, ...chatRooms.value];
        
        // Modalı kapat ve input temizle
        if (context.mounted) {
          Navigator.of(context).pop();
        }
        newRoomTitleController.clear();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Oda oluşturulurken hata: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }

    // Yeni oda oluşturma dialog'ını göster
    void showCreateRoomDialog() {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Yeni Chat Odası'),
          content: TextField(
            controller: newRoomTitleController,
            decoration: const InputDecoration(
              hintText: 'Oda adı girin',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: createChatRoom,
              child: const Text('Oluştur'),
            ),
          ],
        ),
      );
    }

    // Ekran ilk yüklendiğinde ve dispose olduğunda çalışacak hooks
    useEffect(() {
      // Verileri yükle
      loadData();
      
      // Widget dispose olduğunda çalışacak temizleme işlevi
      return () {
        // Timer'ı durdur
        timerRef.value?.cancel();
        
        // Realtime kanalını kapat
        realTimeChannelRef.value?.unsubscribe();
      };
    }, []);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ChatFlow'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: signOut,
            tooltip: 'Çıkış Yap',
          ),
        ],
      ),
      body: isLoading.value
          ? const Center(child: CircularProgressIndicator())
          : currentUser.value == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Oturum açık değil!',
                        style: TextStyle(fontSize: 18),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                                builder: (_) => const LoginScreen()),
                          );
                        },
                        child: const Text('Giriş Yap'),
                      ),
                    ],
                  ),
                )
              : chatRooms.value.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'Henüz hiç chat odası yok!',
                            style: TextStyle(fontSize: 18),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: showCreateRoomDialog,
                            icon: const Icon(Icons.add),
                            label: const Text('Yeni Oda Oluştur'),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: loadData,
                      child: ListView.builder(
                        itemCount: chatRooms.value.length,
                        itemBuilder: (context, index) {
                          final room = chatRooms.value[index];
                          final unreadCount = unreadMessages[room.id] ?? 0;
                          
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: ListTile(
                              title: Text(
                                room.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                'Oluşturan: ${room.createdBy == currentUser.value!.id ? "Siz" : "Başka bir kullanıcı"}',
                              ),
                              trailing: unreadCount > 0
                                  ? Badge(
                                      label: Text(unreadCount.toString()),
                                      isLabelVisible: true,
                                      backgroundColor: Theme.of(context).colorScheme.error,
                                    )
                                  : const Icon(Icons.arrow_forward_ios),
                              onTap: () {
                                // Odayı açtığımızda son görüntüleme zamanını güncelle
                                SupabaseService().updateLastRead(room.id, currentUser.value!.id);
                                
                                // Okunmamış mesaj sayısını hemen sıfırla
                                final updatedUnreadMessages = Map<String, int>.from(unreadMessages);
                                updatedUnreadMessages[room.id] = 0;
                                
                                // UI döngüsünün dışında güncelle
                                Future.microtask(() {
                                  ref.read(unreadMessagesProvider.notifier).state = updatedUnreadMessages;
                                });
                                
                                // Sohbet odasına git
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => ChatRoomScreen(
                                      room: room,
                                      currentUser: currentUser.value!,
                                    ),
                                  ),
                                ).then((_) {
                                  // Sohbet odasından döndüğünde okunmamış mesaj sayısını güncelle
                                  _loadUnreadMessageCounts(currentUser.value!.id);
                                });
                              },
                            ),
                          );
                        },
                      ),
                    ),
      floatingActionButton: !isLoading.value && currentUser.value != null
          ? FloatingActionButton(
              onPressed: showCreateRoomDialog,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
} 