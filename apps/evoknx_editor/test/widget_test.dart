import 'package:flutter_test/flutter_test.dart';
import 'package:knx_config/knx_config.dart';

void main() {
  test('new project is valid', () {
    expect(isProject(newProject('Test')), isTrue);
  });
}
