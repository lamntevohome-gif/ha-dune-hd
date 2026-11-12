import 'package:flutter_test/flutter_test.dart';
import 'package:knx_config/knx_config.dart';

void main() {
  test('a new project is a valid configuration', () {
    expect(isProject(exportProject(newProject('Test'))), isTrue);
  });
}
