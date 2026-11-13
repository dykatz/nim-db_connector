## SQL-aware formatting for the legacy MySQL text-protocol API only.
import std/strutils
import ../db_common

type
  TokenKind = enum word, number, parameter, quoted, symbol
  Token = object
    kind: TokenKind
    first, last: int # half-open source span

proc formatMysql*[Q](sql: string; args: openArray[string]; quote: Q;
                    noBackslashEscapes = false; ansiQuotes = false): string =
  var tokens: seq[Token]
  var i = 0
  while i < sql.len:
    let start = i
    let c = sql[i]
    if c in {' ', '\t', '\r', '\n', '\v', '\f'}:
      inc i
    elif c == '#' or (c == '-' and i+1 < sql.len and sql[i+1] == '-' and
        (i+2 == sql.len or ord(sql[i+2]) <= 32)):
      while i < sql.len and sql[i] notin {'\r', '\n'}: inc i
    elif c == '/' and i+1 < sql.len and sql[i+1] == '*':
      let executable = (i+2 < sql.len and sql[i+2] == '!') or
        (i+3 < sql.len and sql[i+2] == 'M' and sql[i+3] == '!')
      i += 2
      while i+1 < sql.len and not (sql[i] == '*' and sql[i+1] == '/'):
        if executable and sql[i] == '?':
          dbError("legacy MySQL parameters inside executable comments are not supported")
        inc i
      if i+1 >= sql.len: dbError("unterminated SQL comment")
      i += 2
    elif c in {'\'', '"', '`'}:
      let backslash = not noBackslashEscapes and (c == '\'' or (c == '"' and not ansiQuotes))
      inc i
      var closed = false
      while i < sql.len:
        if backslash and sql[i] == '\\':
          i += 2
        elif sql[i] == c:
          inc i
          if i < sql.len and sql[i] == c: inc i
          else:
            closed = true
            break
        else: inc i
      if not closed: dbError("unterminated SQL quoted value or identifier")
      tokens.add Token(kind: quoted, first: start, last: i)
    elif c in {'a'..'z', 'A'..'Z', '_', '$', '\128'..'\255'}:
      inc i
      while i < sql.len and sql[i] in {'a'..'z', 'A'..'Z', '0'..'9', '_', '$', '\128'..'\255'}: inc i
      tokens.add Token(kind: word, first: start, last: i)
    elif c in {'0'..'9'}:
      inc i
      while i < sql.len and sql[i] in {'0'..'9'}: inc i
      tokens.add Token(kind: number, first: start, last: i)
    else:
      inc i
      tokens.add Token(kind: (if c == '?': parameter else: symbol), first: start, last: i)

  proc keyword(index: int; value: string): bool =
    index >= 0 and tokens[index].kind == word and
      cmpIgnoreCase(sql[tokens[index].first ..< tokens[index].last], value) == 0

  proc comma(index: int): bool =
    index >= 0 and tokens[index].kind == symbol and sql[tokens[index].first] == ','

  var pagination = newSeq[bool](tokens.len)
  for index in 0..<tokens.len:
    if not keyword(index, "limit"): continue
    # Reserved words can be unquoted identifiers after a dot in MySQL.
    if index > 0 and tokens[index-1].kind == symbol and sql[tokens[index-1].first] == '.': continue
    let first = index + 1
    if first >= tokens.len or tokens[first].kind notin {number, parameter}: continue
    pagination[first] = tokens[first].kind == parameter
    let separator = first + 1
    let second = first + 2
    if second < tokens.len and (comma(separator) or keyword(separator, "offset")):
      pagination[second] = tokens[second].kind == parameter

  var count = 0
  for token in tokens:
    if token.kind == parameter: inc count
  if count != args.len: dbError("MySQL placeholder count does not match argument count")

  var copied = 0
  var arg = 0
  var formatted = ""
  for index, token in tokens:
    if token.kind != parameter: continue
    formatted.add sql[copied ..< token.first]
    if pagination[index]:
      # Never infer numeric types elsewhere. Only direct LIMIT/OFFSET slots
      # accept unquoted values, validated against MySQL's uint64 range.
      let value = args[arg]
      if value.len == 0 or not value.allCharsInSet({'0'..'9'}):
        dbError("MySQL LIMIT/OFFSET arguments must be unsigned decimal integers")
      var number = 0'u64
      for digit in value:
        let d = uint64(ord(digit) - ord('0'))
        if number > (high(uint64) - d) div 10:
          dbError("MySQL LIMIT/OFFSET argument exceeds uint64")
        number = number * 10 + d
      formatted.add $number
    else:
      formatted.add quote(args[arg])
    inc arg
    copied = token.last
  formatted.add sql[copied ..< sql.len]
  result = move(formatted)

proc formatMysqlSafe*[Q](sql: string; args: openArray[string]; quote: Q;
                        noBackslashEscapes = false): string =
  # Oracle does not expose ANSI_QUOTES in a portable client status flag.
  # An extra SELECT @@sql_mode would change ROW_COUNT()/FOUND_ROWS() and other
  # session diagnostics. Require identical formatting under both interpretations
  # of double quotes instead. They differ only in backslash handling.
  if not noBackslashEscapes and '"' in sql and '\\' in sql:
    var formatted: string
    var alternative: string
    try:
      formatted = formatMysql(sql, args, quote, false, false)
      alternative = formatMysql(sql, args, quote, false, true)
    except DbError:
      dbError("ambiguous double-quoted MySQL template; use single-quoted strings or backtick identifiers")
    if formatted != alternative:
      dbError("ambiguous double-quoted MySQL template; use single-quoted strings or backtick identifiers")
    result = move(formatted)
  else:
    result = formatMysql(sql, args, quote, noBackslashEscapes)
