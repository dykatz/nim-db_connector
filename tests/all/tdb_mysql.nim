import ../../src/db_connector/[db_mysql]
import std/assertions
import ../../src/db_connector/private/mysql_format
import std/strutils

doAssert dbQuote("SELECT * FROM foo WHERE col1 = 'bar_baz'") == "'SELECT * FROM foo WHERE col1 = \\'bar_baz\\''"
doAssert dbQuote("SELECT * FROM foo WHERE col1 LIKE '%bar_baz%'") == "'SELECT * FROM foo WHERE col1 LIKE \\'%bar_baz%\\''"

proc quote(s: string): string = "'" & s.replace("'", "''") & "'"
doAssert formatMysql("SELECT ? LIMIT ? OFFSET ?", ["001", "10", "020"], quote) ==
  "SELECT '001' LIMIT 10 OFFSET 20"
doAssert formatMysql("SELECT ? LIMIT ?, ?", ["x", "20", "10"], quote) ==
  "SELECT 'x' LIMIT 20, 10"
doAssert formatMysql("SELECT ? LIMIT 20, ?", ["x", "10"], quote) ==
  "SELECT 'x' LIMIT 20, 10"
doAssert formatMysql("SELECT ? LIMIT /* comment ? */ ? OFFSET -- comment ?\n ?", ["x", "10", "20"], quote) ==
  "SELECT 'x' LIMIT /* comment ? */ 10 OFFSET -- comment ?\n 20"
doAssert formatMysql("SELECT '?', 'it''s ?', `a``?`, \"?\", ? # ?\n", ["value"], quote) ==
  "SELECT '?', 'it''s ?', `a``?`, \"?\", 'value' # ?\n"
doAssert formatMysql("SELECT 'a\\'?', ?", ["value"], quote) == "SELECT 'a\\'?', 'value'"
doAssert formatMysql("SELECT \"a\\\"?\", ?", ["value"], quote) == "SELECT \"a\\\"?\", 'value'"
doAssert formatMysql("SELECT 'a\\', ?", ["value"], quote, noBackslashEscapes = true) ==
  "SELECT 'a\\', 'value'"
doAssert formatMysql("SELECT \"a\\\", ?", ["value"], quote, ansiQuotes = true) ==
  "SELECT \"a\\\", 'value'"
doAssert formatMysql("SELECT ? AS `limit`, ? AS `offset`", ["001", "2"], quote) ==
  "SELECT '001' AS `limit`, '2' AS `offset`"
doAssert formatMysql("SELECT t.limit ? FROM t", ["alias"], quote) ==
  "SELECT t.limit 'alias' FROM t"
doAssert formatMysql("SELECT offset ? FROM t", ["alias"], quote) ==
  "SELECT offset 'alias' FROM t"
doAssert formatMysql("SELECT ? /* LIMIT ? */, ?", ["001", "2"], quote) ==
  "SELECT '001' /* LIMIT ? */, '2'"
doAssert formatMysql("SELECT ? --not_a_comment ?", ["one", "two"], quote) ==
  "SELECT 'one' --not_a_comment 'two'"
doAssert formatMysql("SELECT ? LIMIT ?", ["x", $high(uint64)], quote) ==
  "SELECT 'x' LIMIT 18446744073709551615"
doAssert formatMysqlSafe("SELECT ? AS \"?\", 'a\\\\b'", ["value"], quote) ==
  "SELECT 'value' AS \"?\", 'a\\\\b'"
doAssert formatMysqlSafe("SELECT \"a\\\", ?", ["value"], quote, noBackslashEscapes = true) ==
  "SELECT \"a\\\", 'value'"
var ambiguousRejected = false
try: discard formatMysqlSafe("SELECT \"a\\\"?\", ?", ["value"], quote)
except DbError: ambiguousRejected = true
doAssert ambiguousRejected

for invalid in ["", "-1", "+1", "1.0", " 1", "1 ", "1e2", "0x10", "1 OR 1=1", "1; SELECT 1", "18446744073709551616"]:
  for query in ["SELECT ? LIMIT ?", "SELECT ? LIMIT 1 OFFSET ?", "SELECT ? LIMIT 1, ?"]:
    var rejected = false
    try: discard formatMysql(query, ["x", invalid], quote)
    except DbError: rejected = true
    doAssert rejected, query & " must reject invalid pagination"

for query in ["SELECT ?", "SELECT ?, ?", "SELECT /*! ? */ 1", "SELECT /*M! ? */ 1", "SELECT 'unterminated ?", "SELECT /* unterminated ?"]:
  var rejected = false
  try: discard formatMysql(query, ["x", "y", "z"], quote)
  except DbError: rejected = true
  doAssert rejected
