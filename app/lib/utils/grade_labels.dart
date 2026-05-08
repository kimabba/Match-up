enum Sport { tennis, futsal }

const tennisGrades = ['rookie', 'div5', 'div4', 'div3', 'div2', 'div1'];
const futsalGrades = ['beginner', 'intermediate', 'advanced'];

const gradeLabels = <String, String>{
  'rookie': '신입',
  'div5': '5부',
  'div4': '4부',
  'div3': '3부',
  'div2': '2부',
  'div1': '1부',
  'beginner': '초급',
  'intermediate': '중급',
  'advanced': '고급',
};

const sportLabels = <Sport, String>{
  Sport.tennis: '테니스',
  Sport.futsal: '풋살',
};

Sport sportFromString(String s) =>
    s == 'futsal' ? Sport.futsal : Sport.tennis;

String sportToString(Sport s) => s == Sport.futsal ? 'futsal' : 'tennis';

List<String> gradesFor(Sport sport) =>
    sport == Sport.tennis ? tennisGrades : futsalGrades;

String gradeLabel(String grade) => gradeLabels[grade] ?? grade;
String sportLabel(Sport sport) => sportLabels[sport] ?? '';
String sportLabelFromString(String s) => sportLabel(sportFromString(s));
