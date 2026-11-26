import 'package:flutter_test/flutter_test.dart';
import 'package:svitlo/main.dart';

void main() {
  test('isNewerVersion', () {
    expect(isNewerVersion('1.0.1', '1.0.0'), isTrue);
    expect(isNewerVersion('1.2.10', '1.2.9'), isTrue);
    expect(isNewerVersion('2.0', '1.9.9'), isTrue);
    expect(isNewerVersion('1.0.0', '1.0.0'), isFalse);
    expect(isNewerVersion('1.0', '1.0.0'), isFalse);
    expect(isNewerVersion('1.0.0', '1.0.1'), isFalse);
  });

  test('groupRows merges adjacent slots with the same status', () {
    const rows = [
      ScheduleRow(hours: '08-00 10-30', queues: ['1(1,2)']),
      ScheduleRow(hours: '10-30 13-00', queues: ['2(1,2)']),
      ScheduleRow(hours: '13-00 14-00', queues: []),
      ScheduleRow(hours: '14-00 16-00', queues: ['3(1,2)']),
      ScheduleRow(hours: '16-00 17-30', queues: ['1(1,2)']),
      ScheduleRow(hours: '17-30 20-00', queues: ['1(1,2)', '2(1,2)']),
      ScheduleRow(hours: '20-00 21-00', queues: []),
    ];
    final grouped = groupRows('1(1,2)', rows);
    expect(_hours(grouped),
        ['08-00 10-30', '10-30 16-00', '16-00 20-00', '20-00 21-00']);
    expect(grouped.map((r) => slotStatus('1(1,2)', r.queues)).toList(), [
      PowerStatus.off,
      PowerStatus.light,
      PowerStatus.off,
      PowerStatus.light,
    ]);
  });

  test('groupRows does not merge across a gap', () {
    const rows = [
      ScheduleRow(hours: '08-00 10-00', queues: []),
      ScheduleRow(hours: '11-00 12-00', queues: []),
    ];
    expect(_hours(groupRows('1(1,2)', rows)), ['08-00 10-00', '11-00 12-00']);
  });
}

List<String> _hours(List<ScheduleRow> rows) => rows.map((r) => r.hours).toList();
