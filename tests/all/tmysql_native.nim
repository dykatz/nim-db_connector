## Integration test: MYSQL_TEST_DATABASE must name a disposable, writable DB.
import ../../src/db_connector/[db_mysql, mysql]
import std/[os, strutils, assertions]

if getEnv("MYSQL_TEST_DATABASE").len == 0:
  echo "SKIP MySQL integration: set MYSQL_TEST_DATABASE (see docs/mysql.md)"
else:
  let db = db_mysql.open(getEnv("MYSQL_TEST_HOST", "localhost"),
    getEnv("MYSQL_TEST_USER", "root"), getEnv("MYSQL_TEST_PASSWORD"),
    getEnv("MYSQL_TEST_DATABASE"), socket = getEnv("MYSQL_TEST_SOCKET"))
  defer: db.close()
  echo "client: ", mysql.get_client_info(), " server: ", mysql.get_server_info(PMySQL(db))
  doAssert db.setEncoding("utf8mb4")
  db.exec(sql"CREATE TEMPORARY TABLE native_values (id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, i BIGINT, u BIGINT UNSIGNED, f DOUBLE, t LONGTEXT, b LONGBLOB, n TEXT) ENGINE=InnoDB")
  let before = db.getRow(sql"SHOW SESSION STATUS LIKE 'Com_stmt_prepare'")[1]
  db.exec(sql"START TRANSACTION")
  db.exec(sql"SAVEPOINT db_connector_outer")
  db.exec(sql"SAVEPOINT db_connector_inner")
  db.exec(sql"ROLLBACK TO SAVEPOINT db_connector_inner")
  db.exec(sql"RELEASE SAVEPOINT db_connector_inner")
  db.exec(sql"ROLLBACK TO SAVEPOINT db_connector_outer")
  db.exec(sql"COMMIT")
  doAssert db.getRow(sql"SHOW SESSION STATUS LIKE 'Com_stmt_prepare'")[1] == before

  let insert = db.prepare("INSERT INTO native_values(i,u,f,t,b,n) VALUES (?,?,?,?,?,?)")
  defer: insert.finalize()
  doAssert insert.parameterCount == 6
  try:
    insert.exec()
    doAssert false
  except DbError: discard
  try:
    insert.bindNull(0)
    doAssert false
  except DbError: discard
  let text = "héllo 世界 ' \\ \0" & repeat("x", 100000)
  let binary = @[0'u8, 255, 1, 0, 128]
  insert.bindParam(1, low(int64))
  insert.bindParam(2, high(uint64))
  insert.bindParam(3, 1.25)
  insert.bindParam(4, text)
  insert.bindParam(5, binary)
  insert.bindNull(6)
  insert.exec()
  doAssert insert.affectedRows == 1
  doAssert insert.insertId > 0
  let select = db.prepare("SELECT i,u,f,t,b,n FROM native_values WHERE id=?")
  defer: select.finalize()
  select.bindParam(1, insert.insertId)
  select.exec()
  doAssert select.columns.len == 6
  var row: seq[DbValue]
  doAssert select.fetch(row)
  doAssert row[0].data == $low(int64)
  doAssert row[1].data == $high(uint64)
  doAssert parseFloat(row[2].data) == 1.25
  doAssert row[3].data == text
  doAssert row[4].kind == dvBlob and row[4].data == "\0\xff\1\0\x80"
  doAssert row[5].kind == dvNull
  doAssert not select.fetch(row)
  doAssert not select.fetch(row)
  select.reset()
  select.exec()
  doAssert select.fetch(row)
  # Re-execution discards unread results, rebinding preserves parameter ownership.
  select.exec()
  doAssert select.fetch(row)
  insert.reset()
  insert.bindParam(1, high(int64))
  insert.bindParam(2, 0'u64)
  insert.bindParam(4, "")
  insert.bindParam(5, newSeq[byte]())
  insert.bindParam(6, "")
  insert.exec()
  select.bindParam(1, insert.insertId)
  select.exec()
  doAssert select.fetch(row)
  doAssert row[0].data == $high(int64)
  doAssert row[3].kind == dvText and row[3].data == ""
  doAssert row[4].kind == dvBlob and row[4].data == ""
  doAssert row[5].kind != dvNull and row[5].data == ""
  let beforeTx = db.getRow(sql"SHOW SESSION STATUS LIKE 'Com_stmt_prepare'")[1]
  db.exec(sql"START TRANSACTION")
  insert.exec()
  db.exec(sql"SAVEPOINT bound_values")
  insert.exec()
  doAssert db.getValue(sql"SELECT COUNT(*) FROM native_values") == "4"
  db.exec(sql"ROLLBACK TO SAVEPOINT bound_values")
  doAssert db.getValue(sql"SELECT COUNT(*) FROM native_values") == "3"
  db.exec(sql"ROLLBACK")
  doAssert db.getValue(sql"SELECT COUNT(*) FROM native_values") == "2"
  doAssert db.getRow(sql"SHOW SESSION STATUS LIKE 'Com_stmt_prepare'")[1] == beforeTx
  select.finalize()
  select.finalize()
  try:
    select.exec()
    doAssert false
  except DbError: discard
  let invalid = "SELECT * FROM db_connector_nonexistent_table"
  try:
    discard db.prepare(invalid)
    doAssert false
  except MysqlError as e:
    doAssert e.code != 0 and e.sqlState.len == 5 and e.msg.len > 0
  let duplicate = db.prepare("INSERT INTO native_values(id) VALUES (?)")
  defer: duplicate.finalize()
  duplicate.bindParam(1, 1)
  try:
    duplicate.exec()
    doAssert false
  except MysqlError as e: doAssert e.code == 1062
  duplicate.reset()
  let largeBlob = db.prepare("SELECT ?")
  try:
    try:
      discard largeBlob.fetch(row)
      doAssert false
    except DbError: discard
    var bytes = newSeq[byte](100000)
    for i in 0..<bytes.len: bytes[i] = byte(i mod 256)
    largeBlob.bindParam(1, bytes)
    largeBlob.exec()
    doAssert largeBlob.fetch(row) and row[0].data.len == bytes.len
    for i in 0..<bytes.len: doAssert byte(row[0].data[i]) == bytes[i]
  finally: largeBlob.finalize()

  # Explicit lengths apply to every legacy result API, not only fastRows.
  doAssert db.getValue(sql"SELECT CONCAT('a', CHAR(0), 'b')") == "a\0b"
  doAssert db.getAllRows(sql"SELECT CONCAT('a', CHAR(0), 'b')")[0][0] == "a\0b"
  for value in db.fastRows(sql"SELECT t FROM native_values ORDER BY id"):
    doAssert value[0] == text
    break
  doAssert db.getValue(sql"SELECT 1") == "1"
  proc earlyReturn(db: DbConn) =
    for value in db.fastRows(sql"SELECT * FROM native_values"):
      return
  earlyReturn(db)
  try:
    for value in db.fastRows(sql"SELECT * FROM native_values"):
      raise newException(ValueError, "iterator exception")
  except ValueError: discard
  doAssert db.getValue(sql"SELECT 2") == "2"
  var columns: DbColumns
  for value in db.instantRows(columns, sql"SELECT CONCAT('a', CHAR(0), 'b') AS binary_value"):
    doAssert value[0] == "a\0b" and columns[0].name == "binary_value"
    break
  for value in db.instantRows(sql"SELECT CONCAT('a', CHAR(0), 'b')"):
    doAssert value[0] == "a\0b"
    break
  doAssert db.getRow(sql"SELECT NULL, ''") == @["", ""]
  db.exec(sql"SELECT 1") # Execution-only calls consume result sets too.
  doAssert db.getValue(sql"SELECT 3") == "3"

  # Stored procedures exercise multiple result sets without enabling arbitrary
  # multi-statement SQL. This database must be disposable and isolated.
  db.exec(sql"CREATE PROCEDURE db_connector_results() BEGIN SELECT 1; SELECT 2; END")
  try:
    doAssert db.getValue(sql"CALL db_connector_results()") == "1"
    doAssert db.getValue(sql"SELECT 4") == "4"
    db.exec(sql"CALL db_connector_results()")
    let call = db.prepare("CALL db_connector_results()")
    try:
      call.exec()
      doAssert call.fetch(row) and row[0].data == "1"
      call.reset()
      doAssert db.getValue(sql"SELECT 5") == "5"
      call.exec()
    finally: call.finalize()
    doAssert db.getValue(sql"SELECT 6") == "6"
  finally: db.exec(sql"DROP PROCEDURE db_connector_results")

  let mode = db.getValue(sql"SELECT @@sql_mode")
  # Legacy quoting is tested only in its documented mode. Native bindings
  # must work in both modes, without connection-independent escaping.
  db.exec(sql"SET sql_mode = ''")
  doAssert db.getValue(sql"SELECT ?", "quotes ' and \\ slash") == "quotes ' and \\ slash"
  db.exec(sql"SET sql_mode = 'NO_BACKSLASH_ESCAPES'")
  let safe = db.prepare("SELECT ?")
  safe.bindParam(1, text)
  safe.exec()
  doAssert safe.fetch(row) and row[0].data == text
  safe.finalize()
  let copied = db.prepare("SELECT ?, ?")
  var mutableText = "original"
  var mutableBytes = @[1'u8, 0, 2]
  copied.bindParam(1, mutableText)
  copied.bindParam(2, mutableBytes)
  mutableText[0] = 'X'
  mutableBytes[0] = 9
  copied.exec()
  doAssert copied.fetch(row) and row[0].data == "original" and row[1].data == "\1\0\2"
  copied.finalize()
  # Restore trusted server-supplied mode (mode tokens contain no quotes).
  db.exec(SqlQuery("SET sql_mode = '" & mode & "'"))

  # Server-side statement count detects native handle leaks. The ASAN job also
  # checks that failed prepares release their Nim wrappers, not just handles.
  let handles = db.getRow(sql"SHOW GLOBAL STATUS LIKE 'Prepared_stmt_count'")[1]
  for i in 0..<25:
    let stmt = db.prepare("SELECT 1")
    stmt.exec()
    stmt.finalize()
    try: discard db.prepare("THIS IS NOT SQL")
    except MysqlError: discard
  doAssert db.getRow(sql"SHOW GLOBAL STATUS LIKE 'Prepared_stmt_count'")[1] == handles
  try:
    discard db_mysql.open("127.0.0.1:1", "invalid", "invalid", "invalid")
    doAssert false
  except DbError: discard
  echo "native MySQL regression tests passed"
