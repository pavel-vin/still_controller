import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:convert';
import 'dart:async';
import 'package:json_annotation/json_annotation.dart';
part 'main.g.dart';

// Модель данных для состояния
@JsonSerializable()
class StillState {
  String mode;
  double cube_temp;
  double column_temp;
  double? tsa_temp;
  double water_temp;
  double flow_rate;
  double total_flow;
  double pressure;
  bool leak_detected;
  bool heating;
  int servo_angle;

  StillState({
    required this.mode,
    required this.cube_temp,
    required this.column_temp,
    this.tsa_temp,
    required this.water_temp,
    required this.flow_rate,
    required this.total_flow,
    required this.pressure,
    required this.leak_detected,
    required this.heating,
    required this.servo_angle,
  });

  factory StillState.fromJson(Map<String, dynamic> json) => _$StillStateFromJson(json);
  Map<String, dynamic> toJson() => _$StillStateToJson(this);
}

// Модель для конфигурации
@JsonSerializable()
class Config {
  String wifi_ssid;
  String wifi_password;
  double cube_offset;
  double column_offset;
  double tsa_offset;
  double water_offset;
  double flow_pulses_per_liter;
  int heads_servo_angle;
  int body_servo_angle;
  double temp_delta;
  int servo_step;
  double pid_kp;
  double pid_ki;
  double pid_kd;
  bool use_pid;
  String cube_sensor_id;
  String column_sensor_id;
  String tsa_sensor_id;
  String water_sensor_id;

  Config({
    required this.wifi_ssid,
    required this.wifi_password,
    required this.cube_offset,
    required this.column_offset,
    required this.tsa_offset,
    required this.water_offset,
    required this.flow_pulses_per_liter,
    required this.heads_servo_angle,
    required this.body_servo_angle,
    required this.temp_delta,
    required this.servo_step,
    required this.pid_kp,
    required this.pid_ki,
    required this.pid_kd,
    required this.use_pid,
    required this.cube_sensor_id,
    required this.column_sensor_id,
    required this.tsa_sensor_id,
    required this.water_sensor_id,
  });

  factory Config.fromJson(Map<String, dynamic> json) => _$ConfigFromJson(json);
  Map<String, dynamic> toJson() => _$ConfigToJson(this);
}

// Модель для фракций
@JsonSerializable()
class Fractions {
  double heads;
  double body;
  double tails;

  Fractions({required this.heads, required this.body, required this.tails});

  factory Fractions.fromJson(Map<String, dynamic> json) => _$FractionsFromJson(json);
  Map<String, dynamic> toJson() => _$FractionsToJson(this);
}

void main() {
  runApp(StillControllerApp());
}

class StillControllerApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Still Controller',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        buttonTheme: ButtonThemeData(
          buttonColor: Colors.blueAccent,
          textTheme: ButtonTextTheme.primary,
        ),
      ),
      home: BluetoothScreen(),
    );
  }
}

class BluetoothScreen extends StatefulWidget {
  @override
  _BluetoothScreenState createState() => _BluetoothScreenState();
}

class _BluetoothScreenState extends State<BluetoothScreen> {
  BluetoothConnection? connection;
  List<BluetoothDevice> devices = [];
  bool isScanning = false;
  StillState state = StillState(
    mode: 'Idle',
    cube_temp: 0.0,
    column_temp: 0.0,
    tsa_temp: null,
    water_temp: 0.0,
    flow_rate: 0.0,
    total_flow: 0.0,
    pressure: 760.0,
    leak_detected: false,
    heating: false,
    servo_angle: 0,
  );
  List<double> cubeTempHistory = [];
  List<double> columnTempHistory = [];

  @override
  void initState() {
    super.initState();
    FlutterBluetoothSerial.instance.requestPermissions();
    scanDevices();
  }

  void scanDevices() async {
    setState(() => isScanning = true);
    devices = await FlutterBluetoothSerial.instance.getBondedDevices();
    FlutterBluetoothSerial.instance.startDiscovery().listen((result) {
      setState(() {
        if (!devices.contains(result.device)) {
          devices.add(result.device);
        }
      });
    }).onDone(() => setState(() => isScanning = false));
  }

  void connectToDevice(BluetoothDevice device) async {
    try {
      connection = await BluetoothConnection.toAddress(device.address);
      connection!.input.listen((data) {
        final jsonData = utf8.decode(data);
        try {
          final newState = StillState.fromJson(jsonDecode(jsonData));
          setState(() {
            state = newState;
            cubeTempHistory.add(newState.cube_temp);
            columnTempHistory.add(newState.column_temp);
            if (cubeTempHistory.length > 60) cubeTempHistory.removeAt(0);
            if (columnTempHistory.length > 60) columnTempHistory.removeAt(0);
          });
          if (newState.leak_detected || newState.water_temp > 40.0 || newState.flow_rate < 5.0) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Авария: протечка или перегрев!'),
                backgroundColor: Colors.red,
              ),
            );
          }
        } catch (e) {
          print('Ошибка парсинга состояния: $e');
        }
      });
      setState(() {});
    } catch (e) {
      print('Ошибка подключения: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка подключения: $e')),
      );
    }
  }

  void sendCommand(Map<String, dynamic> command) async {
    if (connection != null && connection!.isConnected) {
      connection!.output.add(utf8.encode(jsonEncode(command) + '\r\n'));
      await connection!.output.allSent;
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не подключено к устройству')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Still Controller'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: scanDevices,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Подключение к устройству',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: devices.length,
              itemBuilder: (context, index) {
                return Card(
                  margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    leading: Icon(MdiIcons.bluetooth),
                    title: Text(devices[index].name ?? 'Неизвестное устройство'),
                    subtitle: Text(devices[index].address),
                    onTap: () => connectToDevice(devices[index]),
                  ),
                );
              },
            ),
          ),
          if (isScanning) CircularProgressIndicator(),
          if (connection != null && connection!.isConnected)
            Expanded(
              child: MainScreen(
                state: state,
                cubeTempHistory: cubeTempHistory,
                columnTempHistory: columnTempHistory,
                sendCommand: sendCommand,
              ),
            ),
        ],
      ),
    );
  }
}

class MainScreen extends StatelessWidget {
  final StillState state;
  final List<double> cubeTempHistory;
  final List<double> columnTempHistory;
  final Function(Map<String, dynamic>) sendCommand;

  MainScreen({
    required this.state,
    required this.cubeTempHistory,
    required this.columnTempHistory,
    required this.sendCommand,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Управление самогонным аппаратом',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Text('Выберите режим:', style: TextStyle(fontSize: 18)),
            DropdownButton<String>(
              value: state.mode,
              isExpanded: true,
              items: [
                DropdownMenuItem(value: 'Idle', child: Text('Ожидание')),
                DropdownMenuItem(value: 'MashDistillation', child: Text('Перегон браги')),
                DropdownMenuItem(value: 'Rectification', child: Text('Ректификация')),
                DropdownMenuItem(value: 'Distillation', child: Text('Дистилляция')),
                DropdownMenuItem(value: 'Distiller', child: Text('Дистиллятор')),
                DropdownMenuItem(value: 'Calibration', child: Text('Настройки')),
              ],
              onChanged: (value) => sendCommand({'mode': value}),
            ),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  icon: Icon(MdiIcons.gauge),
                  label: Text('Статус'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => StateScreen(
                        state: state,
                        cubeTempHistory: cubeTempHistory,
                        columnTempHistory: columnTempHistory,
                      ),
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  icon: Icon(MdiIcons.fire),
                  label: Text('Перегон браги'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => MashDistillationScreen(state: state, sendCommand: sendCommand),
                    ),
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  icon: Icon(MdiIcons.filter),
                  label: Text('Ректификация'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => RectificationScreen(state: state, sendCommand: sendCommand),
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  icon: Icon(MdiIcons.bottleWine),
                  label: Text('Дистилляция'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => DistillationScreen(state: state, sendCommand: sendCommand),
                    ),
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  icon: Icon(MdiIcons.water),
                  label: Text('Дистиллятор'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => DistillerScreen(state: state, sendCommand: sendCommand),
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  icon: Icon(MdiIcons.cog),
                  label: Text('Настройки'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SettingsScreen(state: state, sendCommand: sendCommand),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class StateScreen extends StatelessWidget {
  final StillState state;
  final List<double> cubeTempHistory;
  final List<double> columnTempHistory;

  StateScreen({required this.state, required this.cubeTempHistory, required this.columnTempHistory});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Статус системы')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Температуры', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(show: true),
                  titlesData: FlTitlesData(show: true),
                  borderData: FlBorderData(show: true),
                  lineBarsData: [
                    LineChartBarData(
                      spots: cubeTempHistory.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList(),
                      isCurved: true,
                      colors: [Colors.blue],
                      barWidth: 2,
                      dotData: FlDotData(show: false),
                    ),
                    LineChartBarData(
                      spots: columnTempHistory.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList(),
                      isCurved: true,
                      colors: [Colors.green],
                      barWidth: 2,
                      dotData: FlDotData(show: false),
                    ),
                  ],
                  minX: 0,
                  maxX: cubeTempHistory.length.toDouble() - 1,
                  minY: 0,
                  maxY: 100,
                ),
              ),
            ),
            SizedBox(height: 16),
            ListTile(
              leading: Icon(MdiIcons.thermometer),
              title: Text('Температура куба: ${state.cube_temp.toStringAsFixed(1)}°C'),
            ),
            ListTile(
              leading: Icon(MdiIcons.thermometer),
              title: Text('Температура колонны: ${state.column_temp.toStringAsFixed(1)}°C'),
            ),
            ListTile(
              leading: Icon(MdiIcons.thermometer),
              title: Text('Температура ТСА: ${state.tsa_temp != null ? state.tsa_temp!.toStringAsFixed(1) : 'N/A'}°C'),
            ),
            ListTile(
              leading: Icon(MdiIcons.thermometer),
              title: Text('Температура воды: ${state.water_temp.toStringAsFixed(1)}°C'),
            ),
            ListTile(
              leading: Icon(MdiIcons.water),
              title: Text('Проток воды: ${state.flow_rate.toStringAsFixed(1)} мл/с'),
            ),
            ListTile(
              leading: Icon(MdiIcons.water),
              title: Text('Расход воды: ${state.total_flow.toStringAsFixed(2)} л'),
            ),
            ListTile(
              leading: Icon(MdiIcons.gauge),
              title: Text('Давление: ${state.pressure.toStringAsFixed(1)} мм.рт.ст.'),
            ),
            ListTile(
              leading: Icon(state.leak_detected ? MdiIcons.alert : MdiIcons.check),
              title: Text('Протечка: ${state.leak_detected ? 'Да' : 'Нет'}'),
            ),
            ListTile(
              leading: Icon(state.heating ? MdiIcons.fire : MdiIcons.fireOff),
              title: Text('Нагрев: ${state.heating ? 'Вкл' : 'Выкл'}'),
            ),
            ListTile(
              leading: Icon(MdiIcons.servo),
              title: Text('Угол сервопривода: ${state.servo_angle}°'),
            ),
          ],
        ),
      ),
    );
  }
}

class MashDistillationScreen extends StatelessWidget {
  final StillState state;
  final Function(Map<String, dynamic>) sendCommand;

  MashDistillationScreen({required this.state, required this.sendCommand});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Перегон браги')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: Duration(milliseconds: 300),
              child: ElevatedButton.icon(
                icon: Icon(state.heating ? MdiIcons.fireOff : MdiIcons.fire),
                label: Text(state.heating ? 'Выкл нагрев' : 'Вкл нагрев'),
                style: ElevatedButton.styleFrom(
                  primary: state.heating ? Colors.red : Colors.green,
                ),
                onPressed: () => sendCommand({'heating': !state.heating}),
              ),
            ),
            SizedBox(height: 16),
            ElevatedButton.icon(
              icon: Icon(MdiIcons.stop),
              label: Text('Аварийная остановка'),
              style: ElevatedButton.styleFrom(primary: Colors.red),
              onPressed: () => sendCommand({'mode': 'Idle', 'heating': false, 'servo_angle': 0}),
            ),
            SizedBox(height: 16),
            StateScreen(state: state, cubeTempHistory: [], columnTempHistory: []),
          ],
        ),
      ),
    );
  }
}

class RectificationScreen extends StatefulWidget {
  final StillState state;
  final Function(Map<String, dynamic>) sendCommand;

  RectificationScreen({required this.state, required this.sendCommand});

  @override
  _RectificationScreenState createState() => _RectificationScreenState();
}

class _RectificationScreenState extends State<RectificationScreen> {
  final TextEditingController servoController = TextEditingController();
  final TextEditingController volumeController = TextEditingController();
  final TextEditingController strengthController = TextEditingController();
  Fractions? fractions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Ректификация')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton.icon(
              icon: Icon(MdiIcons.play),
              label: Text('Старт'),
              onPressed: () => widget.sendCommand({'baseline': true}),
            ),
            SizedBox(height: 8),
            ElevatedButton.icon(
              icon: Icon(MdiIcons.filter),
              label: Text('Отбор голов'),
              onPressed: () => widget.sendCommand({'angle': 'heads'}),
            ),
            SizedBox(height: 8),
            ElevatedButton.icon(
              icon: Icon(MdiIcons.bottleWine),
              label: Text('Отбор тела'),
              onPressed: () => widget.sendCommand({'angle': 'body'}),
            ),
            SizedBox(height: 8),
            ElevatedButton.icon(
              icon: Icon(MdiIcons.stop),
              label: Text('Аварийная остановка'),
              style: ElevatedButton.styleFrom(primary: Colors.red),
              onPressed: () => widget.sendCommand({'mode': 'Idle', 'heating': false, 'servo_angle': 0}),
            ),
            SizedBox(height: 16),
            TextField(
              controller: servoController,
              decoration: InputDecoration(
                labelText: 'Коррекция сервопривода (%)',
                prefixIcon: Icon(MdiIcons.servo),
                errorText: servoController.text.isNotEmpty && double.tryParse(servoController.text) == null
                    ? 'Введите число'
           