# Chat Flow

A modern, real-time messaging application built with Flutter and Supabase.

![Chat Flow](https://i.imgur.com/nYzGTfG.png)

## Features

- **Real-time Messaging**: Instant message delivery and receipt using Supabase Realtime
- **Multimedia Support**: Send and receive images and audio messages
- **Audio Messaging**: User-friendly audio recording and playback interface with waveform visualization
- **Typing Indicators**: Track when users are typing in real-time
- **Unread Message Counter**: Keep track of unread messages in conversations
- **Modern UI/UX**: Sleek interface designed with Material Design 3
- **Platform Compatibility**: Optimized experience for both iOS and Android

## Technical Specifications

- Built with Flutter 3.0+
- Supabase for real-time database and authentication
- Riverpod for state management
- Just Audio and Record libraries for audio management
- Platform-specific optimizations for iOS and Android

## Getting Started

### Prerequisites

- Flutter SDK (3.0.0 or higher)
- Dart SDK (3.0.0 or higher)
- Supabase account
- IDE (VS Code, Android Studio, etc.)

### Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/chat_flow.git
cd chat_flow
```

2. Install dependencies:
```bash
flutter pub get
```

3. Set up your Supabase environment:
   - Create a `.env` file in the root directory
   - Add your Supabase URL and anon key:
   ```
   SUPABASE_URL=your_supabase_url
   SUPABASE_KEY=your_supabase_anon_key
   ```

4. Run the application:
```bash
flutter run
```

## Project Structure

```
lib/
├── models/           # Data models
│   ├── chat_room_model.dart
│   ├── message_model.dart
│   └── user_model.dart
├── screens/          # UI screens
│   ├── auth/         # Authentication screens
│   └── home/         # Main app screens
├── services/         # Backend services
│   ├── audio_service.dart
│   ├── permission_service.dart
│   └── supabase_service.dart
├── widgets/          # Reusable UI components
│   ├── audio_message.dart
│   └── audio_recording_sheet.dart
└── main.dart         # Application entry point
```

## Supabase Setup

### Database Schema

The application requires the following tables in your Supabase project. Run these SQL statements in your Supabase SQL editor:

```sql
-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Users Table
CREATE TABLE public.users (
  id UUID REFERENCES auth.users NOT NULL PRIMARY KEY,
  name TEXT NOT NULL,
  avatar_url TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

-- Set up Row Level Security (RLS)
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users are viewable by everyone" ON public.users
  FOR SELECT USING (true);
CREATE POLICY "Users can update their own profile" ON public.users
  FOR UPDATE USING (auth.uid() = id);

-- Trigger to create a user profile on sign-up
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.users (id, name, avatar_url)
  VALUES (new.id, new.raw_user_meta_data->>'name', new.raw_user_meta_data->>'avatar_url');
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- Chat Rooms Table
CREATE TABLE public.chat_rooms (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  title TEXT NOT NULL,
  created_by UUID REFERENCES public.users NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

-- Set up RLS for chat_rooms
ALTER TABLE public.chat_rooms ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Chat rooms are viewable by everyone" ON public.chat_rooms
  FOR SELECT USING (true);
CREATE POLICY "Users can create chat rooms" ON public.chat_rooms
  FOR INSERT WITH CHECK (auth.uid() = created_by);

-- Messages Table
CREATE TABLE public.messages (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  room_id UUID REFERENCES public.chat_rooms NOT NULL,
  sender_id UUID REFERENCES public.users NOT NULL,
  content TEXT NOT NULL,
  content_type TEXT DEFAULT 'text' NOT NULL, -- 'text', 'image', 'audio'
  media_url TEXT,
  timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

-- Set up RLS for messages
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Messages are viewable by everyone" ON public.messages
  FOR SELECT USING (true);
CREATE POLICY "Users can insert messages" ON public.messages
  FOR INSERT WITH CHECK (auth.uid() = sender_id);

-- Typing Status Table
CREATE TABLE public.typing_status (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id UUID REFERENCES public.users NOT NULL,
  room_id UUID REFERENCES public.chat_rooms NOT NULL,
  is_typing BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
  UNIQUE(user_id, room_id)
);

-- Set up RLS for typing_status
ALTER TABLE public.typing_status ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Typing status is viewable by everyone" ON public.typing_status
  FOR SELECT USING (true);
CREATE POLICY "Users can update their own typing status" ON public.typing_status
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update their own typing status" ON public.typing_status
  FOR UPDATE USING (auth.uid() = user_id);

-- Last Read Table
CREATE TABLE public.last_read (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id UUID REFERENCES public.users NOT NULL,
  room_id UUID REFERENCES public.chat_rooms NOT NULL,
  last_read_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
  UNIQUE(user_id, room_id)
);

-- Set up RLS for last_read
ALTER TABLE public.last_read ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Last read is viewable by everyone" ON public.last_read
  FOR SELECT USING (true);
CREATE POLICY "Users can update their own last read status" ON public.last_read
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update their own last read status" ON public.last_read
  FOR UPDATE USING (auth.uid() = user_id);
```

### Storage Buckets

Create the following storage buckets in your Supabase project:

1. **chat.images** - For storing image messages
2. **chat.voices** - For storing audio messages

Make sure to set the following bucket policies:

```sql
-- For chat.images bucket
CREATE POLICY "Images are publicly accessible"
ON storage.objects FOR SELECT
USING (bucket_id = 'chat.images');

CREATE POLICY "Authenticated users can upload images"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'chat.images' 
  AND auth.role() = 'authenticated'
);

-- For chat.voices bucket
CREATE POLICY "Voice messages are publicly accessible"
ON storage.objects FOR SELECT
USING (bucket_id = 'chat.voices');

CREATE POLICY "Authenticated users can upload voice messages"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'chat.voices' 
  AND auth.role() = 'authenticated'
);
```

### Enable Realtime

Make sure to enable Realtime in your Supabase project settings for the following tables:
- `messages`
- `typing_status`
- `last_read`

## Key Implementations

### Audio Messaging

The application features a sophisticated audio messaging system with:
- Custom waveform visualization
- Playback speed control
- Drag-to-seek functionality
- Platform-specific optimizations for audio recording and playback

### Real-time Communication

Built on Supabase Realtime for:
- Instant message delivery
- Typing indicators
- Presence detection
- Read receipts

### Permission Handling

Robust permission handling for:
- Microphone access
- Camera/image gallery access
- File system access

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request




