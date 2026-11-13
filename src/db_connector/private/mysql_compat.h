#ifndef NIM_DB_MYSQL_COMPAT_H
#define NIM_DB_MYSQL_COMPAT_H
#include <mysql.h>
/* Oracle removed my_bool in 8.0; MariaDB retains it. */
#if defined(MARIADB_BASE_VERSION) || defined(MARIADB_VERSION_ID) || MYSQL_VERSION_ID < 80000
typedef my_bool NimMysqlBool;
#else
typedef bool NimMysqlBool;
#endif
#endif
