const _westernDigits = <String>[
  '0',
  '1',
  '2',
  '3',
  '4',
  '5',
  '6',
  '7',
  '8',
  '9',
];
const _persianDigits = <String>[
  '۰',
  '۱',
  '۲',
  '۳',
  '۴',
  '۵',
  '۶',
  '۷',
  '۸',
  '۹',
];

String toPersianDigits(Object value) {
  var text = value.toString();
  for (var index = 0; index < _westernDigits.length; index++) {
    text = text.replaceAll(_westernDigits[index], _persianDigits[index]);
  }
  return text;
}
