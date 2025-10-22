import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
export 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart' show BluetoothDevice;
import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';
import 'package:vibration/vibration.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

void main() {
  runApp(const GestureRecognitionApp());
}

class GestureRecognitionApp extends StatelessWidget {
  const GestureRecognitionApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gesture Recognition',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
      ),
      home: const GestureHomePage(),
    );
  }
}

class GestureHomePage extends StatefulWidget {
  const GestureHomePage({Key? key}) : super(key: key);

  @override
  State<GestureHomePage> createState() => _GestureHomePageState();
}

class _GestureHomePageState extends State<GestureHomePage>
    with TickerProviderStateMixin {
  BluetoothConnection? connection;
  bool isConnected = false;
  bool isConnecting = false;

  String currentGesture = "NONE";
  double currentDistance = 0.0;
  double leftDistance = 0.0;
  double rightDistance = 0.0;

  List<BluetoothDevice> devicesList = [];
  BluetoothDevice? selectedDevice;
  StreamSubscription<Uint8List>? _dataSubscription;

  late AnimationController _pulseController;
  late AnimationController _slideController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _getPairedDevices();

    // Add error handling for Bluetooth initialization
    try {
      FlutterBluetoothSerial.instance.requestEnable();
    } catch (e) {
      print('Error enabling Bluetooth: $e');
    }

    // Add permission checks
    _requestPermissions();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _slideController.dispose();
    _dataSubscription?.cancel();
    connection?.dispose();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      await Permission.bluetooth.request();
      await Permission.location.request();
    }
  }

  Future<void> _getPairedDevices() async {
    try {
      List<BluetoothDevice> devices = await FlutterBluetoothSerial.instance
          .getBondedDevices();
      setState(() {
        devicesList = devices;
      });
    } catch (e) {
      debugPrint("Error getting devices: $e");
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    setState(() {
      isConnecting = true;
      selectedDevice = device;
    });

    try {
      BluetoothConnection conn = await BluetoothConnection.toAddress(
        device.address,
      );
      connection = conn;

      setState(() {
        isConnected = true;
        isConnecting = false;
      });

      _showSnackBar('Connected to ${device.name}', Colors.green);

      _dataSubscription = connection!.input?.listen(
        (Uint8List data) {
          String receivedData = utf8.decode(data);
          _parseData(receivedData);
        },
        onDone: () {
          setState(() {
            isConnected = false;
            connection = null;
          });
          _showSnackBar('Disconnected', Colors.red);
        },
        onError: (error) {
          setState(() {
            isConnected = false;
            connection = null;
          });
          _showSnackBar('Connection error: $error', Colors.red);
        },
      );
    } catch (e) {
      setState(() {
        isConnecting = false;
      });
      _showSnackBar('Connection Failed: $e', Colors.red);
    }
  }

  void _parseData(String data) {
    try {
      if (data.contains('GESTURE:')) {
        List<String> parts = data.split(',');

        String gesture = parts[0].replaceAll('GESTURE:', '').trim();
        String distStr = parts.length > 1
            ? parts[1].replaceAll('DIST:', '').trim()
            : '0';
        double distance = double.tryParse(distStr) ?? 0.0;

        if (mounted) {
          setState(() {
            currentGesture = gesture;
            currentDistance = distance;
          });
        }

        _handleGestureAnimation(gesture);
        _triggerVibration(gesture);
      }

      if (data.contains('L:') && data.contains('R:')) {
        List<String> parts = data.split(',');
        double l = double.tryParse(parts[0].replaceAll('L:', '').trim()) ?? 0.0;
        double r = double.tryParse(parts[1].replaceAll('R:', '').trim()) ?? 0.0;
        setState(() {
          leftDistance = l;
          rightDistance = r;
        });
      }
    } catch (e) {
      debugPrint("Parse error: $e");
    }
  }

  void _handleGestureAnimation(String gesture) {
    if (gesture.contains('SWIPE') || gesture.contains('MOVE')) {
      _slideController.forward(from: 0.0);
    }
  }

  Future<void> _triggerVibration(String gesture) async {
    try {
      if (await Vibration.hasVibrator() ?? false) {
        if (gesture.contains('SWIPE')) {
          Vibration.vibrate(duration: 200);
        } else if (gesture.contains('MOVE')) {
          Vibration.vibrate(duration: 100);
        }
      }
    } catch (e) {
      // ignore vibration errors
    }
  }

  void _sendCommand(String command) {
    if (isConnected && connection != null) {
      try {
        connection!.output.add(Uint8List.fromList(utf8.encode("$command\n")));
      } catch (e) {
        debugPrint("Send command error: $e");
      }
    } else {
      _showSnackBar('Not connected', Colors.orange);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _disconnect() {
    _dataSubscription?.cancel();
    connection?.dispose();
    setState(() {
      isConnected = false;
      connection = null;
      currentGesture = "NONE";
    });
  }

  Widget _buildConnectionButton() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: ElevatedButton.icon(
        onPressed: isConnected ? _disconnect : () => _showDeviceDialog(),
        icon: Icon(isConnected ? Icons.bluetooth_connected : Icons.bluetooth),
        label: Text(
          isConnected
              ? 'Connected to ${selectedDevice?.name ?? "Device"}'
              : 'Connect to Bluetooth',
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: isConnected ? Colors.green : Colors.blue,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          textStyle: const TextStyle(fontSize: 16),
        ),
      ),
    );
  }

  void _showDeviceDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Bluetooth Device'),
          content: SizedBox(
            width: double.maxFinite,
            child: devicesList.isEmpty
                ? const Center(child: Text('No paired devices found'))
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: devicesList.length,
                    itemBuilder: (context, index) {
                      BluetoothDevice device = devicesList[index];
                      return ListTile(
                        leading: const Icon(Icons.bluetooth),
                        title: Text(device.name ?? 'Unknown'),
                        subtitle: Text(device.address),
                        onTap: () {
                          Navigator.pop(context);
                          _connectToDevice(device);
                        },
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _getPairedDevices();
              },
              child: const Text('Refresh'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGestureDisplay() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _getGestureGradient(currentGesture),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _getGestureColor(currentGesture).withOpacity(0.3),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Transform.scale(
                scale: 1.0 + (_pulseController.value * 0.1),
                child: Icon(
                  _getGestureIcon(currentGesture),
                  size: 100,
                  color: Colors.white,
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Text(
            currentGesture,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${currentDistance.toStringAsFixed(1)} cm',
            style: const TextStyle(fontSize: 24, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  IconData _getGestureIcon(String gesture) {
    switch (gesture) {
      case 'MOVE_LEFT':
        return Icons.arrow_back;
      case 'MOVE_RIGHT':
        return Icons.arrow_forward;
      case 'SWIPE_CLOSER':
        return Icons.arrow_upward;
      case 'SWIPE_AWAY':
        return Icons.arrow_downward;
      case 'HOLD':
        return Icons.pan_tool;
      default:
        return Icons.help_outline;
    }
  }

  Color _getGestureColor(String gesture) {
    switch (gesture) {
      case 'MOVE_LEFT':
      case 'MOVE_RIGHT':
        return Colors.blue;
      case 'SWIPE_CLOSER':
        return Colors.green;
      case 'SWIPE_AWAY':
        return Colors.red;
      case 'HOLD':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  List<Color> _getGestureGradient(String gesture) {
    Color primary = _getGestureColor(gesture);
    return [primary, primary.withOpacity(0.6)];
  }

  Widget _buildSensorData() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildSensorInfo('Left Sensor', leftDistance, Icons.arrow_back),
          Container(width: 1, height: 50, color: Colors.white.withOpacity(0.2)),
          _buildSensorInfo('Right Sensor', rightDistance, Icons.arrow_forward),
        ],
      ),
    );
  }

  Widget _buildSensorInfo(String label, double distance, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.blue, size: 30),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
        const SizedBox(height: 4),
        Text(
          '${distance.toStringAsFixed(1)} cm',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildControlButtons() {
    return Container(
      margin: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildControlButton(
            'LED ON',
            Icons.lightbulb,
            Colors.green,
            () => _sendCommand('LED_ON'),
          ),
          _buildControlButton(
            'LED OFF',
            Icons.lightbulb_outline,
            Colors.red,
            () => _sendCommand('LED_OFF'),
          ),
          _buildControlButton(
            'Status',
            Icons.info_outline,
            Colors.blue,
            () => _sendCommand('STATUS'),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: ElevatedButton(
          onPressed: isConnected ? onPressed : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 28),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🤚 Gesture Recognition'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              _buildConnectionButton(),
              const SizedBox(height: 16),
              if (isConnected) ...[
                _buildGestureDisplay(),
                const SizedBox(height: 16),
                _buildSensorData(),
                const SizedBox(height: 16),
                _buildControlButtons(),
              ] else ...[
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 80),
                      Icon(
                        Icons.bluetooth_disabled,
                        size: 100,
                        color: Colors.grey.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Not Connected',
                        style: TextStyle(
                          fontSize: 24,
                          color: Colors.grey.withOpacity(0.7),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Connect to start detecting gestures',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
