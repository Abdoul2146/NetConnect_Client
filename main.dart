import 'package:flutter/material.dart';
import 'package:netconnect/screens/welcome_page.dart';
import 'package:netconnect/screens/theme_provider.dart';
import 'package:provider/provider.dart';
// NEW: Import your WebSocketProvider
import 'package:netconnect/screens/websocket_provider.dart';

void main() {
  runApp(
    // NEW: Use MultiProvider to provide both ThemeProvider and WebSocketProvider
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => ThemeProvider()),
        ChangeNotifierProvider(
          create: (context) => WebSocketProvider(),
        ), // NEW: Provide WebSocketProvider
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Consumer for ThemeProvider remains
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'NetChat',
          theme: ThemeData(
            brightness: Brightness.light,
            useMaterial3: false, // <-- Switch to Material 2
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blueGrey,
              brightness: Brightness.light,
            ),
            appBarTheme: AppBarTheme(
              backgroundColor: Colors.white, // White background
              foregroundColor: Colors.black, // Black text/icons
              iconTheme: IconThemeData(color: Colors.black), // Black icons
              titleTextStyle: TextStyle(
                color: Colors.black,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              elevation: 0, // Optional: removes shadow for a flat look
            ),
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            useMaterial3: false, // <-- Switch to Material 2
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blueGrey,
              brightness: Brightness.dark,
              primary: Colors.blueGrey,
              onPrimary: Colors.white,
              surface: Colors.blueGrey, // <-- Add this
              onSurface: Colors.white, // <-- And this
            ),

            scaffoldBackgroundColor: const Color(0xFF18191A),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF242526),
              foregroundColor: Colors.white,
            ),
            cardColor: const Color(0xFF242526),
            dialogTheme: const DialogTheme(
              backgroundColor: Color(0xFF242526),
              titleTextStyle: TextStyle(color: Colors.white, fontSize: 20),
              contentTextStyle: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.all(Colors.blueGrey),
                foregroundColor: WidgetStateProperty.all(Colors.white),
                padding: WidgetStateProperty.all(
                  const EdgeInsets.symmetric(vertical: 12.0),
                ),
              ),
            ),
            bottomNavigationBarTheme: const BottomNavigationBarThemeData(
              backgroundColor: Color(0xFF242526),
              selectedItemColor: Colors.white,
              unselectedItemColor: Colors.grey,
              selectedIconTheme: IconThemeData(color: Colors.white),
              unselectedIconTheme: IconThemeData(color: Colors.grey),
              selectedLabelStyle: TextStyle(color: Colors.white),
              unselectedLabelStyle: TextStyle(color: Colors.grey),
            ),
          ),
          themeMode: themeProvider.themeMode,
          // RETAINED: Your NetChatSplashScreen remains the home
          home: const NetChatSplashScreen(),
        );
      },
    );
  }
}
