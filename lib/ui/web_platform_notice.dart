import 'package:flutter/material.dart';

/// A deliberate web fallback. YouTube blocks iframe embedding and
/// `webview_flutter` has no browser implementation, so crashing after the
/// splash screen would be misleading and unusable.
class WebPlatformNotice extends StatelessWidget {
  const WebPlatformNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/infinity_tube_logo.png',
                    width: 112,
                    height: 112,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'InfinityTube for Web',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'The premium player needs native WebView and offline-storage APIs that browsers do not provide. Use the Android or iOS app for playback and downloads.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF171717),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.phone_android_rounded,
                          color: Color(0xFF3EA6FF),
                        ),
                        SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            'Native mobile release required',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
