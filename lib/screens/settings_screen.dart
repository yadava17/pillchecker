import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final NotificationService _notificationService = NotificationService.instance;
  bool _notificationsEnabled = true;
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;
  TimeOfDay _quietHoursStart = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _quietHoursEnd = const TimeOfDay(hour: 7, minute: 0);
  bool _quietHoursEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
      _soundEnabled = prefs.getBool('sound_enabled') ?? true;
      _vibrationEnabled = prefs.getBool('vibration_enabled') ?? true;
      _quietHoursEnabled = prefs.getBool('quiet_hours_enabled') ?? false;

      final startHour = prefs.getInt('quiet_hours_start_hour') ?? 22;
      final startMinute = prefs.getInt('quiet_hours_start_minute') ?? 0;
      _quietHoursStart = TimeOfDay(hour: startHour, minute: startMinute);

      final endHour = prefs.getInt('quiet_hours_end_hour') ?? 7;
      final endMinute = prefs.getInt('quiet_hours_end_minute') ?? 0;
      _quietHoursEnd = TimeOfDay(hour: endHour, minute: endMinute);
    });
  }

  Future<void> _saveSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    }
  }

  Future<void> _selectQuietHoursStart() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _quietHoursStart,
    );
    if (picked != null) {
      setState(() => _quietHoursStart = picked);
      await _saveSetting('quiet_hours_start_hour', picked.hour);
      await _saveSetting('quiet_hours_start_minute', picked.minute);
    }
  }

  Future<void> _selectQuietHoursEnd() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _quietHoursEnd,
    );
    if (picked != null) {
      setState(() => _quietHoursEnd = picked);
      await _saveSetting('quiet_hours_end_hour', picked.hour);
      await _saveSetting('quiet_hours_end_minute', picked.minute);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Notifications',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.teal,
              ),
            ),
          ),
          SwitchListTile(
            title: const Text('Enable Notifications', style: TextStyle(fontSize: 16)),
            subtitle: const Text('Receive reminders for your medications'),
            value: _notificationsEnabled,
            onChanged: (value) {
              setState(() => _notificationsEnabled = value);
              _saveSetting('notifications_enabled', value);
              if (!value) {
                _notificationService.cancelAllNotifications();
              }
            },
            activeThumbColor: Colors.teal,
          ),
          SwitchListTile(
            title: const Text('Sound', style: TextStyle(fontSize: 16)),
            subtitle: const Text('Play sound with notifications'),
            value: _soundEnabled,
            onChanged: _notificationsEnabled
                ? (value) {
                    setState(() => _soundEnabled = value);
                    _saveSetting('sound_enabled', value);
                  }
                : null,
            activeThumbColor: Colors.teal,
          ),
          SwitchListTile(
            title: const Text('Vibration', style: TextStyle(fontSize: 16)),
            subtitle: const Text('Vibrate on notification'),
            value: _vibrationEnabled,
            onChanged: _notificationsEnabled
                ? (value) {
                    setState(() => _vibrationEnabled = value);
                    _saveSetting('vibration_enabled', value);
                  }
                : null,
            activeThumbColor: Colors.teal,
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('Quiet Hours', style: TextStyle(fontSize: 16)),
            subtitle: const Text('No notifications during specified hours'),
            value: _quietHoursEnabled,
            onChanged: (value) {
              setState(() => _quietHoursEnabled = value);
              _saveSetting('quiet_hours_enabled', value);
            },
            activeThumbColor: Colors.teal,
          ),
          if (_quietHoursEnabled) ...[
            ListTile(
              title: const Text('Start Time', style: TextStyle(fontSize: 16)),
              subtitle: Text(_quietHoursStart.format(context)),
              trailing: const Icon(Icons.access_time),
              onTap: _selectQuietHoursStart,
            ),
            ListTile(
              title: const Text('End Time', style: TextStyle(fontSize: 16)),
              subtitle: Text(_quietHoursEnd.format(context)),
              trailing: const Icon(Icons.access_time),
              onTap: _selectQuietHoursEnd,
            ),
          ],
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'About',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.teal,
              ),
            ),
          ),
          const ListTile(
            title: Text('Version', style: TextStyle(fontSize: 16)),
            subtitle: Text('1.0.0'),
            leading: Icon(Icons.info_outline),
          ),
          ListTile(
            title: const Text('About PillChecker', style: TextStyle(fontSize: 16)),
            subtitle: const Text('Medication management and tracking app'),
            leading: const Icon(Icons.medical_information),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'PillChecker',
                applicationVersion: '1.0.0',
                applicationIcon: const Icon(
                  Icons.medication,
                  size: 48,
                  color: Colors.teal,
                ),
                children: [
                  const Text(
                    'PillChecker helps you safely manage and track your medications with reminders, adherence tracking, and history logs.',
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
