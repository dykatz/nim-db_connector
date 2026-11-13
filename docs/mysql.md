# MySQL/MariaDB architecture and migration

The MySQL driver now compiles against `mysql.h` and links the matching client
library. No handwritten connection, result, or statement layout is used. This
intentionally replaces header-free dynamic loading: install client development
headers as well as the runtime. Do not mix one vendor's headers with the other's
library. The platform linker/loader handles library paths and diagnostics.

Target support is Nim 1.7.3 and newer, Linux, macOS and Windows, Oracle MySQL
8.0/8.4 and MariaDB Connector/C 3.x (including clients bundled with MariaDB).
These are compatibility targets, not a claim that all combinations have been
tested locally. On Unix `mysql_config` supplies flags by default. Select MariaDB
with `-d:mysqlConfig=mariadb_config`. For custom installations or Windows pass
`-d:mysqlCFlags=... -d:mysqlLibs=...` with matching include/link flags. For example
`-d:mysqlCFlags=-IC:/mysql/include -d:mysqlLibs=C:/mysql/lib/libmysql.lib` with
the MSVC backend. Runtime search paths remain the platform loader's responsibility.

Public high-level text-query signatures and NULL-as-empty-string results remain.
The low-level module is reduced to a public client API subset; internal/obsolete
structures, removed server symbols, vendor-specific options, and deprecated
aliases are no longer supported. The shared initial mysql_options entries
(timeouts, protocol and charset) remain. Handles are opaque. C unsigned counts now really are unsigned;
lengths use `culong`, and row offsets are pointers. Users of the low-level module
may need explicit conversions. Legacy signed insert IDs/counts reject overflow;
the prepared API returns unsigned counts.

Native statements are additive: `prepare(db, sqlString)`, one-based `bindParam`
or `bindNull`, `exec`, `fetch`, `reset`, and `finalize`/`close`. Bindings always
copy strings/blobs and remain owned by the statement until rebound or closed.
Every parameter must be bound. Reset discards results but retains bindings.
Results are buffered at execution; fetch returns `seq[DbValue]`, preserving NULL,
and text/blob values as full byte strings (including embedded NUL). Numeric
results are represented as their exact server text; use normal Nim parsers.
Inputs support signed/unsigned 64-bit integers, double, text, bytes, and NULL.
Statement errors include native code and SQLSTATE. Finalize statements before
closing the connection; handles must not be shared concurrently between threads.
Close/finalize is explicit and idempotent; use `defer`/`try finally`.

```nim
let stmt = db.prepare("SELECT ?, ?")
defer: stmt.finalize()
stmt.bindParam(1, high(uint64))
stmt.bindParam(2, @[0'u8, 255, 0])
stmt.exec()
var values: seq[DbValue]
while stmt.fetch(values):
  echo values[0].data
```

Legacy execution methods retain their string argument conversions, but now
escape substituted values with the connection-aware client API. Both default
SQL mode and `NO_BACKSLASH_ESCAPES` are supported. Use `setEncoding` to change
the charset; raw `SET NAMES` statements can leave the client's charset knowledge
out of sync with the server and must not be used for this purpose.

The SQL tokenizer substitutes `?` only outside strings, quoted identifiers, and
comments. Doubled delimiters and SQL-mode-dependent backslash escapes are
recognized. No extra SQL queries are issued during formatting, preserving
session diagnostics such as `ROW_COUNT()` and `FOUND_ROWS()`. Templates whose
double-quote/backslash interpretation is ambiguous under `ANSI_QUOTES` are
rejected; use single quotes for strings and backticks for identifiers instead.
Substituted calls reject missing or extra arguments, malformed quoted text, and
parameters inside executable `/*! ... */` or `/*M! ... */` comments. Placeholders
belong outside quotes (use `LIKE ?` with a value such as `%term%`, not `LIKE '%?%'`).

Direct `LIMIT ?`, `OFFSET ?`, and `LIMIT ?, ?`/`LIMIT 10, ?` slots accept decimal
strings or integer arguments in the range `0..high(uint64)`. Empty values, signs,
whitespace, fractions, SQL expressions, and overflow are rejected. Only these
pagination slots are emitted as unquoted numbers; numeric-looking values
elsewhere remain strings, preserving leading zeros and existing coercions:

```nim
let page = db.getAllRows(sql"SELECT * FROM items LIMIT ? OFFSET ?", 100, pageNumber * 100)
```

UTF-8 and single-byte SQL templates may contain non-ASCII text. With other
multibyte client charsets (such as GBK or SJIS), substituted templates must be
ASCII: pass non-ASCII values as arguments instead. This avoids guessing whether
a quote or backslash byte belongs to a multibyte character. Argument escaping
still uses the full connection charset in all cases.

`dbQuote(db, value)` exposes connection-aware value quoting for callers composing
SQL explicitly. It does not quote identifiers. The original `dbQuote(value)`
overload remains unchanged for compatibility: it assumes backslash escaping and
a compatible charset and is unsafe with `NO_BACKSLASH_ESCAPES`.

Prefer native bindings for new code. Trusted raw SQL with no arguments,
including START TRANSACTION, COMMIT, ROLLBACK and generated SAVEPOINT commands,
remains unchanged and uses the text protocol, never `prepare`.

Text iterators buffer their first result and free it even on break/return/errors.
Additional result sets are drained and discarded; execution-only calls discard
all results. Prepared execution likewise discards additional result sets when
reset, re-executed or closed. Only the first result is exposed.
Finalizing a prepared statement drains pending results before closing it. If a
later result reports a server error, finalization raises that error but still
releases the statement; calling `finalize` again is safe.

## Testing

`nim c -r tests/all/tmysql_abi.nim` verifies actual C sizes/field addresses and
cross-language binding indicators. Do not use Nim compile-time `offsetOf` on
these partial imported structures: only the C compiler knows their layout.

Run `tests/all/tmysql_native.nim` with `MYSQL_TEST_DATABASE` set to a disposable
database. Optional environment variables are `MYSQL_TEST_HOST` (host:port),
`MYSQL_TEST_USER`, `MYSQL_TEST_PASSWORD`, and `MYSQL_TEST_SOCKET`. Credentials
need only database-scoped privileges, including CREATE ROUTINE. Without the
database variable the integration test explicitly skips. Tests create a temporary
table and a procedure, and exercise transaction text-protocol counters and
server statement counts. Run in isolation for meaningful global leak counts.

The CI matrix builds against **both client families**, each against both MySQL
8.4 and MariaDB 11.4 servers, with Nim 2.0.16/2.2.12 in debug/release, plus an
AddressSanitizer configuration. Platform jobs exercise macOS socket connections
and Windows MSVC ABI/loading. Windows server integration and the historical
Nim 1.7.3 development snapshot remain unverified; the package requirement is
unchanged. SQLite and PostgreSQL have separate regression coverage.
