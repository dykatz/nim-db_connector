#include "../../src/db_connector/private/mysql_compat.h"
#include <stddef.h>
#include <stdint.h>
static size_t probe_bind_size(void) { return sizeof(MYSQL_BIND); }
static size_t probe_field_size(void) { return sizeof(MYSQL_FIELD); }
static size_t probe_bind_alignment(void) {
  struct align_probe { char byte; MYSQL_BIND binding; };
  return offsetof(struct align_probe, binding);
}
static const char *probe_header_version(void) { return MYSQL_SERVER_VERSION; }
static size_t probe_bind_length(void) { return offsetof(MYSQL_BIND, length); }
static size_t probe_bind_buffer(void) { return offsetof(MYSQL_BIND, buffer); }
static size_t probe_bind_null(void) { return offsetof(MYSQL_BIND, is_null); }
static size_t probe_bind_error(void) { return offsetof(MYSQL_BIND, error); }
static size_t probe_field_type(void) { return offsetof(MYSQL_FIELD, type); }
static int probe_binding(MYSQL_BIND *b) {
  return b->length && *b->length == 19 && b->is_null && *b->is_null &&
    b->error && !*b->error && b->buffer_length == 19 && b->is_unsigned &&
    b->buffer_type == MYSQL_TYPE_LONGLONG;
}
typedef char probe_unsigned_longlong[(sizeof(my_ulonglong) == 8 && (my_ulonglong)-1 > 0) ? 1 : -1];
typedef char probe_bool_size[(sizeof(*((MYSQL_BIND *)0)->is_null) == sizeof(NimMysqlBool)) ? 1 : -1];
