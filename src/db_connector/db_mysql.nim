#
#
#            Nim's Runtime Library
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## .. note:: In order to use this module, run `nimble install db_connector`.
##
## A higher level `mySQL`:idx: database wrapper. The same interface is
## implemented for other databases too.
##
## See also: `db_odbc <db_odbc.html>`_, `db_sqlite <db_sqlite.html>`_,
## `db_postgres <db_postgres.html>`_.
##
## Parameter substitution
## ======================
##
## All `db_*` modules support the same form of parameter substitution.
## That is, using the `?` (question mark) to signify the place where a
## value should be placed. For example:
##   ```
##   sql"INSERT INTO myTable (colA, colB, colC) VALUES (?, ?, ?)"
##   ```
##
## Examples
## ========
##
## Opening a connection to a database
## ----------------------------------
##
##   ```
##   import db_connector/db_mysql
##   let db = open("localhost", "user", "password", "dbname")
##   db.close()
##   ```
##
## Creating a table
## ----------------
##
##   ```
##   db.exec(sql"DROP TABLE IF EXISTS myTable")
##   db.exec(sql("""CREATE TABLE myTable (
##                    id integer,
##                    name varchar(50) not null)"""))
##   ```
##
## Inserting data
## --------------
##
##   ```
##   db.exec(sql"INSERT INTO myTable (id, name) VALUES (0, ?)",
##           "Dominik")
##   ```
##
## Larger example
## --------------
##
##   ```
##   import db_connector/db_mysql
##   import std/math
##
##   let theDb = open("localhost", "nim", "nim", "test")
##
##   theDb.exec(sql"Drop table if exists myTestTbl")
##   theDb.exec(sql("create table myTestTbl (" &
##       " Id    INT(11)     NOT NULL AUTO_INCREMENT PRIMARY KEY, " &
##       " Name  VARCHAR(50) NOT NULL, " &
##       " i     INT(11), " &
##       " f     DECIMAL(18,10))"))
##
##   theDb.exec(sql"START TRANSACTION")
##   for i in 1..1000:
##     theDb.exec(sql"INSERT INTO myTestTbl (name,i,f) VALUES (?,?,?)",
##           "Item#" & $i, i, sqrt(i.float))
##   theDb.exec(sql"COMMIT")
##
##   for x in theDb.fastRows(sql"select * from myTestTbl"):
##     echo x
##
##   let id = theDb.tryInsertId(sql"INSERT INTO myTestTbl (name,i,f) VALUES (?,?,?)",
##           "Item#1001", 1001, sqrt(1001.0))
##   echo "Inserted item: ", theDb.getValue(sql"SELECT name FROM myTestTbl WHERE id=?", id)
##
##   theDb.close()
##   ```


import strutils, ./mysql

import ./db_common
export db_common

import ./private/dbutils
import std/private/[since]

type
  DbConn* = distinct PMySQL ## encapsulates a database connection
  Row* = seq[string]   ## a row of a dataset. NULL database values will be
                       ## converted to empty strings.
  InstantRow* = object ## a handle that can be used to get a row's
                       ## column text on demand
    row: cstringArray
    lengths: ptr UncheckedArray[culong]
    len: int

proc dbError*(db: DbConn) {.noreturn.} =
  ## raises a DbError exception.
  var e: ref DbError
  new(e)
  e.msg = $mysql.error(PMySQL db)
  raise e

proc dbQuote*(s: string): string =
  ## DB quotes the string. Note that this doesn't escape `%` and `_`.
  ## Legacy only: assumes backslash escapes and a compatible charset. Unsafe
  ## with NO_BACKSLASH_ESCAPES. Use prepare/bindParam for untrusted values.
  result = newStringOfCap(s.len + 2)
  result.add "'"
  for c in items(s):
    # see https://cheatsheetseries.owasp.org/cheatsheets/SQL_Injection_Prevention_Cheat_Sheet.html#mysql-escaping
    case c
    of '\0': result.add "\\0"
    of '\b': result.add "\\b"
    of '\t': result.add "\\t"
    of '\l': result.add "\\n"
    of '\r': result.add "\\r"
    of '\x1a': result.add "\\Z"
    of '"': result.add "\\\""
    of '\'': result.add "\\'"
    of '\\': result.add "\\\\"
    else: result.add c
  add(result, '\'')

proc dbFormat(formatstr: SqlQuery, args: varargs[string]): string =
  dbFormatImpl(formatstr, dbQuote, args)

proc rawExec(db: DbConn, query: SqlQuery, args: varargs[string, `$`]) =
  var q = dbFormat(query, args)
  if mysql.real_query(PMySQL db, q.cstring, culong(q.len)) != 0: dbError(db)

proc discardResults(db: DbConn; current = true) =
  ## Consume all remaining text-protocol results, including CALL status results.
  var consume = current
  while true:
    if consume:
      let res = mysql.store_result(PMySQL db)
      if res != nil: mysql.free_result(res)
      elif mysql.field_count(PMySQL db) != 0: dbError(db)
    let status = mysql.next_result(PMySQL db)
    if status < 0: break
    if status > 0: dbError(db)
    consume = true

proc queryResult(db: DbConn): PRES =
  result = mysql.store_result(PMySQL db)
  if result == nil and mysql.field_count(PMySQL db) != 0: dbError(db)

proc finishResult(db: DbConn; res: PRES) =
  if res != nil: mysql.free_result(res)
  discardResults(db, false)

proc copyColumn(data: cstring; length: culong): string =
  if data == nil: return ""
  if uint64(length) > uint64(high(int)): dbError("column exceeds Nim string size")
  result = newString(int(length))
  if length != 0: copyMem(addr result[0], data, int(length))

proc fetchRow(db: DbConn; res: PRES): cstringArray =
  result = mysql.fetch_row(res)
  if result == nil and mysql.errno(PMySQL db) != 0: dbError(db)

proc tryExec*(db: DbConn, query: SqlQuery, args: varargs[string, `$`]): bool {.
  tags: [ReadDbEffect, WriteDbEffect].} =
  ## Executes using the text protocol and discards any returned results.
  try:
    rawExec(db, query, args)
    discardResults(db)
    result = true
  except DbError:
    result = false

proc exec*(db: DbConn, query: SqlQuery, args: varargs[string, `$`]) {.
  tags: [ReadDbEffect, WriteDbEffect].} =
  ## executes the query and raises EDB if not successful.
  rawExec(db, query, args)
  discardResults(db)

proc newRow(L: int): Row =
  newSeq(result, L)
  for i in 0..L-1: result[i] = ""

iterator fastRows*(db: DbConn, query: SqlQuery,
                   args: varargs[string, `$`]): Row {.tags: [ReadDbEffect].} =
  ## Iterates a buffered result. Early exits release all resources.
  rawExec(db, query, args)
  let sqlres = queryResult(db)
  try:
    if sqlres != nil:
      let L = int(mysql.numFields(sqlres))
      while true:
        let row = fetchRow(db, sqlres)
        if row == nil: break
        let lengths = mysql.fetch_lengths(sqlres)
        var value = newRow(L)
        for i in 0..<L: value[i] = copyColumn(row[i], lengths[i])
        yield value
  finally:
    finishResult(db, sqlres)

iterator instantRows*(db: DbConn, query: SqlQuery,
                      args: varargs[string, `$`]): InstantRow
                      {.tags: [ReadDbEffect].} =
  ## Same as fastRows but returns a handle that can be used to get column text
  ## on demand using `[]`. Returned handle is valid only within the iterator body.
  rawExec(db, query, args)
  let sqlres = queryResult(db)
  try:
    if sqlres != nil:
      let L = int(mysql.numFields(sqlres))
      while true:
        let row = fetchRow(db, sqlres)
        if row == nil: break
        yield InstantRow(row: row, lengths: mysql.fetch_lengths(sqlres), len: L)
  finally:
    finishResult(db, sqlres)

proc setTypeName(t: var DbType; f: PFIELD) =
  t.name = $f.name
  t.maxReprLen = Natural(f.max_length)
  if (NOT_NULL_FLAG and f.flags) != 0: t.notNull = true
  case f.ftype
  of TYPE_DECIMAL:
    t.kind = dbDecimal
  of TYPE_TINY:
    t.kind = dbInt
    t.size = 1
  of TYPE_SHORT:
    t.kind = dbInt
    t.size = 2
  of TYPE_LONG:
    t.kind = dbInt
    t.size = 4
  of TYPE_FLOAT:
    t.kind = dbFloat
    t.size = 4
  of TYPE_DOUBLE:
    t.kind = dbFloat
    t.size = 8
  of TYPE_NULL:
    t.kind = dbNull
  of TYPE_TIMESTAMP:
    t.kind = dbTimestamp
  of TYPE_LONGLONG:
    t.kind = dbInt
    t.size = 8
  of TYPE_INT24:
    t.kind = dbInt
    t.size = 3
  of TYPE_DATE:
    t.kind = dbDate
  of TYPE_TIME:
    t.kind = dbTime
  of TYPE_DATETIME:
    t.kind = dbDatetime
  of TYPE_YEAR:
    t.kind = dbDate
  of TYPE_NEWDATE:
    t.kind = dbDate
  of TYPE_VARCHAR, TYPE_VAR_STRING, TYPE_STRING:
    t.kind = dbVarchar
  of TYPE_BIT:
    t.kind = dbBit
  of TYPE_NEWDECIMAL:
    t.kind = dbDecimal
  of TYPE_ENUM: t.kind = dbEnum
  of TYPE_SET: t.kind = dbSet
  of TYPE_TINY_BLOB, TYPE_MEDIUM_BLOB, TYPE_LONG_BLOB,
     TYPE_BLOB: t.kind = dbBlob
  of TYPE_GEOMETRY:
    t.kind = dbGeometry
  of TYPE_JSON:
    t.kind = dbVarchar

proc setColumnInfo(columns: var DbColumns; res: PRES; L: int) =
  setLen(columns, L)
  for i in 0..<L:
    let fp = mysql.fetch_field_direct(res, cuint(i))
    setTypeName(columns[i].typ, fp)
    columns[i].name = $fp.name
    columns[i].tableName = $fp.table
    columns[i].primaryKey = (fp.flags and PRI_KEY_FLAG) != 0
    #columns[i].foreignKey = there is no such thing in mysql

iterator instantRows*(db: DbConn; columns: var DbColumns; query: SqlQuery;
                      args: varargs[string, `$`]): InstantRow =
  ## Same as fastRows but returns a handle that can be used to get column text
  ## on demand using `[]`. Returned handle is valid only within the iterator body.
  rawExec(db, query, args)
  let sqlres = queryResult(db)
  try:
    if sqlres != nil:
      let L = int(mysql.numFields(sqlres))
      setColumnInfo(columns, sqlres, L)
      while true:
        let row = fetchRow(db, sqlres)
        if row == nil: break
        yield InstantRow(row: row, lengths: mysql.fetch_lengths(sqlres), len: L)
  finally:
    finishResult(db, sqlres)


proc `[]`*(row: InstantRow, col: int): string {.inline.} =
  ## Returns text for given column of the row.
  if col < 0 or col >= row.len: raise newException(IndexDefect, "column index")
  copyColumn(row.row[col], row.lengths[col])

proc unsafeColumnAt*(row: InstantRow, index: int): cstring {.inline.} =
  ## Return cstring of given column of the row
  row.row[index]

proc len*(row: InstantRow): int {.inline.} =
  ## Returns number of columns in the row.
  row.len

proc getRow*(db: DbConn, query: SqlQuery,
             args: varargs[string, `$`]): Row {.tags: [ReadDbEffect].} =
  ## Retrieves a single row. If the query doesn't return any rows, this proc
  ## will return a Row with empty strings for each column.
  rawExec(db, query, args)
  let sqlres = queryResult(db)
  try:
    if sqlres != nil:
      let L = int(mysql.numFields(sqlres))
      result = newRow(L)
      let row = fetchRow(db, sqlres)
      if row != nil:
        let lengths = mysql.fetch_lengths(sqlres)
        for i in 0..<L: result[i] = copyColumn(row[i], lengths[i])
  finally:
    finishResult(db, sqlres)

proc getAllRows*(db: DbConn, query: SqlQuery,
                 args: varargs[string, `$`]): seq[Row] {.tags: [ReadDbEffect].} =
  ## executes the query and returns the whole result dataset.
  for row in fastRows(db, query, args): result.add row

iterator rows*(db: DbConn, query: SqlQuery,
               args: varargs[string, `$`]): Row {.tags: [ReadDbEffect].} =
  ## same as `fastRows`, but slower and safe.
  for r in items(getAllRows(db, query, args)): yield r

proc getValue*(db: DbConn, query: SqlQuery,
               args: varargs[string, `$`]): string {.tags: [ReadDbEffect].} =
  ## executes the query and returns the first column of the first row of the
  ## result dataset. Returns "" if the dataset contains no rows or the database
  ## value is NULL.
  let row = getRow(db, query, args)
  if row.len > 0: result = row[0]

proc tryInsertId*(db: DbConn, query: SqlQuery,
                  args: varargs[string, `$`]): int64 {.tags: [WriteDbEffect], raises: [DbError].} =
  ## executes the query (typically "INSERT") and returns the
  ## generated ID for the row or -1 in case of an error.
  try:
    rawExec(db, query, args)
  except DbError:
    return -1'i64
  let id = mysql.insertId(PMySQL db)
  discardResults(db)
  if id > uint64(high(int64)): dbError("insert ID exceeds int64; use native statements")
  result = int64(id)

proc insertId*(db: DbConn, query: SqlQuery,
               args: varargs[string, `$`]): int64 {.tags: [WriteDbEffect].} =
  ## executes the query (typically "INSERT") and returns the
  ## generated ID for the row.
  result = tryInsertID(db, query, args)
  if result < 0: dbError(db)

proc tryInsert*(db: DbConn, query: SqlQuery, pkName: string,
                args: varargs[string, `$`]): int64
               {.tags: [WriteDbEffect], raises: [DbError], since: (1, 3).} =
  ## same as tryInsertID
  tryInsertID(db, query, args)

proc insert*(db: DbConn, query: SqlQuery, pkName: string,
             args: varargs[string, `$`]): int64
            {.tags: [WriteDbEffect], since: (1, 3).} =
  ## same as insertId
  result = tryInsert(db, query,pkName, args)
  if result < 0: dbError(db)

proc execAffectedRows*(db: DbConn, query: SqlQuery,
                       args: varargs[string, `$`]): int64 {.
                       tags: [ReadDbEffect, WriteDbEffect].} =
  ## runs the query (typically "UPDATE") and returns the
  ## number of affected rows
  rawExec(db, query, args)
  let count = mysql.affectedRows(PMySQL db)
  discardResults(db)
  if count > uint64(high(int64)): dbError("affected row count exceeds int64")
  result = int64(count)

proc close*(db: DbConn) {.tags: [DbEffect].} =
  ## closes the database connection.
  if PMySQL(db) != nil: mysql.close(PMySQL db)

proc open*(connection, user, password, database: string; socket = ""): DbConn {.
  tags: [DbEffect].} =
  ## opens a database connection. Raises `EDb` if the connection could not
  ## be established.
  ## Pass socket explicitly for Unix-socket connections (host should be localhost).
  let
    colonPos = connection.find(':')
    host = if colonPos < 0: connection
           else: substr(connection, 0, colonPos-1)
    portNumber = if colonPos < 0: 0 else: substr(connection, colonPos+1).parseInt
  if portNumber < 0 or portNumber > 65535: dbError("invalid MySQL port")
  var res = mysql.init(nil)
  if res == nil: dbError("could not open database connection")
  if mysql.realConnect(res, host.cstring, user, password, database,
                       cuint(portNumber), (if socket.len == 0: nil else: socket.cstring), 0) == nil:
    var errmsg = $mysql.error(res)
    mysql.close(res)
    dbError(errmsg)
  result = DbConn(res)

proc setEncoding*(connection: DbConn, encoding: string): bool {.
  tags: [DbEffect].} =
  ## sets the encoding of a database connection, returns true for
  ## success, false for failure.
  result = mysql.set_character_set(PMySQL connection, encoding) == 0

type
  DbValueKind* = enum
    dvNull, dvInt, dvUInt, dvFloat, dvText, dvBlob
  DbValue* = object
    ## Native input value or fetched value. Results use dvNull/dvText/dvBlob;
    ## numeric results retain exact server text in data.
    kind*: DbValueKind
    intValue*: int64
    uintValue*: uint64
    floatValue*: float64
    data*: string
  SqlPrepared* = ref object
    ## Explicitly owned native statement; finalize before closing its connection.
    handle: PSTMT
    params: seq[DbValue]
    bound: seq[bool]
    input: seq[BIND]
    inputLengths: seq[culong]
    output: seq[BIND]
    outputBuffers: seq[string]
    lengths: seq[culong]
    nulls, errors: seq[my_bool]
    binary: seq[bool]
    executed, exhausted: bool
  MysqlError* = object of DbError
    code*: uint32
    sqlState*: string

proc checkOpen(stmt: SqlPrepared) =
  if stmt == nil or stmt.handle == nil: dbError("statement is closed")

proc statementError(stmt: SqlPrepared) {.noreturn.} =
  let e = newException(MysqlError, $mysql.stmt_error(stmt.handle))
  e.code = uint32(mysql.stmt_errno(stmt.handle))
  e.sqlState = $mysql.stmt_sqlstate(stmt.handle)
  raise e

proc prepare*(db: DbConn; query: string): SqlPrepared =
  ## Prepare native SQL. Transaction control should use text-protocol exec.
  new(result)
  result.handle = mysql.stmt_init(PMySQL db)
  if result.handle == nil: dbError(db)
  try:
    if mysql.stmt_prepare(result.handle, query.cstring, culong(query.len)) != 0:
      statementError(result)
    let count = mysql.stmt_param_count(result.handle)
    if uint64(count) > uint64(high(int)): dbError("too many statement parameters")
    result.params = newSeq[DbValue](int(count))
    result.bound = newSeq[bool](int(count))
  except:
    discard mysql.stmt_close(result.handle)
    result.handle = nil
    raise

proc parameterCount*(stmt: SqlPrepared): int =
  checkOpen(stmt)
  stmt.params.len

proc bindParam*(stmt: SqlPrepared; paramIdx: int; value: DbValue) =
  ## One-based index. Values are owned by the statement, not borrowed.
  checkOpen(stmt)
  if paramIdx < 1 or paramIdx > stmt.params.len: dbError("parameter index out of range")
  stmt.params[paramIdx - 1] = value
  # Force a copy even with legacy Nim string memory managers.
  if value.kind in {dvText, dvBlob}:
    stmt.params[paramIdx - 1].data = copyColumn(value.data.cstring, culong(value.data.len))
  stmt.bound[paramIdx - 1] = true

proc bindNull*(stmt: SqlPrepared; paramIdx: int) =
  stmt.bindParam(paramIdx, DbValue(kind: dvNull))

proc bindParam*[T: SomeInteger](stmt: SqlPrepared; paramIdx: int; value: T) =
  when T is SomeUnsignedInt:
    stmt.bindParam(paramIdx, DbValue(kind: dvUInt, uintValue: uint64(value)))
  else:
    stmt.bindParam(paramIdx, DbValue(kind: dvInt, intValue: int64(value)))

proc bindParam*(stmt: SqlPrepared; paramIdx: int; value: float64) =
  stmt.bindParam(paramIdx, DbValue(kind: dvFloat, floatValue: value))

proc bindParam*(stmt: SqlPrepared; paramIdx: int; value: string) =
  stmt.bindParam(paramIdx, DbValue(kind: dvText, data: value))

proc bindParam*(stmt: SqlPrepared; paramIdx: int; value: openArray[byte]) =
  var data = newString(value.len)
  if value.len > 0: copyMem(addr data[0], unsafeAddr value[0], value.len)
  stmt.bindParam(paramIdx, DbValue(kind: dvBlob, data: data))

proc clearResults(stmt: SqlPrepared) =
  if not stmt.executed: return
  if mysql.stmt_field_count(stmt.handle) > 0 and mysql.stmt_free_result(stmt.handle):
    statementError(stmt)
  while true:
    let status = mysql.stmt_next_result(stmt.handle)
    if status < 0: break
    if status > 0: statementError(stmt)
    if mysql.stmt_field_count(stmt.handle) > 0:
      if mysql.stmt_store_result(stmt.handle) != 0: statementError(stmt)
      if mysql.stmt_free_result(stmt.handle): statementError(stmt)
  stmt.executed = false
  stmt.exhausted = true

proc reset*(stmt: SqlPrepared) =
  ## Discard results and reset execution state, retaining parameter values.
  checkOpen(stmt)
  clearResults(stmt)
  if mysql.stmt_reset(stmt.handle): statementError(stmt)

proc finalize*(stmt: SqlPrepared) =
  ## Close exactly once. All aliases to the reference become closed.
  if stmt != nil and stmt.handle != nil:
    let handle = stmt.handle
    stmt.handle = nil
    # stmt_close frees the handle even on failure: never read it afterwards.
    let failed = mysql.stmt_close(handle)
    stmt.params.setLen(0)
    stmt.bound.setLen(0)
    stmt.input.setLen(0)
    stmt.inputLengths.setLen(0)
    stmt.output.setLen(0)
    stmt.outputBuffers.setLen(0)
    stmt.lengths.setLen(0)
    stmt.nulls.setLen(0)
    stmt.errors.setLen(0)
    stmt.binary.setLen(0)
    if failed: dbError("mysql_stmt_close failed (statement has been released)")

proc close*(stmt: SqlPrepared) = stmt.finalize()

proc exec*(stmt: SqlPrepared) {.tags: [ReadDbEffect, WriteDbEffect].} =
  ## Execute with retained bindings and buffer the first result set.
  checkOpen(stmt)
  clearResults(stmt)
  for bound in stmt.bound:
    if not bound: dbError("all statement parameters must be bound")
  stmt.input = newSeq[BIND](stmt.params.len)
  stmt.inputLengths = newSeq[culong](stmt.params.len)
  for i in 0..<stmt.params.len:
    template p: untyped = stmt.params[i]
    template b: untyped = stmt.input[i]
    case p.kind
    of dvNull: b.buffer_type = TYPE_NULL
    of dvInt:
      b.buffer_type = TYPE_LONGLONG
      b.buffer = addr p.intValue
    of dvUInt:
      b.buffer_type = TYPE_LONGLONG
      b.is_unsigned = true
      b.buffer = addr p.uintValue
    of dvFloat:
      b.buffer_type = TYPE_DOUBLE
      b.buffer = addr p.floatValue
    of dvText, dvBlob:
      b.buffer_type = if p.kind == dvText: TYPE_STRING else: TYPE_BLOB
      stmt.inputLengths[i] = culong(p.data.len)
      b.len = addr stmt.inputLengths[i]
      b.buffer_length = stmt.inputLengths[i]
      b.buffer = cast[pointer](p.data.cstring)
  if stmt.input.len > 0 and mysql.stmt_bind_param(stmt.handle, addr stmt.input[0]):
    statementError(stmt)
  if mysql.stmt_execute(stmt.handle) != 0: statementError(stmt)
  stmt.executed = true
  stmt.exhausted = false
  if mysql.stmt_store_result(stmt.handle) != 0: statementError(stmt)
  let count = int(mysql.stmt_field_count(stmt.handle))
  stmt.output = newSeq[BIND](count)
  stmt.outputBuffers = newSeq[string](count)
  stmt.lengths = newSeq[culong](count)
  stmt.nulls = newSeq[my_bool](count)
  stmt.errors = newSeq[my_bool](count)
  stmt.binary = newSeq[bool](count)
  if count > 0:
    let meta = mysql.stmt_result_metadata(stmt.handle)
    if meta == nil: statementError(stmt)
    try:
      for i in 0..<count:
        let field = mysql.fetch_field_direct(meta, cuint(i))
        stmt.binary[i] = (field.flags and BINARY_FLAG) != 0 and
          field.ftype in {TYPE_TINY_BLOB, TYPE_MEDIUM_BLOB, TYPE_LONG_BLOB,
                         TYPE_BLOB, TYPE_STRING, TYPE_VAR_STRING, TYPE_VARCHAR, TYPE_BIT, TYPE_GEOMETRY}
        stmt.output[i].buffer_type = if stmt.binary[i]: TYPE_BLOB else: TYPE_STRING
        # Some clients do not report float-to-text lengths for a zero-sized
        # buffer. A small initial buffer also avoids refetching short values.
        stmt.outputBuffers[i] = newString(256)
        stmt.output[i].buffer = addr stmt.outputBuffers[i][0]
        stmt.output[i].buffer_length = 256
        stmt.output[i].len = addr stmt.lengths[i]
        stmt.output[i].is_null = addr stmt.nulls[i]
        stmt.output[i].error = addr stmt.errors[i]
    finally:
      mysql.free_result(meta)
    # fetch_column recovers values exceeding the initial buffer in full.
    if mysql.stmt_bind_result(stmt.handle, addr stmt.output[0]): statementError(stmt)

proc fetch*(stmt: SqlPrepared; row: var seq[DbValue]): bool {.tags: [ReadDbEffect].} =
  ## False at end of first result. A NULL differs from an empty text/blob value.
  checkOpen(stmt)
  if not stmt.executed: dbError("statement has not been executed")
  row.setLen(0)
  if stmt.exhausted or stmt.output.len == 0: return false
  let status = mysql.stmt_fetch(stmt.handle)
  if status == NO_DATA:
    stmt.exhausted = true
    return false
  if status != 0 and status != DATA_TRUNCATED: statementError(stmt)
  row = newSeq[DbValue](stmt.output.len)
  for i in 0..<row.len:
    if stmt.nulls[i]:
      row[i].kind = dvNull
    else:
      row[i].kind = if stmt.binary[i]: dvBlob else: dvText
      if stmt.errors[i] and stmt.lengths[i] <= culong(stmt.outputBuffers[i].len):
        dbError("prepared result conversion failed without a larger column length")
      if uint64(stmt.lengths[i]) > uint64(high(int)): dbError("column exceeds Nim string size")
      row[i].data = newString(int(stmt.lengths[i]))
      if row[i].data.len > 0 and row[i].data.len <= stmt.outputBuffers[i].len:
        copyMem(addr row[i].data[0], addr stmt.outputBuffers[i][0], row[i].data.len)
      elif row[i].data.len > 0:
        var binding: BIND
        var length: culong
        var isNull, truncated: my_bool
        binding.buffer_type = stmt.output[i].buffer_type
        binding.buffer = addr row[i].data[0]
        binding.buffer_length = stmt.lengths[i]
        binding.len = addr length
        binding.is_null = addr isNull
        binding.error = addr truncated
        if mysql.stmt_fetch_column(stmt.handle, addr binding, cuint(i), 0) != 0:
          statementError(stmt)
        if truncated or length != stmt.lengths[i]: dbError("incomplete prepared result column")
  result = true

proc affectedRows*(stmt: SqlPrepared): uint64 =
  checkOpen(stmt)
  if not stmt.executed: dbError("statement has not been executed")
  result = uint64(mysql.stmt_affected_rows(stmt.handle))
  if result == high(uint64): statementError(stmt)

proc insertId*(stmt: SqlPrepared): uint64 =
  checkOpen(stmt)
  if not stmt.executed: dbError("statement has not been executed")
  uint64(mysql.stmt_insert_id(stmt.handle))

proc columns*(stmt: SqlPrepared): DbColumns =
  checkOpen(stmt)
  let meta = mysql.stmt_result_metadata(stmt.handle)
  if meta != nil:
    try: setColumnInfo(result, meta, int(mysql.num_fields(meta)))
    finally: mysql.free_result(meta)
