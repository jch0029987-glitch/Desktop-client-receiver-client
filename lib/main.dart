import 'dart:io' as io;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const DesktopReceiverApp());
}

class DesktopReceiverApp extends StatelessWidget {
  const DesktopReceiverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Desktop Wireless Receiver',
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const ReceiverDashboardScreen(),
    );
  }
}

class ReceiverDashboardScreen extends StatefulWidget {
  const ReceiverDashboardScreen({super.key});

  @override
  State<ReceiverDashboardScreen> createState() => _ReceiverDashboardScreenState();
}

class _ReceiverDashboardScreenState extends State<ReceiverDashboardScreen> {
  String _localIpAddress = 'Fetching IP...';
  bool _isConnected = false;
  io.RawDatagramSocket? _receiverSocket;
  Uint8List? _latestFrameBytes;

  @override
  void initState() {
    super.initState();
    _initNetworkListener();
  }

  Future<void> _initNetworkListener() async {
    try {
      // Find local IP address on the Wi-Fi network
      for (var interface in await io.NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == io.InternetAddressType.IPv4 && !addr.isLoopback) {
            setState(() {
              _localIpAddress = addr.address;
            });
          }
        }
      }

      // Bind UDP socket to listen for incoming stream packets from Pixel 9 host
      _receiverSocket = await io.RawDatagramSocket.bind(io.InternetAddress.anyIPv4, 9876);
      _receiverSocket?.listen((io.RawSocketEvent event) {
        if (event == io.RawSocketEvent.read) {
          io.Datagram? datagram = _receiverSocket?.receive();
          if (datagram != null) {
            setState(() {
              _isConnected = true;
              _latestFrameBytes = datagram.data;
            });
          }
        }
      });
    } catch (e) {
      debugPrint('Socket initialization error: $e');
    }
  }

  @override
  void dispose() {
    _receiverSocket?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          // Capture Android TV D-Pad or Bluetooth Keyboard/Mouse inputs
          if (event is KeyDownEvent) {
            debugPrint('Key pressed on TV receiver: ${event.logicalKey.keyLabel}');
          }
          return KeyEventResult.handled;
        },
        child: Stack(
          children: [
            // Stream Rendering Surface or Waiting State
            Center(
              child: _isConnected && _latestFrameBytes != null
                  ? Image.memory(
                      _latestFrameBytes!,
                      gaplessPlayback: true,
                      fit: BoxFit.contain,
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(color: Colors.blueAccent),
                        const SizedBox(height: 24),
                        const Text(
                          'Waiting for Pixel 9 Host Connection...',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white70),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.grey[900],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blueAccent.withOpacity(0.5)),
                          ),
                          child: Text(
                            'Receiver IP Address: $_localIpAddress (Port: 9876)',
                            style: const TextStyle(fontSize: 16, color: Colors.cyanAccent, fontFamily: 'monospace'),
                          ),
                        ),
                      ],
                    ),
            ),
            
            // Status HUD Overlay (Disappears when connected)
            if (_isConnected)
              Positioned(
                top: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'LIVE STREAM ACTIVE',
                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
