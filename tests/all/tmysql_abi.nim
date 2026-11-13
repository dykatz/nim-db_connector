import ../../src/db_connector/mysql
import std/[os, assertions]
const probe = currentSourcePath.parentDir / "mysql_abi_probe.h"
{.push importc, cdecl, header: probe.}
proc probe_bind_size(): csize_t
proc probe_field_size(): csize_t
proc probe_bind_alignment(): csize_t
proc probe_header_version(): cstring
proc probe_bind_length(): csize_t
proc probe_bind_buffer(): csize_t
proc probe_bind_null(): csize_t
proc probe_bind_error(): csize_t
proc probe_field_type(): csize_t
proc probe_binding(binding: PBIND): cint
{.pop.}
doAssert sizeof(my_ulonglong) == 8
doAssert high(my_ulonglong) == high(uint64)
doAssert sizeof(BIND) == int(probe_bind_size())
doAssert sizeof(FIELD) == int(probe_field_size())
doAssert alignof(BIND) == int(probe_bind_alignment())
# Use actual C field addresses: Nim's compile-time offsetOf only knows the
# deliberately partial Nim declaration, not the header's complete layout.
var layout: BIND
var field: FIELD
template offset(base, member: untyped): uint =
  cast[uint](addr member) - cast[uint](addr base)
doAssert offset(layout, layout.len) == uint(probe_bind_length())
doAssert offset(layout, layout.buffer) == uint(probe_bind_buffer())
doAssert offset(layout, layout.is_null) == uint(probe_bind_null())
doAssert offset(layout, layout.error) == uint(probe_bind_error())
doAssert offset(field, field.ftype) == uint(probe_field_type())
var length = 19.culong
var isNull: my_bool = true
var error: my_bool = false
var binding: BIND
binding.len = addr length
binding.is_null = addr isNull
binding.error = addr error
binding.buffer_length = length
binding.buffer_type = TYPE_LONGLONG
binding.is_unsigned = true
doAssert probe_binding(addr binding) == 1
echo "ABI probe passed; headers: ", probe_header_version(), "; client: ", get_client_info()
