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
      home: const ReceiverTestScreen(),
    );
  }
}

class ReceiverTestScreen extends StatefulWidget {
  const ReceiverTestScreen({super.key});

  @override
  State<ReceiverTestScreen> createState() => _ReceiverTestScreenState();
}

class _ReceiverTestScreenState extends State<ReceiverTestScreen> {
  String _localIpAddress = 'Fetching IP...';
  bool _isConnected = false;
  io.RawDatagramSocket? _receiverSocket;
  
  // Frame reassembly buffers
  final Map<int, Map<int, Uint8List>> _pendingFrames = {};
  Uint8List? _activeFrameBytes;

  @override
  void initState() {
    super.initState();
    _startReceiverService();
  }

  Future<void> _startReceiverService() async {
    try {
      // Keep screen awake on Chromecast
      SystemChannels.platform.invokeMethod('SystemChrome.setEnabledSystemUIMode', [SystemUiMode.immersiveSticky]);

      // Get local Wi-Fi IP address
      for (var interface in await io.NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == io.InternetAddressType.IPv4 && !addr.isLoopback) {
            setState(() {
              _localIpAddress = addr.address;
            });
          }
        }
      }

      // Bind UDP socket listener on port 9876
      _receiverSocket = await io.RawDatagramSocket.bind(io.InternetAddress.anyIPv4, 9876);
      _receiverSocket?.listen((io.RawSocketEvent event) {
        if (event == io.RawSocketEvent.read) {
          io.Datagram? datagram = _receiverSocket?.receive();
          if (datagram != null && datagram.data.length > 6) {
            _handleIncomingPacket(datagram.data);
          }
        }
      });
    } catch (e) {
      debugPrint('Receiver initialization error: $e');
    }
  }

  /// Packet Protocol: [4 bytes Frame ID][2 bytes Chunk Index/Total][Payload Bytes...]
  void _handleIncomingPacket(Uint8List packetData) {
    try {
      final byteData = ByteData.sublistView(packetData);
      final int frameId = byteData.getUint32(0, Endian.big);
      final int chunkInfo = byteData.getUint16(4, Endian.big);
      final int chunkIndex = (chunkInfo >> 8) & 0xFF;
      final int totalChunks = chunkInfo & 0xFF;
      final Uint8List payload = Uint8List.sublistView(packetData, 6);

      _pendingFrames.putIfAbsent(frameId, () => {});
      _pendingFrames[frameId]![chunkIndex] = payload;

      // Check if all chunks for this frame have arrived
      if (_pendingFrames[frameId]!.length == totalChunks) {
        final sortedKeys = _pendingFrames[frameId]!.keys.toList()..sort();
        final List<int> completeBytes = [];
        for (var key in sortedKeys) {
          completeBytes.addAll(_pendingFrames[frameId]![key]!);
        }

        setState(() {
          _isConnected = true;
          _activeFrameBytes = Uint8List.fromList(completeBytes);
        });

        // Clean up older frames
        _pendingFrames.removeWhere((key, value) => key < frameId);
      }
    } catch (e) {
      debugPrint('Packet reassembly error: $e');
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
          if (event is KeyDownEvent) {
            debugPrint('TV Remote Key: ${event.logicalKey.keyLabel}');
          }
          return KeyEventResult.handled;
        },
        child: Stack(
          children: [
            Center(
              child: _isConnected && _activeFrameBytes != null
                  ? Image.memory(
                      _activeFrameBytes!,
                      gaplessPlayback: true,
                      fit: BoxFit.contain,
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(color: Colors.blueAccent),
                        const SizedBox(height: 24),
                        const Text(
                          'Waiting for Pixel 9 Host Stream...',
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
                            'TV Receiver IP: $_localIpAddress (Port: 9876)',
                            style: const TextStyle(fontSize: 16, color: Colors.cyanAccent, fontFamily: 'monospace'),
                          ),
                        ),
                      ],
                    ),
            ),
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
                    'STREAM LIVE',
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
