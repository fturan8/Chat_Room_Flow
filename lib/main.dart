import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'services/supabase_service.dart';
import 'services/permission_service.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Supabase'i başlat
  await SupabaseService.initialize();
  
  // Mikrofon izni
  try {
    final status = await Permission.microphone.status;
    print('Ana uygulama başlangıcı: Mikrofon izni durumu: $status');
    
    // Direkt izin iste
    final result = await Permission.microphone.request();
    print('Ana uygulama başlangıcı: Mikrofon izin sonucu: $result');
  } catch (e) {
    print('Ana uygulama başlangıcı: Mikrofon izni hatası: $e');
  }
  
  // Realtime'ı özellikle etkinleştir
  final supabase = Supabase.instance.client;
  
  // Tüm kanallar için otomatik yeniden bağlanmayı etkinleştir
  supabase.realtime.setAuth(supabase.auth.currentSession?.accessToken ?? '');
  
  // Evrensel Realtime kanalını manuel olarak başlat
  final universalChannel = supabase.channel('global_realtime');
  universalChannel.subscribe((status, [error]) {
    print('Global realtime status: $status');
    if (error != null) {
      print('Global realtime error: $error');
    }
  });
  
  runApp(
    ProviderScope(
      child: ChatFlowApp(),
    ),
  );
}

class ChatFlowApp extends StatefulWidget {
  const ChatFlowApp({super.key});

  @override
  State<ChatFlowApp> createState() => _ChatFlowAppState();
}

class _ChatFlowAppState extends State<ChatFlowApp> {
  bool _isAuthenticated = false;
  bool _isLoading = true;
  final _permissionService = PermissionService();

  @override
  void initState() {
    super.initState();
    _checkAuth();
    // İzinleri başlangıçta iste
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Permission.microphone.request();
    });
  }

  // Oturum durumunu kontrol et
  Future<void> _checkAuth() async {
    final supabaseService = SupabaseService();
    final isAuth = await supabaseService.isAuthenticated();
    
    if (mounted) {
      setState(() {
        _isAuthenticated = isAuth;
        _isLoading = false;
      });
    }
  }
  
  // Uygulama izinlerini iste
  Future<void> _requestPermissions() async {
    try {
      // _permissionService sınıf üyesini kullan
      await _permissionService.requestMicrophonePermission();
    } catch (e) {
      print('İzin isteme hatası: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ChatFlow',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: _isLoading
          ? const _LoadingScreen()
          : _isAuthenticated
              ? const HomeScreen()
              : const LoginScreen(),
    );
  }
}

// Uygulama yüklenirken gösterilen ekran
class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('ChatFlow yükleniyor...'),
          ],
        ),
      ),
    );
  }
}
