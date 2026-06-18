import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

void main() {
  group('CodeLines constructor ', () {
    test('`CodeLines()`', () {
      {
        final CodeLines codeLines = CodeLines([]);
        expect(listEquals(codeLines.segments, const []), true);
      }
      {
        final CodeLines codeLines = CodeLines([
          const CodeLineSegment(
            codeLines: [
              CodeLine('abc'),
              CodeLine('foo'),
              CodeLine('bar')
            ]
          )
        ]);
        expect(listEquals(codeLines.segments, const [
          CodeLineSegment(
            codeLines: [
              CodeLine('abc'),
              CodeLine('foo'),
              CodeLine('bar')
            ]
          )
        ]), true);
      }
    });

    test('`CodeLines.empty()`', () {
      final CodeLines codeLines = CodeLines.empty();
      expect(listEquals(codeLines.segments, const []), true);
    });

    test('`CodeLines.of()`', () {
      {
        final CodeLines codeLines = CodeLines.of(const []);
        expect(listEquals(codeLines.segments, const []), true);
      }
      {
        final CodeLines codeLines = CodeLines.of(const [
          CodeLine('abc'),
          CodeLine('foo'),
          CodeLine('bar')
        ]);
        expect(listEquals(codeLines.segments, const [
          CodeLineSegment(
            codeLines: [
              CodeLine('abc'),
              CodeLine('foo'),
              CodeLine('bar')
            ]
          )
        ]), true);
      }
      {
        final CodeLines codeLines = CodeLines.of(List.generate(512, (index) => CodeLine('$index')));
        expect(codeLines.segments.length, 2);
        for (int i = 0; i < codeLines.segments.length; i++) {
          expect(codeLines.segments[i].first, CodeLine('${i * 256}'));
          expect(codeLines.segments[i].last, CodeLine('${(i + 1) * 256 - 1}'));
        }
      }
    });

    test('`CodeLines.from()`', () {
      {
        final CodeLines codeLines = CodeLines.from(CodeLines.empty());
        expect(listEquals(codeLines.segments, const []), true);
      }
      {
        final CodeLines codeLines = CodeLines.from(CodeLines([
          const CodeLineSegment(
            codeLines: [
              CodeLine('abc'),
              CodeLine('foo'),
              CodeLine('bar')
            ]
          )
        ]));
        expect(listEquals(codeLines.segments, const [
          CodeLineSegment(
            codeLines: [
              CodeLine('abc'),
              CodeLine('foo'),
              CodeLine('bar')
            ],
          )
        ]), true);
      }
      {
        final CodeLines codeLines = CodeLines.from(CodeLines([
          const CodeLineSegment(
            codeLines: [
              CodeLine('abc'),
            ]
          ),
          const CodeLineSegment(
            codeLines: [
              CodeLine('foo'),
            ]
          ),
          const CodeLineSegment(
            codeLines: [
              CodeLine('bar'),
            ]
          )
        ]));
        expect(listEquals(codeLines.segments, const [
          CodeLineSegment(
            codeLines: [
              CodeLine('abc'),
            ],
          ),
          CodeLineSegment(
            codeLines: [
              CodeLine('foo'),
            ],
          ),
          CodeLineSegment(
            codeLines: [
              CodeLine('bar'),
            ],
          )
        ]), true);
      }
    });
  });

  group('CodeLines getter ', () {
    test('`first` and `last`', () {
      {
        final CodeLines codeLines = CodeLines.empty();
        expect(() => codeLines.first, throwsA(isA<StateError>()));
        expect(() => codeLines.last, throwsA(isA<StateError>()));
      }
      {
        final CodeLines codeLines = CodeLines.of(const [
          CodeLine('abc')
        ]);
        expect(codeLines.first, const CodeLine('abc'));
        expect(codeLines.last, const CodeLine('abc'));
      }
      {
        final CodeLines codeLines = CodeLines.of(const [
          CodeLine('abc'),
          CodeLine('foo'),
          CodeLine('bar')
        ]);
        expect(codeLines.first, const CodeLine('abc'));
        expect(codeLines.last, const CodeLine('bar'));
      }
      {
        final CodeLines codeLines = CodeLines.of(List.generate(3000, (index) => CodeLine('$index')));
        expect(codeLines.first, const CodeLine('0'));
        expect(codeLines.last, const CodeLine('2999'));
      }
    });

    test('`length`', () {
      {
        final CodeLines codeLines = CodeLines.empty();
        expect(codeLines.length, 0);
      }
      {
        final CodeLines codeLines = CodeLines.of(const [
          CodeLine('abc')
        ]);
        expect(codeLines.length, 1);
      }
      {
        final CodeLines codeLines = CodeLines.of(const [
          CodeLine('abc'),
          CodeLine('foo'),
          CodeLine('bar')
        ]);
        expect(codeLines.length, 3);
      }
      {
        final CodeLines codeLines = CodeLines.of(List.generate(3000, (index) => CodeLine('$index')));
        expect(codeLines.length, 3000);
      }
    });

    test('`isEmpty` and `isNotEmpty`', () {
      {
        final CodeLines codeLines = CodeLines.empty();
        expect(codeLines.isEmpty, true);
        expect(codeLines.isNotEmpty, false);
      }
      {
        final CodeLines codeLines = CodeLines.of(const [
          CodeLine('abc')
        ]);
        expect(codeLines.isEmpty, false);
        expect(codeLines.isNotEmpty, true);
      }
      {
        final CodeLines codeLines = CodeLines.of(const [
          CodeLine('abc'),
          CodeLine('foo'),
          CodeLine('bar')
        ]);
        expect(codeLines.isEmpty, false);
        expect(codeLines.isNotEmpty, true);
      }
      {
        final CodeLines codeLines = CodeLines.of(List.generate(3000, (index) => CodeLine('$index')));
        expect(codeLines.isEmpty, false);
        expect(codeLines.isNotEmpty, true);
      }
    });

    test('`lineCount`', () {
      {
        final CodeLines codeLines = CodeLines.empty();
        expect(codeLines.lineCount, 0);
      }
      {
        final CodeLines codeLines = CodeLines.of(const [
          CodeLine('abc')
        ]);
        expect(codeLines.lineCount, 1);
      }
      {
        final CodeLines codeLines = CodeLines.of(const [
          CodeLine('abc'),
          CodeLine('foo'),
          CodeLine('bar')
        ]);
        expect(codeLines.lineCount, 3);
      }
      {
        final CodeLines codeLines = CodeLines.of(const [
          CodeLine('abc', [
            CodeLine('123'),
            CodeLine('456'),
            CodeLine('789'),
          ]),
          CodeLine('foo', [
            CodeLine('123'),
            CodeLine('456'),
            CodeLine('789'),
          ]),
          CodeLine('bar', [
            CodeLine('123'),
            CodeLine('456'),
            CodeLine('789'),
          ])
        ]);
        expect(codeLines.lineCount, 12);
      }
      {
        final CodeLines codeLines = CodeLines.of(List.generate(3000, (index) => CodeLine('$index')));
        expect(codeLines.lineCount, 3000);
      }
    });
  });

  group('CodeLines operator ', () {
    test('`[]`', () {
      {
        final CodeLines codeLines = CodeLines.empty();
        expect(() => codeLines[0], throwsA(isA<RangeError>()));
      }
      {
        final CodeLines codeLines = CodeLines.of(const [
          CodeLine('abc')
        ]);
        expect(codeLines[0], const CodeLine('abc'));
        expect(() => codeLines[1], throwsA(isA<RangeError>()));
      }
      {
        final CodeLines codeLines = CodeLines.of(const [
          CodeLine('abc'),
          CodeLine('foo'),
          CodeLine('bar')
        ]);
        expect(codeLines[0], const CodeLine('abc'));
        expect(codeLines[1], const CodeLine('foo'));
        expect(codeLines[2], const CodeLine('bar'));
        expect(() => codeLines[3], throwsA(isA<RangeError>()));
      }
      {
        final CodeLines codeLines = CodeLines.of(List.generate(3000, (index) => CodeLine('$index')));
        expect(codeLines[0], const CodeLine('0'));
        expect(codeLines[1024], const CodeLine('1024'));
        expect(codeLines[2047], const CodeLine('2047'));
        expect(codeLines[2999], const CodeLine('2999'));
        expect(() => codeLines[3000], throwsA(isA<RangeError>()));
      }
    });

    test('`[]=`', () {
      {
        final CodeLines codeLines = CodeLines.empty();
        expect(() => codeLines[0] = const CodeLine('abc'), throwsA(isA<RangeError>()));
      }
      {
        final CodeLines codeLines = CodeLines.of(const [
          CodeLine('abc')
        ]);
        codeLines[0] = const CodeLine('foo');
        expect(codeLines[0], const CodeLine('foo'));
        expect(() => codeLines[1] = const CodeLine('abc'), throwsA(isA<RangeError>()));
      }
      {
        final CodeLines codeLines = CodeLines.of(const [
          CodeLine('abc'),
          CodeLine('foo'),
          CodeLine('bar')
        ]);
        codeLines[0] = const CodeLine('123');
        expect(codeLines[0], const CodeLine('123'));
        codeLines[1] = const CodeLine('456');
        expect(codeLines[1], const CodeLine('456'));
        codeLines[2] = const CodeLine('789');
        expect(codeLines[2], const CodeLine('789'));
      }
      {
        final CodeLines codeLines = CodeLines.of(List.generate(3000, (index) => CodeLine('$index')));
        codeLines[0] = const CodeLine('a');
        expect(codeLines[0], const CodeLine('a'));
        codeLines[1024] = const CodeLine('b');
        expect(codeLines[1024], const CodeLine('b'));
        codeLines[2047] = const CodeLine('c');
        expect(codeLines[2047], const CodeLine('c'));
        codeLines[2999] = const CodeLine('d');
        expect(codeLines[2999], const CodeLine('d'));
      }
      {
        final CodeLines codeLines = CodeLines([
          CodeLineSegment(
            codeLines: List.of(const [
              CodeLine('abc'),
              CodeLine('foo'),
              CodeLine('bar')
            ]),
          )
        ]);
        codeLines[0] = const CodeLine('a');
      }
      {
        final CodeLines codeLines = CodeLines([
          CodeLineSegment(
            codeLines: List.generate(1024, (index) => CodeLine('$index')),
          )
        ]);
        codeLines[1023] = const CodeLine('a');
        expect(codeLines[1023], const CodeLine('a'));
      }
    });

    test('`==`', () {
      expect(CodeLines.empty() == CodeLines.empty(), true);
      expect(CodeLines.empty() == CodeLines.of(const [
        CodeLine('abc')
      ]), false);
      expect(CodeLines.of(const [
        CodeLine('abc')
      ]) == CodeLines.of(const [
        CodeLine('abc')
      ]), true);
      expect(CodeLines.of(const [
        CodeLine('foo')
      ]) == CodeLines.of(const [
        CodeLine('abc')
      ]), false);
      expect(CodeLines([
        const CodeLineSegment(
          codeLines: [
            CodeLine('abc')
          ]
        )
      ]) == CodeLines([
        const CodeLineSegment(
          codeLines: [
            CodeLine('abc')
          ]
        )
      ]), true);
      expect(CodeLines([
        const CodeLineSegment(
          codeLines: [
            CodeLine('abc')
          ]
        ),
        const CodeLineSegment(
          codeLines: [
            CodeLine('foo')
          ]
        ),
        const CodeLineSegment(
          codeLines: [
            CodeLine('bar')
          ]
        )
      ]) == CodeLines([
        const CodeLineSegment(
          codeLines: [
            CodeLine('abc')
          ]
        ),
        const CodeLineSegment(
          codeLines: [
            CodeLine('foo')
          ]
        ),
        const CodeLineSegment(
          codeLines: [
            CodeLine('bar')
          ]
        )
      ]), true);
      expect(CodeLines([
        const CodeLineSegment(
          codeLines: [
            CodeLine('abc')
          ],
        ),
        const CodeLineSegment(
          codeLines: [
            CodeLine('foo')
          ]
        ),
        const CodeLineSegment(
          codeLines: [
            CodeLine('bar')
          ]
        )
      ]) == CodeLines([
        const CodeLineSegment(
          codeLines: [
            CodeLine('abc')
          ]
        ),
        const CodeLineSegment(
          codeLines: [
            CodeLine('foo')
          ]
        ),
        const CodeLineSegment(
          codeLines: [
            CodeLine('bar')
          ]
        )
      ]), true);
    });
  });

  group('CodeLines method ', () {
    test('`add()`', () {
      {
        final CodeLines codeLines = CodeLines.empty();
        codeLines.add(const CodeLine('abc'));
        expect(codeLines.length, 1);
        expect(codeLines.first, const CodeLine('abc'));
        expect(codeLines.last, const CodeLine('abc'));
        codeLines.add(const CodeLine('foo'));
        expect(codeLines.length, 2);
        expect(codeLines.first, const CodeLine('abc'));
        expect(codeLines.last, const CodeLine('foo'));
        codeLines.add(const CodeLine('bar'));
        expect(codeLines.length, 3);
        expect(codeLines.first, const CodeLine('abc'));
        expect(codeLines.last, const CodeLine('bar'));
      }
      {
        final CodeLines codeLines = CodeLines.of(List.generate(1024, (index) => CodeLine('$index')));
        codeLines.add(const CodeLine('abc'));
        expect(codeLines.length, 1025);
        expect(codeLines.last, const CodeLine('abc'));
        expect(codeLines.segments.length, 5);
        expect(codeLines.segments.last, const CodeLineSegment(
          codeLines: [
            CodeLine('abc')
          ]
        ));
      }
      {
        final CodeLines codeLines = CodeLines([
          CodeLineSegment(
            codeLines: List.of(const [
              CodeLine('abc')
            ]),
          )
        ]);
        codeLines.add(const CodeLine('foo'));
        codeLines.add(const CodeLine('bar'));
        expect(codeLines.length, 3);
        expect(codeLines.first, const CodeLine('abc'));
        expect(codeLines.last, const CodeLine('bar'));
      }
    });

    test('`addAll()`', () {
      {
        final CodeLines codeLines = CodeLines.empty();
        codeLines.addAll(const [
          CodeLine('abc')
        ]);
        expect(codeLines.length, 1);
        expect(codeLines.first, const CodeLine('abc'));
        expect(codeLines.last, const CodeLine('abc'));
        codeLines.addAll(const [
          CodeLine('foo'),
          CodeLine('bar')
        ]);
      }
      {
        final CodeLines codeLines = CodeLines.of(const [
          CodeLine('abc')
        ]);
        codeLines.addAll(List.generate(512, (index) => CodeLine('$index')));
        expect(codeLines.length, 513);
        expect(codeLines.last, const CodeLine('511'));
        expect(codeLines.toList(), [const CodeLine('abc'), ...List.generate(512, (index) => CodeLine('$index'))]);
      }
      {
        final CodeLines codeLines = CodeLines([
          CodeLineSegment(
            codeLines: List.of(const [
              CodeLine('abc')
            ]),
          )
        ]);
        codeLines.addAll(List.generate(512, (index) => CodeLine('$index')));
        expect(codeLines.length, 513);
        expect(codeLines.last, const CodeLine('511'));
        expect(codeLines.toList(), [const CodeLine('abc'), ...List.generate(512, (index) => CodeLine('$index'))]);
      }
    });

    test('`addFrom()`', () {
      {
        final CodeLines codeLines1 = CodeLines.empty();
        final CodeLines codeLines2 = CodeLines.of(const [
          CodeLine('abc')
        ]);
        codeLines1.addFrom(codeLines2, 0);
        expect(codeLines1.toList(), const [CodeLine('abc')]);
      }
      {
        final CodeLines codeLines1 = CodeLines([
          const CodeLineSegment(
            codeLines: [
              CodeLine('abc'),
              CodeLine('foo'),
              CodeLine('bar')
            ],
          )
        ]);
        final CodeLines codeLines2 = CodeLines([
          CodeLineSegment(
            codeLines: List.of([
              const CodeLine('123'),
            ]),
          )
        ]);
        codeLines2.addFrom(codeLines1, 1, 2);
        expect(codeLines2.toList(), const [CodeLine('123'), CodeLine('foo')]);
        codeLines2.addFrom(codeLines1, 0);
        expect(codeLines2.toList(), const [CodeLine('123'), CodeLine('foo'), CodeLine('abc'), CodeLine('foo'), CodeLine('bar')]);
      }
      {
        final CodeLines codeLines1 = CodeLines.of(const [
          CodeLine('abc')
        ]);
        final CodeLines codeLines2 = CodeLines.of(List.generate(512, (index) => CodeLine('$index')));
        codeLines1.addFrom(codeLines2, 0);
        expect(codeLines1.toList(), [const CodeLine('abc'), ...List.generate(512, (index) => CodeLine('$index'))]);
      }
      {
        final CodeLines codeLines1 = CodeLines.of(const [
          CodeLine('abc')
        ]);
        final CodeLines codeLines2 = CodeLines([
          const CodeLineSegment(
            codeLines: [
              CodeLine('foo')
            ],
          ),
          const CodeLineSegment(
            codeLines: [
              CodeLine('bar')
            ],
          ),
          CodeLineSegment(
            codeLines: List.generate(256, (index) => CodeLine('$index')),
          ),
          const CodeLineSegment(
            codeLines: [
              CodeLine('abc')
            ],
          ),
        ]);
        codeLines1.addFrom(codeLines2, 0);
        expect(codeLines1.toList(), [const CodeLine('abc'), const CodeLine('foo'), const CodeLine('bar'), ...List.generate(256, (index) => CodeLine('$index')), const CodeLine('abc')]);
      }
    });

    test('`asString`', () {
      {
        final CodeLines codeLines = CodeLines.empty();
        expect(codeLines.asString(TextLineBreak.lf), '');
      }
      {
        final CodeLines codeLines = CodeLines.of(const [
          CodeLine('abc')
        ]);
        expect(codeLines.asString(TextLineBreak.lf), 'abc');
      }
      {
        final CodeLines codeLines = CodeLines.of(const [
          CodeLine('abc'),
          CodeLine('foo'),
          CodeLine('bar')
        ]);
        expect(codeLines.asString(TextLineBreak.lf), 'abc\nfoo\nbar');
        expect(codeLines.asString(TextLineBreak.crlf), 'abc\r\nfoo\r\nbar');
        expect(codeLines.asString(TextLineBreak.cr), 'abc\rfoo\rbar');
      }
      {
        final CodeLines codeLines = CodeLines.of(const [
          CodeLine('abc', [
            CodeLine('123'),
            CodeLine('456'),
            CodeLine('789'),
          ]),
          CodeLine('foo', [
            CodeLine('123'),
            CodeLine('456'),
            CodeLine('789'),
          ]),
          CodeLine('bar', [
            CodeLine('123'),
            CodeLine('456'),
            CodeLine('789'),
          ])
        ]);
        expect(codeLines.asString(TextLineBreak.lf), 'abc\n123\n456\n789\nfoo\n123\n456\n789\nbar\n123\n456\n789');
        expect(codeLines.asString(TextLineBreak.crlf), 'abc\r\n123\r\n456\r\n789\r\nfoo\r\n123\r\n456\r\n789\r\nbar\r\n123\r\n456\r\n789');
        expect(codeLines.asString(TextLineBreak.cr), 'abc\r123\r456\r789\rfoo\r123\r456\r789\rbar\r123\r456\r789');
        expect(codeLines.asString(TextLineBreak.lf, false), 'abc\nfoo\nbar');
      }
    });

    test('`equals()`', () {
      expect(CodeLines.empty().equals(CodeLines.empty()), true);
      expect(CodeLines.empty().equals(CodeLines.of(const [
        CodeLine('abc')
      ])), false);
      expect(CodeLines.of(const [
        CodeLine('abc')
      ]).equals(CodeLines.empty()), false);
      expect(CodeLines.of(const [
        CodeLine('abc')
      ]).equals(CodeLines.of(const [
        CodeLine('abc')
      ])), true);
      expect(CodeLines.of(const [
        CodeLine('abc'),
        CodeLine('foo'),
        CodeLine('bar')
      ]).equals(CodeLines.of(const [
        CodeLine('abc'),
        CodeLine('foo'),
        CodeLine('bar')
      ])), true);
      expect(CodeLines.of(const [
        CodeLine('abc'),
        CodeLine('foo'),
        CodeLine('bar')
      ]).equals(CodeLines.of(const [
        CodeLine('abc'),
        CodeLine('bar'),
        CodeLine('foo'),
      ])), false);
      expect(CodeLines([
        const CodeLineSegment(
          codeLines: [
            CodeLine('abc'),
          ],
        ),
        const CodeLineSegment(
          codeLines: [
            CodeLine('foo'),
          ],
        ),
        const CodeLineSegment(
          codeLines: [
            CodeLine('bar'),
          ],
        )
      ]).equals(CodeLines.of(const [
        CodeLine('abc'),
        CodeLine('foo'),
        CodeLine('bar'),
      ])), true);
    });

    test('`sublines()`', () {
      {
        final CodeLines codeLines = CodeLines.empty();
        expect(codeLines.sublines(0), CodeLines.empty());
        expect(() => codeLines.sublines(1), throwsA(isA<RangeError>()));
        expect(() => codeLines.sublines(0, 1), throwsA(isA<RangeError>()));
      }
      {
        final CodeLines codeLines = CodeLines.of(const [
          CodeLine('abc')
        ]);
        expect(codeLines.sublines(0).equals(codeLines), true);
        expect(identical(codeLines.sublines(0), codeLines), false);
        expect(codeLines.sublines(1), CodeLines.empty());
        expect(codeLines.sublines(0, 1).equals(codeLines), true);
        expect(identical(codeLines.sublines(0, 1), codeLines), false);
        expect(() => codeLines.sublines(2), throwsA(isA<RangeError>()));
        expect(() => codeLines.sublines(0, 2), throwsA(isA<RangeError>()));
        expect(() => codeLines.sublines(1, 2), throwsA(isA<RangeError>()));
      }
      {
        final CodeLines codeLines = CodeLines.of(const [
          CodeLine('abc'),
          CodeLine('foo'),
          CodeLine('bar')
        ]);
        expect(codeLines.sublines(0).equals(codeLines), true);
        expect(identical(codeLines.sublines(0), codeLines), false);
        expect(codeLines.sublines(1).toList(), const [CodeLine('foo'), CodeLine('bar')]);
        expect(codeLines.sublines(0, 1).toList(), const [CodeLine('abc')]);
        expect(codeLines.sublines(0, 2).toList(), const [CodeLine('abc'), CodeLine('foo')]);
        expect(codeLines.sublines(1, 2).toList(), const [CodeLine('foo')]);
        expect(codeLines.sublines(2, 3).toList(), const [CodeLine('bar')]);
        expect(codeLines.sublines(0, 3).toList(), const [CodeLine('abc'), CodeLine('foo'), CodeLine('bar')]);
        expect(() => codeLines.sublines(4), throwsA(isA<RangeError>()));
      }
      {
        final CodeLines codeLines = CodeLines.of(List.generate(3000, (index) => CodeLine('$index')));
        expect(codeLines.sublines(512, 1024 + 512).toList(), List.generate(1024, (index) => CodeLine('${index + 512}')));
        expect(codeLines.sublines(512, 2048 + 512).toList(), List.generate(2048, (index) => CodeLine('${index + 512}')));
      }
    });

    test('`clear()`', () {
      {
        final CodeLines codeLines = CodeLines.empty();
        codeLines.clear();
        expect(codeLines.isEmpty, true);
      }
      {
        final CodeLines codeLines = CodeLines.of(const [
          CodeLine('abc')
        ]);
        codeLines.clear();
        expect(codeLines.isEmpty, true);
      }
      {
        final CodeLines codeLines = CodeLines.of(const [
          CodeLine('abc'),
          CodeLine('foo'),
          CodeLine('bar')
        ]);
        codeLines.clear();
        expect(codeLines.isEmpty, true);
      }
    });
  
    test('`index2lineIndex()`', () {
      // Single code line
      {
        final CodeLines codeLines = CodeLines.of(const [
          CodeLine('abc')
        ]);
        expect(codeLines.index2lineIndex(0), 0);
        expect(codeLines.index2lineIndex(1), -1);
        expect(codeLines.index2lineIndex(-1), -1);
      }
      // Multi code lines
      {
        final CodeLines codeLines = CodeLines.of(const [
          CodeLine('abc'),
          CodeLine('foo'),
          CodeLine('bar'),
        ]);
        expect(codeLines.index2lineIndex(0), 0);
        expect(codeLines.index2lineIndex(1), 1);
        expect(codeLines.index2lineIndex(2), 2);
      }
      // Multi code lines in different segments
      {
        final CodeLines codeLines = CodeLines([
          const CodeLineSegment(
            codeLines: [
              CodeLine('abc'),
            ],
          ),
          const CodeLineSegment(
            codeLines: [
              CodeLine('foo'),
            ],
          ),
          const CodeLineSegment(
            codeLines: [
              CodeLine('bar')
            ],
          )
        ]);
        expect(codeLines.index2lineIndex(0), 0);
        expect(codeLines.index2lineIndex(1), 1);
        expect(codeLines.index2lineIndex(2), 2);
      }
      // Multi code lines with collapsed chunks
      {
        final CodeLines codeLines = CodeLines.of(const [
          CodeLine('{', [
            CodeLine('  "start": "foo",'),
            CodeLine('  "abc": [', [
              CodeLine('    0,'),
              CodeLine('    1,'),
              CodeLine('    2,'),
            ]),
            CodeLine('  ],'),
            CodeLine('  "end": "bar"'),
          ]),
          CodeLine('}'),
        ]);
        expect(codeLines.index2lineIndex(0), 0);
        expect(codeLines.index2lineIndex(1), 8);
      }
    });

    test('`lineIndex2index()`', () {
      // Single code line
      {
        final CodeLines codeLines = CodeLines.of(const [
          CodeLine('abc')
        ]);
        expect(codeLines.lineIndex2Index(0), const CodeLineIndex(0, -1));
        expect(codeLines.lineIndex2Index(1), const CodeLineIndex(-1, -1));
        expect(codeLines.lineIndex2Index(-1), const CodeLineIndex(-1, -1));
      }
      // Multi code lines
      {
        final CodeLines codeLines = CodeLines.of(const [
          CodeLine('abc'),
          CodeLine('foo'),
          CodeLine('bar'),
        ]);
        expect(codeLines.lineIndex2Index(0), const CodeLineIndex(0, -1));
        expect(codeLines.lineIndex2Index(1), const CodeLineIndex(1, -1));
        expect(codeLines.lineIndex2Index(2), const CodeLineIndex(2, -1));
      }
      // Multi code lines in different segments
      {
        final CodeLines codeLines = CodeLines([
          const CodeLineSegment(
            codeLines: [
              CodeLine('abc'),
            ],
          ),
          const CodeLineSegment(
            codeLines: [
              CodeLine('foo'),
            ],
          ),
          const CodeLineSegment(
            codeLines: [
              CodeLine('bar')
            ],
          )
        ]);
        expect(codeLines.lineIndex2Index(0), const CodeLineIndex(0, -1));
        expect(codeLines.lineIndex2Index(1), const CodeLineIndex(1, -1));
        expect(codeLines.lineIndex2Index(2), const CodeLineIndex(2, -1));
      }
      // Multi code lines with collapsed chunks
      {
        final CodeLines codeLines = CodeLines.of(const [
          CodeLine('{', [
            CodeLine('  "start": "foo",'),
            CodeLine('  "abc": [', [
              CodeLine('    0,'),
              CodeLine('    1,'),
              CodeLine('    2,'),
            ]),
            CodeLine('  ],'),
            CodeLine('  "end": "bar"'),
          ]),
          CodeLine('}'),
        ]);
        expect(codeLines.lineIndex2Index(0), const CodeLineIndex(0, -1));
        expect(codeLines.lineIndex2Index(1), const CodeLineIndex(0, 0));
        expect(codeLines.lineIndex2Index(2), const CodeLineIndex(0, 1));
        expect(codeLines.lineIndex2Index(3), const CodeLineIndex(0, 1));
        expect(codeLines.lineIndex2Index(6), const CodeLineIndex(0, 2));
        expect(codeLines.lineIndex2Index(8), const CodeLineIndex(1, -1));
      }
    });
  });

  group('CodeLines.fromText line endings ', () {
    test('normalizes CRLF and lone CR to plain line splits', () {
      expect(CodeLines.fromText('a\r\nb'),
          CodeLines.of(const [CodeLine('a'), CodeLine('b')]));
      expect(CodeLines.fromText('a\rb'),
          CodeLines.of(const [CodeLine('a'), CodeLine('b')]));
      expect(CodeLines.fromText('a\r\nb\nc\rd'),
          CodeLines.of(const [CodeLine('a'), CodeLine('b'), CodeLine('c'), CodeLine('d')]));
      // no stray carriage return retained on a line
      expect(CodeLines.fromText('a\r\nb')[0].text, 'a');
    });

    test('a trailing newline yields a trailing empty line', () {
      expect(CodeLines.fromText('a\nb\n'),
          CodeLines.of(const [CodeLine('a'), CodeLine('b'), CodeLine('')]));
      expect(CodeLines.fromText('a\nb').length, 2); // no trailing newline -> no extra line
    });

    test('an empty string is a single empty line', () {
      final CodeLines cl = CodeLines.fromText('');
      expect(cl.length, 1);
      expect(cl[0], CodeLine.empty);
    });

    test('a single very long line parses to one CodeLine and stays valid', () {
      final CodeLines cl = CodeLines.fromText('x' * 200000);
      expect(cl.length, 1);
      expect(cl[0].text.length, 200000);
      cl.debugValidate();
    });
  });

}