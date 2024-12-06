import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:front/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';


final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

class SettingsScreen extends StatefulWidget {
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final String userId = FirebaseAuth.instance.currentUser!.uid;

  bool _isNotificationEnabled = false; // 알림 활성화 여부
  bool isNearBudgetAlertEnabled = false;
  bool isOverBudgetAlertEnabled = false;
  double nearBudgetThreshold = 80; // 기본적으로 80% 설정
  List<String> friends = []; // 친구 목록을 저장하는 배열


  @override
  void initState() {
    super.initState();
    _loadNotificationPreference(); // 알림 설정 불러오기
    _loadSettings();
  }

  /// 알림 설정 불러오기
  Future<void> _loadNotificationPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _isNotificationEnabled = prefs.getBool('notificationsEnabled') ?? false;
      });
    } catch (e) {
      print('Failed to load notification preference: $e');
    }
  }

  /// 알림 설정 저장
  Future<void> _saveNotificationPreference(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notificationsEnabled', value);
    setState(() {
      _isNotificationEnabled = value;
    });

    // 알림 활성화/비활성화에 따른 처리
    if (value) {
      // 알림 활성화 시 필요한 설정 추가 가능
      _showSnackbar('알림이 활성화되었습니다.');

      setState(() {
        isNearBudgetAlertEnabled = true; // 근접 알림 비활성화
        isOverBudgetAlertEnabled = true; // 초과 알림 비활성화
      });
      await _saveSettings(); // 업데이트된 상태를 Firestore에 저장

      await requestNotificationPermission();
    } else {
      // 알림 비활성화 시 모든 알림 취소 및 개별 알림 비활성화
      await flutterLocalNotificationsPlugin.cancelAll();
      setState(() {
        isNearBudgetAlertEnabled = false; // 근접 알림 비활성화
        isOverBudgetAlertEnabled = false; // 초과 알림 비활성화
      });
      await _saveSettings(); // 업데이트된 상태를 Firestore에 저장
      _showSnackbar('알림이 비활성화되었습니다.');
    }
  }

  Future<void> _loadSettings() async {
    try {
      final docRef = FirebaseFirestore.instance.collection('users').doc(userId);
      final docSnapshot = await docRef.get();

      if (docSnapshot.exists) {
        final settings = docSnapshot.data();
        setState(() {
          isNearBudgetAlertEnabled = settings?['near_budget_alert'] ?? false;
          isOverBudgetAlertEnabled = settings?['over_budget_alert'] ?? false;
          nearBudgetThreshold = (settings?['near_budget_threshold'] ?? 80).toDouble();

          // friends 필드가 배열인지 확인
          if (settings?['friends'] is List) {
            friends = List<String>.from(settings?['friends']);
          } else {
            friends = []; // friends 필드가 배열이 아니면 빈 배열로 초기화
          }
        });

        // friends 필드가 없거나 빈 배열인 경우 초기값 추가
        if (friends.isEmpty) {
          final initialFriend = '$userId#내 정보';
          friends = [initialFriend];
          await docRef.set({
            'friends': friends,
          }, SetOptions(merge: true));
        }
      } else {
        // 문서가 없는 경우 기본값으로 새 문서 생성
        await docRef.set({
          'near_budget_alert': false,
          'over_budget_alert': false,
          'near_budget_threshold': 80.0,
          'friends': ['$userId#내 정보'], // friends 배열에 "1@1" 추가
        });
        setState(() {
          isNearBudgetAlertEnabled = false;
          isOverBudgetAlertEnabled = true;
          nearBudgetThreshold = 80.0;
          friends = ["'$userId#내 정보'"];
        });
      }
    } catch (e) {
      print('Failed to load settings: $e');
    }
  }



  Future<void> _saveSettings() async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .set({
      'near_budget_alert': isNearBudgetAlertEnabled,
      'over_budget_alert': isOverBudgetAlertEnabled,
      'near_budget_threshold': nearBudgetThreshold,
    }, SetOptions(merge: true));
  }


  Future<void> requestNotificationPermission() async {
    final status = await Permission.notification.request();
    if (status.isGranted) {
      print('Notification permission granted');
    } else {
      print('Notification permission denied');
    }
  }

  /// 알림 설정 시 피드백 메시지 표시
  void _showSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false); // '/login' 경로로 이동
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text("설정"),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "테마 설정",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            SwitchListTile(
              title: Text("다크 모드"),
              value: themeProvider.themeMode == ThemeMode.dark,
              onChanged: (bool value) {
                themeProvider.toggleTheme();
              },
            ),
            Divider(), // 구분선 추가

            // 예산 알림 설정
            Text(
              "예산 알림 설정",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            SwitchListTile(
              title: Text("예산 근접 알림"),
              subtitle: Text("지출액이 예산의 $nearBudgetThreshold% 이상이 되면 알림을 보냅니다."),
              value: isNearBudgetAlertEnabled,
              onChanged: (bool value) {
                setState(() {
                  isNearBudgetAlertEnabled = value;
                });
                _saveSettings();
              },
            ),
            if (isNearBudgetAlertEnabled)
              Slider(
                value: nearBudgetThreshold,
                min: 50,
                max: 100,
                divisions: 10,
                label: "${nearBudgetThreshold.toInt()}%",
                onChanged: (double value) {
                  setState(() {
                    nearBudgetThreshold = value;
                  });
                  _saveSettings();
                },
              ),
            SwitchListTile(
              title: Text("예산 초과 알림"),
              subtitle: Text("지출액이 예산을 초과하면 알림을 보냅니다."),
              value: isOverBudgetAlertEnabled,
              onChanged: (bool value) {
                setState(() {
                  isOverBudgetAlertEnabled = value;
                });
                _saveSettings();
              },
            ),
            Spacer(),
            Align(
              alignment: Alignment.bottomRight,
              child: ElevatedButton(
                onPressed: _logout,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey[800]
                      : Colors.grey[300],
                  foregroundColor: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black,
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text("로그아웃"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}