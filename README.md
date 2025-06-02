# Chat Flow

Modern ve kullanımı kolay bir sohbet uygulaması.

## Özellikler

- **Gerçek Zamanlı Mesajlaşma**: Anlık mesaj gönderimi ve alımı
- **Multimedya Desteği**: Resim ve ses mesajları gönderme
- **Ses Mesajları**: Kullanıcı dostu ses kaydetme ve oynatma arayüzü
- **Yazıyor Göstergesi**: Kullanıcının yazma durumunu takip etme
- **Okunmamış Mesaj Sayacı**: Okunmamış mesajların takibi
- **Modern UI/UX**: Material Design 3 kullanılan şık arayüz
- **Platform Uyumluluğu**: iOS ve Android için optimize edilmiş deneyim

## Teknik Özellikler

- Flutter 3.0+ ile geliştirilmiştir
- Supabase gerçek zamanlı veritabanı kullanılmaktadır
- Riverpod state yönetimi
- Just Audio ve Record kütüphaneleri ile ses yönetimi
- Platform-spesifik özelleştirmeler

## Kurulum

1. Repo'yu klonlayın:
```bash
git clone https://github.com/username/chat_flow.git
```

2. Bağımlılıkları yükleyin:
```bash
flutter pub get
```

3. Supabase ortamınızı kurun ve `.env` dosyasına API anahtarlarını ekleyin

4. Uygulamayı çalıştırın:
```bash
flutter run
```

## Son Güncellemeler

- iOS mikrofon izinleri sorunu çözüldü
- Ses kaydı ve oynatma performansı iyileştirildi
- Ses mesajları için modern ve etkileşimli bir arayüz eklendi
- Dalga formu (waveform) eklendi ve sürükleme ile ilerleme kontrolü sağlandı
- Tek bir ses dosyasının oynatılması sağlandı
