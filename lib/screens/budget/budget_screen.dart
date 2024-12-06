import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:front/screens/transaction/transaction_screen.dart';

class BudgetScreen extends StatefulWidget {
  @override
  _BudgetScreenState createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  bool _isCalendarView = false;
  Map<DateTime, Map<String, bool>> _markers = {}; // 날짜별로 수입, 지출 여부 저장

  int totalIncome = 0;
  int totalExpense = 0;

  String? userId;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _initializeUserId();
    _fetchTransactionMarkers();
  }

  // Firebase에서 userId 가져오기
  Future<void> _initializeUserId() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacementNamed(context, '/login');
      });
    } else {
      setState(() {
        userId = user.uid;
      });
      _calculateMonthlyTotals();
    }
  }

  // Firestore에서 수입/지출 내역을 가져와 날짜별 마커 데이터 설정
  Future<void> _fetchTransactionMarkers() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print('No user logged in');
      return;
    }
    final transactions = await _firestore
        .collection('transactions')
        .where('userId', isEqualTo: user.uid)
        .get();
    Map<DateTime, Map<String, bool>> markers = {};
    for (var doc in transactions.docs) {
      final data = doc.data();
      print('Transaction Data: $data'); // 데이터 출력
      final date = (data['date'] as Timestamp).toDate();
      final day = DateTime.utc(date.year, date.month, date.day); // 날짜 표준화
      markers.putIfAbsent(day, () => {'income': false, 'expense': false});
      if (data['type'] == 'income') {
        markers[day]!['income'] = true;
      }
      if (data['type'] == 'expense') {
        markers[day]!['expense'] = true;
      }
    }
    print('Markers after fetching: $markers'); // 최종 결과 출력
    setState(() {
      _markers = markers;
    });
  }

  Stream<QuerySnapshot> _getTransactions(DateTime start, DateTime end) {
    if (userId == null) {
      return const Stream.empty(); // userId가 null이면 빈 스트림 반환
    }

    return _firestore
        .collection('transactions')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThan: Timestamp.fromDate(end))
        .where('userId', isEqualTo: userId) // userId 조건 추가
        .orderBy('date', descending: true) // 날짜 기준 내림차순 정렬
        .snapshots();
  }

  void _toggleView() {
    setState(() {
      _isCalendarView = !_isCalendarView;
    });
  }

  void _previousMonth() {
    if (!_isCalendarView) {
      setState(() {
        _focusedDay = DateTime(_focusedDay.year, _focusedDay.month - 1, 1);
      });
      _calculateMonthlyTotals();
    }
  }

  void _nextMonth() {
    if (!_isCalendarView) {
      setState(() {
        _focusedDay = DateTime(_focusedDay.year, _focusedDay.month + 1, 1);
      });
      _calculateMonthlyTotals();
    }
  }

  void _calculateMonthlyTotals() async {
    if (userId == null) return;

    final startOfMonth = DateTime(_focusedDay.year, _focusedDay.month, 1);
    final endOfMonth = DateTime(_focusedDay.year, _focusedDay.month + 1, 0);

    final transactions = await _firestore
        .collection('transactions')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
        .where('date', isLessThan: Timestamp.fromDate(endOfMonth))
        .where('userId', isEqualTo: userId) // userId 조건 추가
        .get();

    double income = 0;
    double expense = 0;

    for (var doc in transactions.docs) {
      final type = doc['type'];
      final amount = doc['amount'];
      if (type == 'income') {
        income += amount;
      } else if (type == 'expense') {
        expense += amount;
      }
    }

    setState(() {
      totalIncome = income.toInt();
      totalExpense = expense.toInt();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.bodyLarge;

    if (userId == null) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text("가계부"),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(_isCalendarView ? Icons.list : Icons.calendar_today),
            onPressed: _toggleView,
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_isCalendarView)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_left),
                        onPressed: _previousMonth,
                      ),
                      Text(
                        "${_focusedDay.year}년 ${_focusedDay.month}월",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: theme.brightness == Brightness.dark 
                              ? Colors.white 
                              : theme.textTheme.titleLarge?.color, // 다크 모드: 화이트, 라이트 모드: 기본 색상
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.arrow_right),
                        onPressed: _nextMonth,
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildSummaryItem(
                        label: "수입",
                        value: totalIncome,
                        color: Colors.blue,
                      ),
                      _buildSummaryItem(
                        label: "지출",
                        value: totalExpense,
                        color: Colors.red,
                      ),
                      _buildSummaryItem(
                        label: "합계",
                        value: totalIncome - totalExpense,
                        color: textStyle?.color ?? Colors.black,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          Expanded(
            child: _isCalendarView ? _buildCalendarView() : _buildListView(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.pushNamed(
            context,
            '/transaction',
            arguments: {'type': 'income'},
          );
        },
        child: Icon(Icons.add),
      ),
    );
  }

  Widget _buildSummaryItem({
    required String label,
    required int value,
    required Color color,
  }) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: color, fontSize: 16)),
        Text(
          "$value",
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildListView() {
    final startOfMonth = DateTime(_focusedDay.year, _focusedDay.month, 1);
    final endOfMonth = DateTime(_focusedDay.year, _focusedDay.month + 1, 0);

    return StreamBuilder<QuerySnapshot>(
      stream: _getTransactions(startOfMonth, endOfMonth),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(child: Text("이번 달 내역이 없습니다."));
        }

        final transactions = snapshot.data!.docs;
        final groupedTransactions = <String, List<Map<String, dynamic>>>{};

        for (var transaction in transactions) {
          final date = (transaction['date'] as Timestamp).toDate();
          final formattedDate = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";

          if (!groupedTransactions.containsKey(formattedDate)) {
            groupedTransactions[formattedDate] = [];
          }
          groupedTransactions[formattedDate]!.add({
            'id': transaction.id,
            ...transaction.data() as Map<String, dynamic>,
          });
        }

        final groupedKeys = groupedTransactions.keys.toList();

        return ListView.builder(
          itemCount: groupedKeys.length,
          itemBuilder: (context, index) {
            final dateKey = groupedKeys[index];
            final dailyTransactions = groupedTransactions[dateKey]!;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                  child: Text(
                    "$dateKey",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
                  ),
                ),
                ...dailyTransactions.map((transaction) {
                  final type = transaction['type'];
                  final category = transaction['category'];
                  final amount = transaction['amount'];
                  final memo = transaction['memo'];

                  return ListTile(
                    title: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          category,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        SizedBox(width: 50),
                        Expanded(
                          child: Text(
                            memo,
                            style: TextStyle(fontSize: 18),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    trailing: Text(
                      (type == 'income' ? "+" : "-") + "$amount",
                      style: TextStyle(
                        color: type == 'income' ? Colors.blue : Colors.red,
                        fontSize: 16,
                      ),
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => TransactionScreen(
                            transactionId: transaction['id'],
                          ),
                        ),
                      );
                    },
                  );
                }).toList(),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildCalendarView() {
    return Column(
      children: [
        TableCalendar(
          firstDay: DateTime.utc(2000, 1, 1),
          lastDay: DateTime.utc(2100, 12, 31),
          focusedDay: _focusedDay,
          headerStyle: HeaderStyle(
            titleCentered: true,
            formatButtonVisible: false,
            titleTextStyle: const TextStyle(
              fontSize: 20.0,
            ),
            headerPadding: const EdgeInsets.symmetric(vertical: 4.0),
          ),
          selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
          calendarFormat: CalendarFormat.month,
          onDaySelected: (selectedDay, focusedDay) {
            setState(() {
              _selectedDay = selectedDay;
              _focusedDay = focusedDay;
            });
          },
          calendarBuilders: CalendarBuilders(
            markerBuilder: (context, date, events) {
              final standardizedDate = DateTime.utc(date.year, date.month, date.day);
              if (_markers.containsKey(standardizedDate)) {
                final isIncome = _markers[standardizedDate]!['income'] ?? false;
                final isExpense = _markers[standardizedDate]!['expense'] ?? false;
                List<Widget> markers = [];
                if (isIncome) {
                  markers.add(
                    Icon(Icons.circle, color: Colors.blue, size: 6), // 수입 마커
                  );
                }
                if (isExpense) {
                  markers.add(
                    Icon(Icons.circle, color: Colors.red, size: 6), // 지출 마커
                  );
                }
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: markers,
                );
              }
              return null; // 마커가 없는 경우
            },
          ),
          calendarStyle: CalendarStyle(
            selectedDecoration: BoxDecoration(
              color: Colors.cyan,
              shape: BoxShape.circle,
            ),
            todayDecoration: BoxDecoration(
              shape: BoxShape.circle,
            ),
              todayTextStyle: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red
              )
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _getTransactions(
              _selectedDay ?? _focusedDay,
              _selectedDay?.add(Duration(days: 1)) ?? _focusedDay.add(Duration(days: 1)),
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(child: Text("내역이 없습니다."));
              }

              final transactions = snapshot.data!.docs;

              return ListView.builder(
                itemCount: transactions.length,
                itemBuilder: (context, index) {
                  final transaction = transactions[index];
                  final type = transaction['type'];
                  final category = transaction['category'];
                  final amount = transaction['amount'];
                  final memo = transaction['memo'];

                  return ListTile(
                    title: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          category,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        SizedBox(width: 50),
                        Expanded(
                          child: Text(
                            memo,
                            style: TextStyle(fontSize: 18),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    trailing: Text(
                      (type == 'income' ? "+" : "-") + "$amount",
                      style: TextStyle(
                        color: type == 'income' ? Colors.blue : Colors.red,
                        fontSize: 16,
                      ),
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => TransactionScreen(
                            transactionId: transaction.id,
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
