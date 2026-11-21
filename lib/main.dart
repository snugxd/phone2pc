import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';

const _port = 45454;

Future<String> _sendTestPacket(String ip, int sequence) {
  return Isolate.run(() async {
    final address = InternetAddress.tryParse(ip);
    if (address == null || address.type != InternetAddressType.IPv4) {
      throw const FormatException('Enter a valid PC IPv4 address.');
    }

    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    try {
      final packet =
          'PHONE2PC|$sequence|${DateTime.now().millisecondsSinceEpoch}';
      final bytes = utf8.encode(packet);
      final sent = socket.send(bytes, address, _port);
      if (sent != bytes.length) {
        throw const SocketException('The UDP packet could not be sent.');
      }
      return packet;
    } finally {
      socket.close();
    }
  });
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Phone2PC',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final _ipController = TextEditingController();
  int _sequence = 0;
  bool _sending = false;
  String _status = 'No packet sent yet.';

  Future<void> _send() async {
    final ip = _ipController.text.trim();
    final sequence = ++_sequence;
    setState(() => _sending = true);

    try {
      final packet = await _sendTestPacket(ip, sequence);
      if (!mounted) return;
      setState(() => _status = 'Last packet sent: $packet');
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Error: $error');
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Phone2PC')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _ipController,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'PC IP address',
                  hintText: '192.168.1.100',
                ),
              ),
              const SizedBox(height: 12),
              const Text('Port: 45454'),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _sending ? null : _send,
                child: const Text('Send test packet'),
              ),
              const SizedBox(height: 12),
              Text(_status),
            ],
          ),
        ),
      ),
    );
  }
}
