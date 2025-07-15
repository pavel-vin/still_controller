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
                    : null,
              ),
              keyboardType: TextInputType.number,
              onSubmitted: (value) {
                final percent = double.tryParse(value);
                if (percent != null && percent >= -100 && percent <= 100) {
                  widget.sendCommand({'percent': percent});
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Введите значение от -100 до 100')),
                  );
                }
              },
            ),
            SizedBox(height: 16),
            TextField(
              controller: volumeController,
              decoration: InputDecoration(
                labelText: 'Объём (л)',
                prefixIcon: Icon(MdiIcons.cup),
                errorText: volumeController.text.isNotEmpty && double.tryParse(volumeController.text) == null
                    ? 'Введите число'
                    : null,
              ),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: strengthController,
              decoration: InputDecoration(
                labelText: 'Крепость (%)',
                prefixIcon: Icon(MdiIcons.percent),
                errorText: strengthController.text.isNotEmpty && double.tryParse(strengthController.text) == null
                    ? 'Введите число'
                    : null,
              ),
              keyboardType: TextInputType.number,
            ),
            SizedBox(height: 8),
            ElevatedButton.icon(
              icon: Icon(MdiIcons.calculator),
              label: Text('Рассчитать фракции'),
              onPressed: () {
                final volume = double.tryParse(volumeController.text) ?? 0.0;
                final strength = double.tryParse(strengthController.text) ?? 0.0;
                if (volume > 0 && strength > 0 && strength <= 100) {
                  setState(() {
                    fractions = Fractions(
                      heads: volume * strength / 100.0 * 0.1,
                      body: volume * strength / 100.0 * 0.8,
                      tails: volume * (1 - strength / 100.0),
                    );
                  });
                  widget.sendCommand({
                    'volume': volume,
                    'strength': strength,
                  });
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Введите корректный объём и крепость')),
                  );
                }
              },
            ),
            if (fractions != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text(
                  'Фракции: головы=${fractions!.heads.toStringAsFixed(2)}л, тело=${fractions!.body.toStringAsFixed(2)}л, хвосты=${fractions!.tails.toStringAsFixed(2)}л',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            SizedBox(height: 16),
            StateScreen(state: widget.state, cubeTempHistory: [], columnTempHistory: []),
          ],
        ),
      ),
    );
  }
}

class DistillationScreen extends State<DistillationScreen> {
  final StillState state;
  final Function(Map<String, dynamic>) sendCommand;

  DistillationScreen({required this.state, required this.sendCommand});

  @override
  _DistillationScreenState createState() => _DistillationScreenState();
}

class _DistillationScreenState extends State<DistillationScreen> {
  final TextEditingController deltaController = TextEditingController();
  final TextEditingController servoController = TextEditingController();
  final TextEditingController volumeController = TextEditingController();
  final TextEditingController strengthController = TextEditingController();
  Fractions? fractions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Дистилляция')),
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
              controller: deltaController,
              decoration: InputDecoration(
                labelText: 'Дельта температуры (°C)',
                prefixIcon: Icon(MdiIcons.thermometer),
                errorText: deltaController.text.isNotEmpty && double.tryParse(deltaController.text) == null
                    ? 'Введите число'
                    : null,
              ),
              keyboardType: TextInputType.number,
              onSubmitted: (value) {
                final delta = double.tryParse(value);
                if (delta != null && delta >= 0) {
                  widget.sendCommand({'config': {'temp_delta': delta}});
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Введите корректное значение')),
                  );
                }
              },
            ),
            TextField(
              controller: servoController,
              decoration: InputDecoration(
                labelText: 'Коррекция сервопривода (%)',
                prefixIcon: Icon(MdiIcons.servo),
                errorText: servoController.text.isNotEmpty && double.tryParse(servoController.text) == null
                    ? 'Введите число'
                    : null,
              ),
              keyboardType: TextInputType.number,
              onSubmitted: (value) {
                final percent = double.tryParse(value);
                if (percent != null && percent >= -100 && percent <= 100) {
                  widget.sendCommand({'percent': percent});
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Введите значение от -100 до 100')),
                  );
                }
              },
            ),
            SizedBox(height: 16),
            TextField(
              controller: volumeController,
              decoration: InputDecoration(
                labelText: 'Объём (л)',
                prefixIcon: Icon(MdiIcons.cup),
                errorText: volumeController.text.isNotEmpty && double.tryParse(volumeController.text) == null
                    ? 'Введите число'
                    : null,
              ),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: strengthController,
              decoration: InputDecoration(
                labelText: 'Крепость (%)',
                prefixIcon: Icon(MdiIcons.percent),
                errorText: strengthController.text.isNotEmpty && double.tryParse(strengthController.text) == null
                    ? 'Введите число'
                    : null,
              ),
              keyboardType: TextInputType.number,
            ),
            SizedBox(height: 8),
            ElevatedButton.icon(
              icon: Icon(MdiIcons.calculator),
              label: Text('Рассчитать фракции'),
              onPressed: () {
                final volume = double.tryParse(volumeController.text) ?? 0.0;
                final strength = double.tryParse(strengthController.text) ?? 0.0;
                if (volume > 0 && strength > 0 && strength <= 100) {
                  setState(() {
                    fractions = Fractions(
                      heads: volume * strength / 100.0 * 0.1,
                      body: volume * strength / 100.0 * 0.8,
                      tails: volume * (1 - strength / 100.0),
                    );
                  });
                  widget.sendCommand({
                    'volume': volume,
                    'strength': strength,
                  });
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Введите корректный объём и крепость')),
                  );
                }
              },
            ),
            if (fractions != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text(
                  'Фракции: головы=${fractions!.heads.toStringAsFixed(2)}л, тело=${fractions!.body.toStringAsFixed(2)}л, хвосты=${fractions!.tails.toStringAsFixed(2)}л',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            SizedBox(height: 16),
            StateScreen(state: widget.state, cubeTempHistory: [], columnTempHistory: []),
          ],
        ),
      ),
    );
  }
}

class DistillerScreen extends StatefulWidget {
  final StillState state;
  final Function(Map<String, dynamic>) sendCommand;

  DistillerScreen({required this.state, required this.sendCommand});

  @override
  _DistillerScreenState createState() => _DistillerScreenState();
}

class _DistillerScreenState extends State<DistillerScreen> {
  final TextEditingController volumeController = TextEditingController();
  final TextEditingController strengthController = TextEditingController();
  Fractions? fractions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Дистиллятор')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: Duration(milliseconds: 300),
              child: ElevatedButton.icon(
                icon: Icon(widget.state.heating ? MdiIcons.fireOff : MdiIcons.fire),
                label: Text(widget.state.heating ? 'Выкл нагрев' : 'Вкл нагрев'),
                style: ElevatedButton.styleFrom(
                  primary: widget.state.heating ? Colors.red : Colors.green,
                ),
                onPressed: () => widget.sendCommand({'heating': !widget.state.heating}),
              ),
            ),
            SizedBox(height: 8),
            ElevatedButton.icon(
              icon: Icon(MdiIcons.play),
              label: Text('Начать отбор'),
              onPressed: () => widget.sendCommand({'angle': 'body'}),
            ),
            SizedBox(height: 8),
            ElevatedButton.icon(
              icon: Icon(MdiIcons.stop),
              label: Text('Конец отбора'),
              onPressed: () => widget.sendCommand({'angle': 0}),
            ),
            SizedBox(height: 16),
            TextField(
              controller: volumeController,
              decoration: InputDecoration(
                labelText: 'Объём (л)',
                prefixIcon: Icon(MdiIcons.cup),
                errorText: volumeController.text.isNotEmpty && double.tryParse(volumeController.text) == null
                    ? 'Введите число'
                    : null,
              ),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: strengthController,
              decoration: InputDecoration(
                labelText: 'Крепость (%)',
                prefixIcon: Icon(MdiIcons.percent),
                errorText: strengthController.text.isNotEmpty && double.tryParse(strengthController.text) == null
                    ? 'Введите число'
                    : null,
              ),
              keyboardType: TextInputType.number,
            ),
            SizedBox(height: 8),
            ElevatedButton.icon(
              icon: Icon(MdiIcons.calculator),
              label: Text('Рассчитать фракции'),
              onPressed: () {
                final volume = double.tryParse(volumeController.text) ?? 0.0;
                final strength = double.tryParse(strengthController.text) ?? 0.0;
                if (volume > 0 && strength > 0 && strength <= 100) {
                  setState(() {
                    fractions = Fractions(
                      heads: volume * strength / 100.0 * 0.1,
                      body: volume * strength / 100.0 * 0.8,
                      tails: volume * (1 - strength / 100.0),
                    );
                  });
                  widget.sendCommand({
                    'volume': volume,
                    'strength': strength,
                  });
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Введите корректный объём и крепость')),
                  );
                }
              },
            ),
            if (fractions != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text(
                  'Фракции: головы=${fractions!.heads.toStringAsFixed(2)}л, тело=${fractions!.body.toStringAsFixed(2)}л, хвосты=${fractions!.tails.toStringAsFixed(2)}л',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            SizedBox(height: 16),
            StateScreen(state: widget.state, cubeTempHistory: [], columnTempHistory: []),
          ],
        ),
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  final StillState state;
  final Function(Map<String, dynamic>) sendCommand;

  SettingsScreen({required this.state, required this.sendCommand});

  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController cubeOffsetController = TextEditingController();
  final TextEditingController columnOffsetController = TextEditingController();
  final TextEditingController tsaOffsetController = TextEditingController();
  final TextEditingController waterOffsetController = TextEditingController();
  final TextEditingController flowPulsesController = TextEditingController();
  final TextEditingController headsAngleController = TextEditingController();
  final TextEditingController bodyAngleController = TextEditingController();
  final TextEditingController servoStepController = TextEditingController();
  final TextEditingController pidKpController = TextEditingController();
  final TextEditingController pidKiController = TextEditingController();
  final TextEditingController pidKdController = TextEditingController();
  List<String> sensorIds = ['28-000001', '28-000002', '28-000003', '28-000004'];
  String? cubeSensorId;
  String? columnSensorId;
  String? tsaSensorId;
  String? waterSensorId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Настройки')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Калибровка датчиков температуры', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ListTile(
              leading: Icon(MdiIcons.thermometer),
              title: Text('Температура куба: ${widget.state.cube_temp.toStringAsFixed(1)}°C'),
            ),
            DropdownButton<String>(
              hint: Text('Выберите датчик'),
              value: cubeSensorId,
              isExpanded: true,
              items: sensorIds.map((id) => DropdownMenuItem(value: id, child: Text(id))).toList(),
              onChanged: (value) => setState(() => cubeSensorId = value),
            ),
            TextField(
              controller: cubeOffsetController,
              decoration: InputDecoration(
                labelText: 'Смещение (°C)',
                prefixIcon: Icon(MdiIcons.thermometer),
                errorText: cubeOffsetController.text.isNotEmpty && double.tryParse(cubeOffsetController.text) == null
                    ? 'Введите число'
                    : null,
              ),
              keyboardType: TextInputType.number,
            ),
            ElevatedButton.icon(
              icon: Icon(MdiIcons.check),
              label: Text('Калибровать'),
              onPressed: () {
                final offset = double.tryParse(cubeOffsetController.text);
                if (offset != null && cubeSensorId != null) {
                  widget.sendCommand({
                    'calibrate': {'sensor': 'cube', 'offset': offset, 'sensor_id': cubeSensorId}
                  });
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Выберите датчик и введите корректное смещение')),
                  );
                }
              },
            ),
            ListTile(
              leading: Icon(MdiIcons.thermometer),
              title: Text('Температура колонны: ${widget.state.column_temp.toStringAsFixed(1)}°C'),
            ),
            DropdownButton<String>(
              hint: Text('Выберите датчик'),
              value: columnSensorId,
              isExpanded: true,
              items: sensorIds.map((id) => DropdownMenuItem(value: id, child: Text(id))).toList(),
              onChanged: (value) => setState(() => columnSensorId = value),
            ),
            TextField(
              controller: columnOffsetController,
              decoration: InputDecoration(
                labelText: 'Смещение (°C)',
                prefixIcon: Icon(MdiIcons.thermometer),
                errorText: columnOffsetController.text.isNotEmpty && double.tryParse(columnOffsetController.text) == null
                    ? 'Введите число'
                    : null,
              ),
              keyboardType: TextInputType.number,
            ),
            ElevatedButton.icon(
              icon: Icon(MdiIcons.check),
              label: Text('Калибровать'),
              onPressed: () {
                final offset = double.tryParse(columnOffsetController.text);
                if (offset != null && columnSensorId != null) {
                  widget.sendCommand({
                    'calibrate': {'sensor': 'column', 'offset': offset, 'sensor_id': columnSensorId}
                  });
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Выберите датчик и введите корректное смещение')),
                  );
                }
              },
            ),
            ListTile(
              leading: Icon(MdiIcons.thermometer),
              title: Text('Температура ТСА: ${widget.state.tsa_temp != null ? widget.state.tsa_temp!.toStringAsFixed(1) : 'N/A'}°C'),
            ),
            DropdownButton<String>(
              hint: Text('Выберите датчик'),
              value: tsaSensorId,
              isExpanded: true,
              items: sensorIds.map((id) => DropdownMenuItem(value: id, child: Text(id))).toList(),
              onChanged: (value) => setState(() => tsaSensorId = value),
            ),
            TextField(
              controller: tsaOffsetController,
              decoration: InputDecoration(
                labelText: 'Смещение (°C)',
                prefixIcon: Icon(MdiIcons.thermometer),
                errorText: tsaOffsetController.text.isNotEmpty && double.tryParse(tsaOffsetController.text) == null
                    ? 'Введите число'
                    : null,
              ),
              keyboardType: TextInputType.number,
            ),
            ElevatedButton.icon(
              icon: Icon(MdiIcons.check),
              label: Text('Калибровать'),
              onPressed: () {
                final offset = double.tryParse(tsaOffsetController.text);
                if (offset != null && tsaSensorId != null) {
                  widget.sendCommand({
                    'calibrate': {'sensor': 'tsa', 'offset': offset, 'sensor_id': tsaSensorId}
                  });
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Выберите датчик и введите корректное смещение')),
                  );
                }
              },
            ),
            ListTile(
              leading: Icon(MdiIcons.thermometer),
              title: Text('Температура воды: ${widget.state.water_temp.toStringAsFixed(1)}°C'),
            ),
            DropdownButton<String>(
              hint: Text('Выберите датчик'),
              value: waterSensorId,
              isExpanded: true,
              items: sensorIds.map((id) => DropdownMenuItem(value: id, child: Text(id))).toList(),
              onChanged: (value) => setState(() => waterSensorId = value),
            ),
            TextField(
              controller: waterOffsetController,
              decoration: InputDecoration(
                labelText: 'Смещение (°C)',
                prefixIcon: Icon(MdiIcons.thermometer),
                errorText: waterOffsetController.text.isNotEmpty && double.tryParse(waterOffsetController.text) == null
                    ? 'Введите число'
                    : null,
              ),
              keyboardType: TextInputType.number,
            ),
            ElevatedButton.icon(
              icon: Icon(MdiIcons.check),
              label: Text('Калибровать'),
              onPressed: () {
                final offset = double.tryParse(waterOffsetController.text);
                if (offset != null && waterSensorId != null) {
                  widget.sendCommand({
                    'calibrate': {'sensor': 'water', 'offset': offset, 'sensor_id': waterSensorId}
                  });
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Выберите датчик и введите корректное смещение')),
                  );
                }
              },
            ),
            SizedBox(height: 16),
            ElevatedButton.icon(
              icon: Icon(MdiIcons.refresh),
              label: Text('Обновить список датчиков'),
              onPressed: () {
                // Здесь должен быть запрос к устройству для обновления sensorIds
                // Пока используем статический список
              },
            ),
            SizedBox(height: 16),
            Text('Калибровка протока воды', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            TextField(
              controller: flowPulsesController,
              decoration: InputDecoration(
                labelText: 'Импульсов на литр',
                prefixIcon: Icon(MdiIcons.water),
                errorText: flowPulsesController.text.isNotEmpty && double.tryParse(flowPulsesController.text) == null
                    ? 'Введите число'
                    : null,
              ),
              keyboardType: TextInputType.number,
            ),
            ElevatedButton.icon(
              icon: Icon(MdiIcons.check),
              label: Text('Сохранить'),
              onPressed: () {
                final pulses = double.tryParse(flowPulsesController.text);
                if (pulses != null && pulses > 0) {
                  widget.sendCommand({'config': {'flow_pulses_per_liter': pulses}});
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Введите корректное значение')),
                  );
                }
              },
            ),
            SizedBox(height: 16),
            Text('Калибровка сервопривода', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ListTile(
              leading: Icon(MdiIcons.servo),
              title: Text('Текущий угол: ${widget.state.servo_angle}°'),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  icon: Icon(MdiIcons.plus),
                  label: Text('+1°'),
                  onPressed: () => widget.sendCommand({'delta': 1}),
                ),
                ElevatedButton.icon(
                  icon: Icon(MdiIcons.minus),
                  label: Text('-1°'),
                  onPressed: () => widget.sendCommand({'delta': -1}),
                ),
              ],
            ),
            TextField(
              controller: headsAngleController,
              decoration: InputDecoration(
                labelText: 'Угол для голов (100 мл/ч)',
                prefixIcon: Icon(MdiIcons.servo),
                errorText: headsAngleController.text.isNotEmpty && int.tryParse(headsAngleController.text) == null
                    ? 'Введите целое число'
                    : null,
              ),
              keyboardType: TextInputType.number,
            ),
            ElevatedButton.icon(
              icon: Icon(MdiIcons.check),
              label: Text('Сохранить'),
              onPressed: () {
                final angle = int.tryParse(headsAngleController.text);
                if (angle != null && angle >= 0 && angle <= 89) {
                  widget.sendCommand({'config': {'heads_servo_angle': angle}});
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Введите угол от 0 до 89')),
                  );
                }
              },
            ),
            TextField(
              controller: bodyAngleController,
              decoration: InputDecoration(
                labelText: 'Угол для тела (1500 мл/ч)',
                prefixIcon: Icon(MdiIcons.servo),
                errorText: bodyAngleController.text.isNotEmpty && int.tryParse(bodyAngleController.text) == null
                    ? 'Введите целое число'
                    : null,
              ),
              keyboardType: TextInputType.number,
            ),
            ElevatedButton.icon(
              icon: Icon(MdiIcons.check),
              label: Text('Сохранить'),
              onPressed: () {
                final angle = int.tryParse(bodyAngleController.text);
                if (angle != null && angle >= 0 && angle <= 89) {
                  widget.sendCommand({'config': {'body_servo_angle': angle}});
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Введите угол от 0 до 89')),
                  );
                }
              },
            ),
            TextField(
              controller: servoStepController,
              decoration: InputDecoration(
                labelText: 'Шаг уменьшения угла (°C)',
                prefixIcon: Icon(MdiIcons.servo),
                errorText: servoStepController.text.isNotEmpty && int.tryParse(servoStepController.text) == null
                    ? 'Введите целое число'
                    : null,
              ),
              keyboardType: TextInputType.number,
            ),
            ElevatedButton.icon(
              icon: Icon(MdiIcons.check),
              label: Text('Сохранить'),
              onPressed: () {
                final step = int.tryParse(servoStepController.text);
                if (step != null && step > 0) {
                  widget.sendCommand({'config': {'servo_step': step}});
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Введите корректное значение')),
                  );
                }
              },
            ),
            SizedBox(height: 16),
            Text('Настройки PID', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            TextField(
              controller: pidKpController,
              decoration: InputDecoration(
                labelText: 'Kp (PID)',
                prefixIcon: Icon(MdiIcons.tune),
                errorText: pidKpController.text.isNotEmpty && double.tryParse(pidKpController.text) == null
                    ? 'Введите число'
                    : null,
              ),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: pidKiController,
              decoration: InputDecoration(
                labelText: 'Ki (PID)',
                prefixIcon: Icon(MdiIcons.tune),
                errorText: pidKiController.text.isNotEmpty && double.tryParse(pidKiController.text) == null
                    ? 'Введите число'
                    : null,
              ),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: pidKdController,
              decoration: InputDecoration(
                labelText: 'Kd (PID)',
                prefixIcon: Icon(MdiIcons.tune),
                errorText: pidKdController.text.isNotEmpty && double.tryParse(pidKdController.text) == null
                    ? 'Введите число'
                    : null,
              ),
              keyboardType: TextInputType.number,
            ),
            ElevatedButton.icon(
              icon: Icon(MdiIcons.check),
              label: Text('Сохранить PID'),
              onPressed: () {
                final kp = double.tryParse(pidKpController.text);
                final ki = double.tryParse(pidKiController.text);
                final kd = double.tryParse(pidKdController.text);
                if (kp != null && ki != null && kd != null) {
                  widget.sendCommand({
                    'config': {
                      'pid_kp': kp,
                      'pid_ki': ki,
                      'pid_kd': kd,
                      'use_pid': true,
                    }
                  });
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Введите корректные значения PID')),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

// Код для генерации JSON-сериализации (выполнить: flutter pub run build_runner build)
part 'main.g.dart';