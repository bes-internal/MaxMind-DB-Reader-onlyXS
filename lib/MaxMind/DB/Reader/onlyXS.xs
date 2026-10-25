/* *INDENT-ON* */
#ifdef __cplusplus
extern "C" {
#endif

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#define NEED_newRV_noinc
#define NEED_mg_findext
#define NEED_sv_magicext
#include "ppport.h"
#include <sys/socket.h>
#include "maxminddb.h"

/* A 128-bit integer type is needed (Build.PL checks it), it exists on 64-bit
 * platforms only, where IVs are 64-bit: perl_math_int64.h returns plain UVs
 * for uint64 values and Math::Int64 is not needed. */
#define MATH_INT64_NATIVE_IF_AVAILABLE
#if IVSIZE != 8
#error "MaxMind::DB::Reader::onlyXS needs a perl with 64-bit integers"
#endif
#include "perl_math_int64.h"
#include "perl_math_int128.h"

#ifdef __cplusplus
}
#endif

/* Math::Int128 is only needed for uint128 values; load it on first use so
 * that a plain lookup does not pay for it. */
static void ensure_int128(pTHX)
{
    static int loaded = 0;
    if (!loaded) {
        PERL_MATH_INT128_LOAD_OR_CROAK;
        loaded = 1;
    }
}

/* An open database: busy is set while the callbacks of _iterate_search_tree
 * run, they must not close it. */
typedef struct {
    MMDB_s mmdb;
    int busy;
} onlyxs_db;

/* A database handle is a reference to a scalar with ext magic that holds the
 * onlyxs_db pointer. The magic is what makes a scalar a handle: nothing else
 * (undef, a string, a number, another reference) is accepted, so a wrong
 * argument croaks instead of crashing perl. The database is closed by
 * _close_mmdb() or when the last reference to the handle goes away. */
static void mmdb_handle_close(MAGIC *mg)
{
    onlyxs_db *db = (onlyxs_db *)mg->mg_ptr;
    if (db) {
        mg->mg_ptr = NULL;
        MMDB_close(&db->mmdb);
        free(db);
    }
}

static int mmdb_handle_free(pTHX_ SV *sv, MAGIC *mg)
{
    mmdb_handle_close(mg);
    return 0;
}

/* A copy of the handle in a new ithread must not close the database of the
 * parent: the copy is a closed handle. */
static int mmdb_handle_dup(pTHX_ MAGIC *mg, CLONE_PARAMS *param)
{
    mg->mg_ptr = NULL;
    return 0;
}

static MGVTBL mmdb_handle_vtbl = {
    NULL, NULL, NULL, NULL, mmdb_handle_free, NULL, mmdb_handle_dup, NULL
};

static MAGIC *find_mmdb_handle(pTHX_ SV *sv, const char *func)
{
    if (SvROK(sv)) {
        SV *inner = SvRV(sv);
        if (SvTYPE(inner) >= SVt_PVMG) {
            MAGIC *mg = mg_findext(inner, PERL_MAGIC_ext, &mmdb_handle_vtbl);
            if (mg) {
                return mg;
            }
        }
    }
    croak("MaxMind::DB::Reader::onlyXS - Invalid database handle passed to %s()",
          func);
    return NULL;
}

/* The database of a handle. Do not run perl code (a callback, a tied
 * argument) between this and the last use of the result, it could close the
 * database: get the arguments first. */
static onlyxs_db *get_db(pTHX_ SV *sv, const char *func)
{
    MAGIC *mg = find_mmdb_handle(aTHX_ sv, func);
    if (!mg->mg_ptr) {
        croak("MaxMind::DB::Reader::onlyXS - The database handle passed to %s() is closed",
              func);
    }
    return (onlyxs_db *)mg->mg_ptr;
}

static SV *new_mmdb_handle(pTHX_ onlyxs_db *db)
{
    SV *inner = newSV(0);
    MAGIC *mg = sv_magicext(inner, NULL, PERL_MAGIC_ext, &mmdb_handle_vtbl,
                            (const char *)db, 0);
    mg->mg_flags |= MGf_DUP;
    return newRV_noinc(inner);
}

static void iterate_record_entry(MMDB_s *mmdb, SV *data_callback,
                                 SV *node_callback, uint32_t node_num,
                                 mmdb_uint128_t ipnum, int depth,
                                 int max_depth, uint64_t record,
                                 uint8_t record_type,
                                 MMDB_entry_s *record_entry);

static SV *decode_bytes(MMDB_entry_data_s *entry_data)
{
    return newSVpvn((char *)entry_data->bytes, entry_data->data_size);
}

static SV *decode_simple_value(MMDB_entry_data_list_s **current)
{
    MMDB_entry_data_s entry_data = (*current)->entry_data;
    switch (entry_data.type) {
    case MMDB_DATA_TYPE_UTF8_STRING:
        return newSVpvn_utf8((char *)entry_data.utf8_string, entry_data.data_size, 1);
    case MMDB_DATA_TYPE_DOUBLE:
        return newSVnv(entry_data.double_value);
    case MMDB_DATA_TYPE_BYTES:
        return decode_bytes(&entry_data);
    case MMDB_DATA_TYPE_FLOAT:
        return newSVnv(entry_data.float_value);
    case MMDB_DATA_TYPE_UINT16:
        return newSVuv(entry_data.uint16);
    case MMDB_DATA_TYPE_UINT32:
        return newSVuv(entry_data.uint32);
    case MMDB_DATA_TYPE_INT32:
        return newSViv(entry_data.int32);
    case MMDB_DATA_TYPE_UINT64:
        return newSVu64(entry_data.uint64);
    case MMDB_DATA_TYPE_UINT128:
        /* We don't handle the case where uint128 is a byte array since even
         * the pure Perl MaxMind::DB::Reader requires Math::Int128, which in
         * turn requires GCC 4.4+. Therefore we know that we have an int128
         * type available if this code is compiling at all. */
        ensure_int128(aTHX);
        return newSVu128(entry_data.uint128);
    case MMDB_DATA_TYPE_BOOLEAN:
        /* Note to future coders - do not use PL_sv_yes, PL_sv_no, or bool_sv
         * - these all produce read-only SVs */
        return newSViv(entry_data.boolean);
    default:
        croak(
            "MaxMind::DB::Reader::onlyXS - error decoding unknown type number %i",
            entry_data.type
            );
    }

    /* It shouldn't be possible to reach this. */
    return NULL;
}

static SV *decode_entry_data_list(MMDB_entry_data_list_s **entry_data_list);

static SV *decode_array(MMDB_entry_data_list_s **current)
{
    int size = (*current)->entry_data.data_size;

    AV *av = newAV();
    av_extend(av, size);
    for (uint i = 0; i < size; i++) {
        *current = (*current)->next;
        av_push(av, decode_entry_data_list(current));
    }

    return newRV_noinc((SV *)av);
}

static SV *decode_map(MMDB_entry_data_list_s **current)
{
    int size = (*current)->entry_data.data_size;

    HV *hv = newHV();
    hv_ksplit(hv, size);
    for (uint i = 0; i < size; i++) {
        *current = (*current)->next;
        char *key = (char *)(*current)->entry_data.utf8_string;
        int key_size = (*current)->entry_data.data_size;
        *current = (*current)->next;
        SV *val = decode_entry_data_list(current);
        (void)hv_store(hv, key, key_size, val, 0);
    }

    return newRV_noinc((SV *)hv);
}

static SV *decode_entry_data_list(MMDB_entry_data_list_s **current)
{
    switch ((*current)->entry_data.type) {
    case MMDB_DATA_TYPE_MAP:
        return decode_map(current);
    case MMDB_DATA_TYPE_ARRAY:
        return decode_array(current);
    default:
        return decode_simple_value(current);
    }
}

static SV *decode_and_free_entry_data_list(
    MMDB_entry_data_list_s *entry_data_list)
{
    MMDB_entry_data_list_s *current = entry_data_list;
    SV *sv = decode_entry_data_list(&current);
    MMDB_free_entry_data_list(entry_data_list);
    return sv;
}


static void call_node_callback(SV *node_callback, uint32_t node_num,
                               MMDB_search_node_s *node)
{
    if (!SvOK(node_callback)) {
        // nothing to do
        return;
    }

    dSP;

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 3);
    mPUSHu(node_num);
    mPUSHs(newSVu64(node->left_record));
    mPUSHs(newSVu64(node->right_record));
    PUTBACK;

    call_sv(node_callback, G_VOID);

    FREETMPS;
    LEAVE;

    return;
}

static void call_data_callback(MMDB_s *mmdb, SV *data_callback,
                               mmdb_uint128_t ipnum, int depth,
                               MMDB_entry_s *record_entry)
{

    if (!SvOK(data_callback)) {
        // nothing to do
        return;
    }

    MMDB_entry_data_list_s *entry_data_list = NULL;
    int status = MMDB_get_entry_data_list(record_entry, &entry_data_list);
    if (MMDB_SUCCESS != status) {
        const char *error = MMDB_strerror(status);
        MMDB_free_entry_data_list(entry_data_list);
        croak(
            "MaxMind::DB::Reader::onlyXS - Entry data error looking at offset %u: %s",
            record_entry->offset, error
            );
    }
    SV *decoded_entry = decode_and_free_entry_data_list(entry_data_list);

    dSP;

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 3);
    ensure_int128(aTHX);
    mPUSHs(newSVu128(ipnum));
    mPUSHi(depth);
    mPUSHs(decoded_entry);
    PUTBACK;

    call_sv(data_callback, G_VOID);

    FREETMPS;
    LEAVE;

    return;
}

static void iterate_search_nodes(MMDB_s *mmdb, SV *data_callback,
                                  SV *node_callback, uint32_t node_num,
                                  mmdb_uint128_t ipnum,
                                  int depth,
                                  int max_depth)
{

    MMDB_search_node_s node;
    int status = MMDB_read_node(mmdb, node_num, &node);
    if (MMDB_SUCCESS != status) {
        const char *error = MMDB_strerror(status);
        croak(
            "MaxMind::DB::Reader::onlyXS - Error reading node: %s",
            error
            );
    }

    call_node_callback(node_callback, node_num, &node);

    iterate_record_entry(mmdb, data_callback, node_callback, node_num, ipnum,
                         depth, max_depth, node.left_record,
                         node.left_record_type,
                         &node.left_record_entry);

    ipnum |= ((mmdb_uint128_t)1) << ( max_depth - depth );

    iterate_record_entry(mmdb, data_callback, node_callback, node_num, ipnum,
                         depth, max_depth, node.right_record,
                         node.right_record_type,
                         &node.right_record_entry);
}

static void iterate_record_entry(MMDB_s *mmdb, SV *data_callback,
                                 SV *node_callback, uint32_t node_num,
                                 mmdb_uint128_t ipnum, int depth,
                                 int max_depth, uint64_t record,
                                 uint8_t record_type,
                                 MMDB_entry_s *record_entry)
{

    switch (record_type) {
    case MMDB_RECORD_TYPE_INVALID:
        croak(
            "MaxMind::DB::Reader::onlyXS - Invalid record when reading node"
            );
    case MMDB_RECORD_TYPE_SEARCH_NODE:
        iterate_search_nodes(mmdb, data_callback, node_callback, record,
                              ipnum, depth + 1, max_depth);
        return;
    case  MMDB_RECORD_TYPE_EMPTY:
        // We ignore empty branches of the search tree
        return;
    case MMDB_RECORD_TYPE_DATA:
        call_data_callback(mmdb, data_callback, ipnum, depth,
                           record_entry);
        return;
    default:
        croak("MaxMind::DB::Reader::onlyXS - Unknown record type: %u",
              record_type);
    }
}

/* A string argument for a C function: a NUL byte in it would silently cut
 * the string (a path, an IP address), so it is an error. */
static const char *sv_cstr(pTHX_ SV *sv, const char *what)
{
    STRLEN len;
    const char *str = SvPVbyte(sv, len);
    if (strlen(str) != len) {
        croak("MaxMind::DB::Reader::onlyXS - The %s contains a NUL byte", what);
    }
    return str;
}

/* Look up an address and decode the record, or only the value at the path
 * (the strings of path_svs) in it, without decoding the rest of the record.
 * Returns undef if there is no record or no such value. *prefix is the length
 * of the network of the record (in the terms of the address family of ip)
 * and *found tells if there is a record. */
static SV *lookup_value(pTHX_ SV *handle, const char *func, SV *ip_sv,
                        SV **path_svs, int path_n, uint16_t *prefix,
                        int *found)
{
    const char *ip = sv_cstr(aTHX_ ip_sv, "IP address");
    int gai_status, mmdb_status, status;
    MMDB_lookup_result_s result;
    MMDB_entry_data_list_s *entry_data_list = NULL;

    *found = 0;

    /* the strings of the path first: a tied or overloaded argument runs perl
     * code, and path_svs points into the stack, which that code can move */
    const char **path = NULL;
    if (path_n > 0) {
        SV **svs;
        Newx(svs, path_n, SV *);
        SAVEFREEPV(svs);
        Copy(path_svs, svs, path_n, SV *);

        Newx(path, path_n + 1, const char *);
        SAVEFREEPV(path);
        for (int i = 0; i < path_n; i++) {
            path[i] = sv_cstr(aTHX_ svs[i], "path element");
        }
        path[path_n] = NULL;
    }

    MMDB_s *mmdb = &get_db(aTHX_ handle, func)->mmdb;

    if (*ip == '\0') {
        croak("You must provide an IP address to look up");
    }

    result = MMDB_lookup_string(mmdb, ip, &gai_status, &mmdb_status);
    if (0 != gai_status) {
        croak(
            "The IP address you provided (%s) is not a valid IPv4 or IPv6 address",
            ip);
    }
    if (MMDB_SUCCESS != mmdb_status) {
        croak(
            "MaxMind::DB::Reader::onlyXS - Error looking up IP address \"%s\": %s",
            ip, MMDB_strerror(mmdb_status));
    }
    if (!result.found_entry) {
        return &PL_sv_undef;
    }

    *found = 1;
    /* IPv4 addresses are in ::/96 of an IPv6 database */
    *prefix = result.netmask;
    if (mmdb->metadata.ip_version == 6 && !strchr(ip, ':')) {
        *prefix = result.netmask > 96 ? result.netmask - 96 : 0;
    }

    if (path_n == 0) {
        status = MMDB_get_entry_data_list(&result.entry, &entry_data_list);
        if (MMDB_SUCCESS != status) {
            MMDB_free_entry_data_list(entry_data_list);
            croak(
                "MaxMind::DB::Reader::onlyXS - Entry data error looking up \"%s\": %s",
                ip, MMDB_strerror(status));
        }
        return decode_and_free_entry_data_list(entry_data_list);
    }

    MMDB_entry_data_s entry_data;
    status = MMDB_aget_value(&result.entry, &entry_data, path);
    /* the structure of the records differs, a path that does not fit one of
     * them is just a value that is not there */
    if (MMDB_INVALID_LOOKUP_PATH_ERROR == status
        || MMDB_LOOKUP_PATH_DOES_NOT_MATCH_DATA_ERROR == status) {
        return &PL_sv_undef;
    }
    if (MMDB_SUCCESS != status) {
        croak(
            "MaxMind::DB::Reader::onlyXS - Error looking up the value for \"%s\": %s",
            ip, MMDB_strerror(status));
    }
    if (!entry_data.has_data) {
        return &PL_sv_undef;
    }

    if (entry_data.type == MMDB_DATA_TYPE_MAP
        || entry_data.type == MMDB_DATA_TYPE_ARRAY) {
        MMDB_entry_s entry = result.entry;
        entry.offset = entry_data.offset;
        status = MMDB_get_entry_data_list(&entry, &entry_data_list);
        if (MMDB_SUCCESS != status) {
            MMDB_free_entry_data_list(entry_data_list);
            croak(
                "MaxMind::DB::Reader::onlyXS - Entry data error looking up \"%s\": %s",
                ip, MMDB_strerror(status));
        }
        return decode_and_free_entry_data_list(entry_data_list);
    }

    MMDB_entry_data_list_s one;
    memset(&one, 0, sizeof(one));
    one.entry_data = entry_data;
    MMDB_entry_data_list_s *current = &one;
    return decode_simple_value(&current);
}

/* *INDENT-OFF* */

MODULE = MaxMind::DB::Reader::onlyXS    PACKAGE = MaxMind::DB::Reader::onlyXS

SV *
_open_mmdb(file_sv, flags)
    SV *file_sv;
    U32 flags;
    PREINIT:
        onlyxs_db *db;
        int status;
        const char *file;

    CODE:
        file = sv_cstr(aTHX_ file_sv, "file name");
        db = (onlyxs_db *)calloc(1, sizeof(onlyxs_db));
        if (db == NULL) {
            croak("MaxMind::DB::Reader::onlyXS - Out of memory");
        }
        status = MMDB_open(file, flags, &db->mmdb);

        if (MMDB_SUCCESS != status) {
            const char *error = MMDB_strerror(status);
            free(db);
            croak(
                "MaxMind::DB::Reader::onlyXS - Error opening database file \"%s\": %s",
                file, error
                );
        }

        RETVAL = new_mmdb_handle(aTHX_ db);
    OUTPUT:
        RETVAL

void
_close_mmdb(handle)
        SV *handle;
    PREINIT:
        MAGIC *mg;
    CODE:
        /* closing a closed handle is not an error */
        mg = find_mmdb_handle(aTHX_ handle, "_close_mmdb");
        if (mg->mg_ptr && ((onlyxs_db *)mg->mg_ptr)->busy) {
            croak("MaxMind::DB::Reader::onlyXS - The database is in use, it can not be closed by a callback of _iterate_search_tree()");
        }
        mmdb_handle_close(mg);

SV *
_raw_metadata(handle)
        SV *handle
    PREINIT:
        MMDB_entry_data_list_s *entry_data_list = NULL;
        int status;
    CODE:
        status = MMDB_get_metadata_as_entry_data_list(
            &get_db(aTHX_ handle, "_raw_metadata")->mmdb, &entry_data_list);
        if (MMDB_SUCCESS != status) {
            const char *error = MMDB_strerror(status);
            MMDB_free_entry_data_list(entry_data_list);
            croak(
                "MaxMind::DB::Reader::onlyXS - Error getting metadata: %s",
                error
                );
        }

        RETVAL = decode_and_free_entry_data_list(entry_data_list);
    OUTPUT:
        RETVAL

SV *
__data_for_address(handle, ip_sv)
        SV *handle
        SV *ip_sv
    PREINIT:
        uint16_t prefix;
        int found;
    CODE:
        RETVAL = lookup_value(aTHX_ handle, "__data_for_address", ip_sv, NULL,
                              0, &prefix, &found);
    OUTPUT:
        RETVAL

SV *
__value_for_address(handle, ip_sv, ...)
        SV *handle
        SV *ip_sv
    PREINIT:
        uint16_t prefix;
        int found;
    CODE:
        RETVAL = lookup_value(aTHX_ handle, "__value_for_address", ip_sv,
                              &ST(2), items - 2, &prefix, &found);
    OUTPUT:
        RETVAL

void
__lookup_for_address(handle, ip_sv, ...)
        SV *handle
        SV *ip_sv
    PREINIT:
        uint16_t prefix = 0;
        int found = 0;
        SV *value;
    PPCODE:
        value = lookup_value(aTHX_ handle, "__lookup_for_address", ip_sv,
                             &ST(2), items - 2, &prefix, &found);
        EXTEND(SP, 2);
        PUSHs(sv_2mortal(value));
        if (found) {
            mPUSHu(prefix);
        } else {
            PUSHs(&PL_sv_undef);
        }

void
_iterate_search_tree(handle, data_callback, node_callback)
        SV *handle
        SV *data_callback;
        SV *node_callback;
    PREINIT:
        onlyxs_db *db;
        int max_depth;
        mmdb_uint128_t ipnum = 0;
    CODE:
        db = get_db(aTHX_ handle, "_iterate_search_tree");
        max_depth = db->mmdb.metadata.ip_version == 6 ? 128 : 32;

        /* A callback may undef the variable with the handle or try to close
         * the database: keep the handle alive and the database open until the
         * walk is over (also when a callback dies). The order matters, the
         * flag is restored before the handle is released. */
        ENTER;
        SAVEFREESV(SvREFCNT_inc_simple_NN(SvRV(handle)));
        SAVEINT(db->busy);
        db->busy++;

        iterate_search_nodes(&db->mmdb, data_callback, node_callback, 0,
            ipnum, 1, max_depth);

        LEAVE;

void
__read_node(handle, node_number)
        SV *handle
        U32 node_number
    PREINIT:
        MMDB_search_node_s node;
        int status;
    PPCODE:
        status = MMDB_read_node(&get_db(aTHX_ handle, "__read_node")->mmdb,
                                node_number, &node);
        if (MMDB_SUCCESS != status) {
            const char *error = MMDB_strerror(status);
            croak(
                "MaxMind::DB::Reader::onlyXS - Error trying to read node %u: %s",
                node_number, error
                );
        }
        EXTEND(SP, 2);
        mPUSHu(node.left_record);
        mPUSHu(node.right_record);

SV *
libmaxminddb_version()
    CODE:
        const char *v = MMDB_lib_version();
        RETVAL = newSVpv(v, strlen(v));
    OUTPUT:
        RETVAL
