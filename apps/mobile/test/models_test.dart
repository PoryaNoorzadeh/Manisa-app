import 'package:flutter_test/flutter_test.dart';
import 'package:manisa_mobile/src/data/models.dart';

void main() {
  test('parses a three-gang device descriptor', () {
    final descriptor = DeviceDescriptor.fromJson(<String, Object?>{
      'productType': 'switch_3gang',
      'displayName': 'Manisa 3-Gang Touch Switch',
      'category': 'switch',
      'endpoints': <Object?>[
        for (var i = 1; i <= 3; i++)
          <String, Object?>{
            'id': i,
            'name': 'Channel $i',
            'capabilities': <Object?>[
              <String, Object?>{
                'id': 'on_off',
                'readable': true,
                'writable': true,
              },
            ],
          },
      ],
    });

    expect(descriptor.endpoints, hasLength(3));
    expect(descriptor.endpoints.last.id, 3);
    expect(descriptor.endpoints.last.capabilities.single.id, 'on_off');
  });

  test('device state key combines endpoint and capability', () {
    const state = DeviceState(
      deviceId: 'device_1',
      endpoint: 2,
      capability: 'on_off',
      value: true,
    );

    expect(state.key, '2:on_off');
  });
}
