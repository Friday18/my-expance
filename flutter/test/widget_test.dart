// The template's counter test doesn't apply to this app; real tests are in logic_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:my_expance/logic/format.dart';

void main() {
  test('formats rupees', () => expect(formatMoney(450), '₹450'));
}
