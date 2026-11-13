#ifndef NIM_DB_MYSQL_COMPAT_H
#define NIM_DB_MYSQL_COMPAT_H
#include <mysql.h>
/* Oracle removed my_bool in 8.0; MariaDB retains it. */
#if defined(MARIADB_BASE_VERSION) || defined(MARIADB_VERSION_ID) || MYSQL_VERSION_ID < 80000
typedef my_bool NimMysqlBool;
#else
typedef bool NimMysqlBool;
#endif

/* Both implementations account for the connection charset and SQL mode.
 * Oracle's older real_escape_string rejects NO_BACKSLASH_ESCAPES; use its
 * quote-aware API. MariaDB handles that mode in real_escape_string itself. */
static unsigned long nim_mysql_escape_literal(MYSQL *db, char *dest,
    const char *source, unsigned long length) {
#if defined(MARIADB_BASE_VERSION) || defined(MARIADB_VERSION_ID)
  return mysql_real_escape_string(db, dest, source, length);
#else
  return mysql_real_escape_string_quote(db, dest, source, length, '\'');
#endif
}
static int nim_mysql_no_backslash_escapes(MYSQL *db) {
  return (db->server_status & SERVER_STATUS_NO_BACKSLASH_ESCAPES) != 0;
}
#endif
