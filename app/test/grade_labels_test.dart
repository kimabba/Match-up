import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/utils/grade_labels.dart';

void main() {
  group('grade_labels', () {
    test('tennis grade order: rookie → div1', () {
      expect(tennisGrades, ['rookie', 'div5', 'div4', 'div3', 'div2', 'div1']);
    });

    test('futsal grade order', () {
      expect(futsalGrades, ['beginner', 'intermediate', 'advanced']);
    });

    test('Korean labels', () {
      expect(gradeLabel('div3'), '3부');
      expect(gradeLabel('rookie'), '신입');
      expect(gradeLabel('intermediate'), '중급');
      expect(sportLabel(Sport.tennis), '테니스');
      expect(sportLabel(Sport.futsal), '풋살');
    });

    test('sportFromString roundtrip', () {
      expect(sportFromString('tennis'), Sport.tennis);
      expect(sportFromString('futsal'), Sport.futsal);
      expect(sportToString(Sport.tennis), 'tennis');
      expect(sportToString(Sport.futsal), 'futsal');
    });

    test('gradesFor returns sport-specific grades', () {
      expect(gradesFor(Sport.tennis), tennisGrades);
      expect(gradesFor(Sport.futsal), futsalGrades);
    });
  });
}
