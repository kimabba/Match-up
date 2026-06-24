import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/utils/grade_labels.dart';

void main() {
  group('grade_labels', () {
    test('tennis grade order: under1y → over5y', () {
      expect(tennisGrades, ['under1y', 'y1to3', 'y3to5', 'over5y']);
    });

    test('futsal grade order', () {
      expect(futsalGrades, [
        'intro',
        'beginner',
        'intermediate',
        'advanced',
        'elite',
      ]);
    });

    test('Korean labels', () {
      expect(gradeLabel('y3to5'), '3~5년');
      expect(gradeLabel('under1y'), '1년 미만');
      expect(gradeLabel('intro'), '입문');
      expect(gradeLabel('intermediate'), '중급');
      expect(gradeLabel('elite'), '선출');
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

  group('tennis division label grouping', () {
    test('tennisDivisionLabels returns unique labels in first-seen order', () {
      final labels = tennisDivisionLabels();
      // 유니크해야 함
      expect(labels.toSet().length, labels.length);
      // 첫 등장 순서 보존: 광주(gj) 오픈부가 첫 항목
      expect(labels.first, '오픈부');
      // 골드부/일반부/크로스대회 등 공통 라벨 포함
      expect(labels, contains('골드부'));
      expect(labels, contains('일반부'));
      expect(labels, contains('크로스대회'));
      expect(labels, contains('여자우승자부'));
    });

    test('골드부 라벨 → 협회 무관 모든 골드부 코드', () {
      final codes = tennisCodesForLabel('골드부');
      expect(codes, containsAll(['gj_m_gold', 'jn_m_gold']));
      expect(codes.every((c) => c.endsWith('_gold')), isTrue);
    });

    test('크로스대회 라벨 → gj/jn 크로스 코드', () {
      final codes = tennisCodesForLabel('크로스대회');
      expect(codes, containsAll(['gj_cross', 'jn_cross']));
    });

    test('미등록 라벨은 빈 리스트', () {
      expect(tennisCodesForLabel('존재하지않는부'), isEmpty);
    });

    test('tennisCodesForLabels 는 여러 라벨 코드를 합집합으로 모음', () {
      final codes = tennisCodesForLabels({'골드부', '일반부'});
      expect(codes, containsAll(['gj_m_gold', 'jn_m_gold']));
      expect(codes, containsAll(['gj_m_general', 'jn_m_general']));
      // 중복 없는 Set
      expect(codes.length, codes.toSet().length);
    });

    test('빈 라벨 집합 → 빈 코드 집합', () {
      expect(tennisCodesForLabels(const <String>{}), isEmpty);
    });

    test('모든 division 코드는 라벨 그룹핑으로 왕복 가능', () {
      // 각 코드는 자기 라벨의 코드 집합에 반드시 포함된다.
      for (final d in tennisDivisions) {
        expect(tennisCodesForLabel(d.label), contains(d.code));
      }
    });
  });
}
