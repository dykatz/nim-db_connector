## Header-backed public MySQL/MariaDB client API. See docs/mysql.md.
import std/os

const
  mysqlConfig* {.strdefine.} = "mysql_config"
  mysqlCFlags* {.strdefine.} = ""
  mysqlLibs* {.strdefine.} = ""
  mysqlHeader = currentSourcePath.parentDir / "private" / "mysql_compat.h"

when mysqlCFlags.len > 0:
  {.passC: mysqlCFlags.}
elif not defined(windows):
  {.passC: staticExec(mysqlConfig & " --cflags").}
when mysqlLibs.len > 0:
  {.passL: mysqlLibs.}
elif defined(windows):
  {.passL: "libmysql.lib".}
else:
  {.passL: staticExec(mysqlConfig & " --libs").}

type
  my_bool* {.importc: "NimMysqlBool", header: mysqlHeader.} = bool
  Pmy_bool* = ptr my_bool
  my_ulonglong* = culonglong
  MySQL* {.importc: "MYSQL", header: mysqlHeader, incompleteStruct.} = object
  RES* {.importc: "MYSQL_RES", header: mysqlHeader, incompleteStruct.} = object
  STMT* {.importc: "MYSQL_STMT", header: mysqlHeader, incompleteStruct.} = object
  PMySQL* = ptr MySQL
  PRES* = ptr RES
  PSTMT* = ptr STMT
  ROW* = cstringArray
  ROW_OFFSET* = pointer
  FIELD_OFFSET* = cuint
  Option* {.importc: "enum mysql_option", header: mysqlHeader, size: sizeof(cint).} = enum
    OPT_CONNECT_TIMEOUT, OPT_COMPRESS, OPT_NAMED_PIPE, INIT_COMMAND,
    READ_DEFAULT_FILE, READ_DEFAULT_GROUP, SET_CHARSET_DIR, SET_CHARSET_NAME,
    OPT_LOCAL_INFILE, OPT_PROTOCOL, SHARED_MEMORY_BASE_NAME, OPT_READ_TIMEOUT,
    OPT_WRITE_TIMEOUT
  Protocol_type* {.size: sizeof(cint).} = enum
    PROTOCOL_DEFAULT, PROTOCOL_TCP, PROTOCOL_SOCKET, PROTOCOL_PIPE, PROTOCOL_MEMORY
  Enum_field_types* {.importc: "enum enum_field_types", header: mysqlHeader,
                     size: sizeof(cint).} = enum
    TYPE_DECIMAL, TYPE_TINY, TYPE_SHORT, TYPE_LONG, TYPE_FLOAT, TYPE_DOUBLE,
    TYPE_NULL, TYPE_TIMESTAMP, TYPE_LONGLONG, TYPE_INT24, TYPE_DATE, TYPE_TIME,
    TYPE_DATETIME, TYPE_YEAR, TYPE_NEWDATE, TYPE_VARCHAR, TYPE_BIT,
    TYPE_JSON = 245, TYPE_NEWDECIMAL = 246, TYPE_ENUM, TYPE_SET,
    TYPE_TINY_BLOB, TYPE_MEDIUM_BLOB, TYPE_LONG_BLOB, TYPE_BLOB,
    TYPE_VAR_STRING, TYPE_STRING, TYPE_GEOMETRY
  FIELD* {.importc: "MYSQL_FIELD", header: mysqlHeader, bycopy.} = object
    name*, org_name*, table*, org_table*, db*, catalog*, def*: cstring
    len* {.importc: "length".}: culong
    max_length*: culong
    name_length*, org_name_length*, table_length*, org_table_length*: cuint
    db_length*, catalog_length*, def_length*: cuint
    flags*, decimals*, charsetnr*: cuint
    ftype* {.importc: "type".}: Enum_field_types
  PFIELD* = ptr FIELD
  BIND* {.importc: "MYSQL_BIND", header: mysqlHeader, bycopy.} = object
    len* {.importc: "length".}: ptr culong
    is_null*, error*: Pmy_bool
    buffer*: pointer
    buffer_length*: culong
    buffer_type*: Enum_field_types
    is_unsigned*: my_bool
  PBIND* = ptr BIND

const
  NOT_NULL_FLAG* = 1'u32
  PRI_KEY_FLAG* = 2'u32
  UNIQUE_KEY_FLAG* = 4'u32
  MULTIPLE_KEY_FLAG* = 8'u32
  BLOB_FLAG* = 16'u32
  UNSIGNED_FLAG* = 32'u32
  BINARY_FLAG* = 128'u32
  AUTO_INCREMENT_FLAG* = 512'u32
  CLIENT_FOUND_ROWS* = 2'u32
  CLIENT_MULTI_STATEMENTS* = 65536'u32
  CLIENT_MULTI_RESULTS* = 131072'u32
  NO_DATA* = 100
  DATA_TRUNCATED* = 101
  COUNT_ERROR* = high(my_ulonglong)

# Header declarations determine the actual calling convention, including Windows.
{.push cdecl, header: mysqlHeader.}
proc init*(db: PMySQL): PMySQL {.importc: "mysql_init".}
proc close*(db: PMySQL) {.importc: "mysql_close".}
proc real_connect*(db: PMySQL; host, user, password, database: cstring;
                   port: cuint; socket: cstring; flags: culong): PMySQL {.importc: "mysql_real_connect".}
proc real_query*(db: PMySQL; query: cstring; length: culong): cint {.importc: "mysql_real_query".}
proc query*(db: PMySQL; query: cstring): cint {.importc: "mysql_query".}
proc send_query*(db: PMySQL; query: cstring; length: culong): cint {.importc: "mysql_send_query".}
proc read_query_result*(db: PMySQL): my_bool {.importc: "mysql_read_query_result".}
proc store_result*(db: PMySQL): PRES {.importc: "mysql_store_result".}
proc use_result*(db: PMySQL): PRES {.importc: "mysql_use_result".}
proc free_result*(res: PRES) {.importc: "mysql_free_result".}
proc fetch_row*(res: PRES): ROW {.importc: "mysql_fetch_row".}
proc fetch_lengths*(res: PRES): ptr UncheckedArray[culong] {.importc: "mysql_fetch_lengths".}
proc num_fields*(res: PRES): cuint {.importc: "mysql_num_fields".}
proc num_rows*(res: PRES): my_ulonglong {.importc: "mysql_num_rows".}
proc fetch_field_direct*(res: PRES; index: cuint): PFIELD {.importc: "mysql_fetch_field_direct".}
proc fetch_field*(res: PRES): PFIELD {.importc: "mysql_fetch_field".}
proc fetch_fields*(res: PRES): PFIELD {.importc: "mysql_fetch_fields".}
proc row_seek*(res: PRES; offset: ROW_OFFSET): ROW_OFFSET {.importc: "mysql_row_seek".}
proc row_tell*(res: PRES): ROW_OFFSET {.importc: "mysql_row_tell".}
proc field_seek*(res: PRES; offset: FIELD_OFFSET): FIELD_OFFSET {.importc: "mysql_field_seek".}
proc field_tell*(res: PRES): FIELD_OFFSET {.importc: "mysql_field_tell".}
proc field_count*(db: PMySQL): cuint {.importc: "mysql_field_count".}
proc affected_rows*(db: PMySQL): my_ulonglong {.importc: "mysql_affected_rows".}
proc insert_id*(db: PMySQL): my_ulonglong {.importc: "mysql_insert_id".}
proc errno*(db: PMySQL): cuint {.importc: "mysql_errno".}
proc error*(db: PMySQL): cstring {.importc: "mysql_error".}
proc sqlstate*(db: PMySQL): cstring {.importc: "mysql_sqlstate".}
proc warning_count*(db: PMySQL): cuint {.importc: "mysql_warning_count".}
proc info*(db: PMySQL): cstring {.importc: "mysql_info".}
proc thread_id*(db: PMySQL): culong {.importc: "mysql_thread_id".}
proc next_result*(db: PMySQL): cint {.importc: "mysql_next_result".}
proc more_results*(db: PMySQL): my_bool {.importc: "mysql_more_results".}
proc set_character_set*(db: PMySQL; encoding: cstring): cint {.importc: "mysql_set_character_set".}
proc character_set_name*(db: PMySQL): cstring {.importc: "mysql_character_set_name".}
proc get_client_info*(): cstring {.importc: "mysql_get_client_info".}
proc get_client_version*(): culong {.importc: "mysql_get_client_version".}
proc get_server_info*(db: PMySQL): cstring {.importc: "mysql_get_server_info".}
proc get_server_version*(db: PMySQL): culong {.importc: "mysql_get_server_version".}
proc get_host_info*(db: PMySQL): cstring {.importc: "mysql_get_host_info".}
proc get_proto_info*(db: PMySQL): cuint {.importc: "mysql_get_proto_info".}
proc thread_init*(): my_bool {.importc: "mysql_thread_init".}
proc thread_end*() {.importc: "mysql_thread_end".}
proc thread_safe*(): cuint {.importc: "mysql_thread_safe".}
proc ping*(db: PMySQL): cint {.importc: "mysql_ping".}
proc select_db*(db: PMySQL; name: cstring): cint {.importc: "mysql_select_db".}
proc change_user*(db: PMySQL; user, password, database: cstring): my_bool {.importc: "mysql_change_user".}
proc options*(db: PMySQL; option: Option; arg: pointer): cint {.importc: "mysql_options".}
proc stat*(db: PMySQL): cstring {.importc: "mysql_stat".}
proc list_dbs*(db: PMySQL; wildcard: cstring): PRES {.importc: "mysql_list_dbs".}
proc list_tables*(db: PMySQL; wildcard: cstring): PRES {.importc: "mysql_list_tables".}
proc list_fields*(db: PMySQL; table, wildcard: cstring): PRES {.importc: "mysql_list_fields".}
proc commit*(db: PMySQL): my_bool {.importc: "mysql_commit".}
proc rollback*(db: PMySQL): my_bool {.importc: "mysql_rollback".}
proc autocommit*(db: PMySQL; enabled: my_bool): my_bool {.importc: "mysql_autocommit".}
proc real_escape_string*(db: PMySQL; dest, source: cstring; length: culong): culong {.importc: "mysql_real_escape_string".}
proc escape_string*(dest, source: cstring; length: culong): culong {.importc: "mysql_escape_string".}
proc hex_string*(dest, source: cstring; length: culong): culong {.importc: "mysql_hex_string".}
proc data_seek*(res: PRES; offset: my_ulonglong) {.importc: "mysql_data_seek".}
proc stmt_init*(db: PMySQL): PSTMT {.importc: "mysql_stmt_init".}
proc stmt_prepare*(stmt: PSTMT; query: cstring; length: culong): cint {.importc: "mysql_stmt_prepare".}
proc stmt_execute*(stmt: PSTMT): cint {.importc: "mysql_stmt_execute".}
proc stmt_fetch*(stmt: PSTMT): cint {.importc: "mysql_stmt_fetch".}
proc stmt_fetch_column*(stmt: PSTMT; binding: PBIND; column: cuint; offset: culong): cint {.importc: "mysql_stmt_fetch_column".}
proc stmt_store_result*(stmt: PSTMT): cint {.importc: "mysql_stmt_store_result".}
proc stmt_param_count*(stmt: PSTMT): culong {.importc: "mysql_stmt_param_count".}
proc stmt_bind_param*(stmt: PSTMT; binding: PBIND): my_bool {.importc: "mysql_stmt_bind_param".}
proc stmt_bind_result*(stmt: PSTMT; binding: PBIND): my_bool {.importc: "mysql_stmt_bind_result".}
proc stmt_close*(stmt: PSTMT): my_bool {.importc: "mysql_stmt_close".}
proc stmt_reset*(stmt: PSTMT): my_bool {.importc: "mysql_stmt_reset".}
proc stmt_send_long_data*(stmt: PSTMT; param_number: cuint; data: cstring; length: culong): my_bool {.importc: "mysql_stmt_send_long_data".}
proc stmt_free_result*(stmt: PSTMT): my_bool {.importc: "mysql_stmt_free_result".}
proc stmt_result_metadata*(stmt: PSTMT): PRES {.importc: "mysql_stmt_result_metadata".}
proc stmt_errno*(stmt: PSTMT): cuint {.importc: "mysql_stmt_errno".}
proc stmt_error*(stmt: PSTMT): cstring {.importc: "mysql_stmt_error".}
proc stmt_sqlstate*(stmt: PSTMT): cstring {.importc: "mysql_stmt_sqlstate".}
proc stmt_num_rows*(stmt: PSTMT): my_ulonglong {.importc: "mysql_stmt_num_rows".}
proc stmt_data_seek*(stmt: PSTMT; offset: my_ulonglong) {.importc: "mysql_stmt_data_seek".}
proc stmt_row_seek*(stmt: PSTMT; offset: ROW_OFFSET): ROW_OFFSET {.importc: "mysql_stmt_row_seek".}
proc stmt_row_tell*(stmt: PSTMT): ROW_OFFSET {.importc: "mysql_stmt_row_tell".}
proc stmt_affected_rows*(stmt: PSTMT): my_ulonglong {.importc: "mysql_stmt_affected_rows".}
proc stmt_insert_id*(stmt: PSTMT): my_ulonglong {.importc: "mysql_stmt_insert_id".}
proc stmt_field_count*(stmt: PSTMT): cuint {.importc: "mysql_stmt_field_count".}
proc stmt_next_result*(stmt: PSTMT): cint {.importc: "mysql_stmt_next_result".}
{.pop.}
