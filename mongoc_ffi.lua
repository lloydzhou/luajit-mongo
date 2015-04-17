local ffi = require "ffi"
local mongoc = ffi.load("libmongoc-1.0.so")
local cjson = require "cjson" 

ffi.cdef [[
    typedef long ssize_t;
    typedef struct {
       uint8_t bytes[12];
    } bson_oid_t;

    typedef struct _bson_t {
       uint32_t flags;        /* Internal flags for the bson_t. */
       uint32_t len;          /* Length of BSON data. */
       uint8_t padding[120];  /* Padding for stack allocation. */
    } bson_t;
    typedef enum {
       BSON_TYPE_EOD = 0x00,
       BSON_TYPE_DOUBLE = 0x01,
       BSON_TYPE_UTF8 = 0x02,
       BSON_TYPE_DOCUMENT = 0x03,
       BSON_TYPE_ARRAY = 0x04,
       BSON_TYPE_BINARY = 0x05,
       BSON_TYPE_UNDEFINED = 0x06,
       BSON_TYPE_OID = 0x07,
       BSON_TYPE_BOOL = 0x08,
       BSON_TYPE_DATE_TIME = 0x09,
       BSON_TYPE_NULL = 0x0A,
       BSON_TYPE_REGEX = 0x0B,
       BSON_TYPE_DBPOINTER = 0x0C,
       BSON_TYPE_CODE = 0x0D,
       BSON_TYPE_SYMBOL = 0x0E,
       BSON_TYPE_CODEWSCOPE = 0x0F,
       BSON_TYPE_INT32 = 0x10,
       BSON_TYPE_TIMESTAMP = 0x11,
       BSON_TYPE_INT64 = 0x12,
       BSON_TYPE_MAXKEY = 0x7F,
       BSON_TYPE_MINKEY = 0xFF,
    } bson_type_t;

    typedef enum {
       BSON_SUBTYPE_BINARY = 0x00,
       BSON_SUBTYPE_FUNCTION = 0x01,
       BSON_SUBTYPE_BINARY_DEPRECATED = 0x02,
       BSON_SUBTYPE_UUID_DEPRECATED = 0x03,
       BSON_SUBTYPE_UUID = 0x04,
       BSON_SUBTYPE_MD5 = 0x05,
       BSON_SUBTYPE_USER = 0x80,
    } bson_subtype_t;

    typedef struct _bson_value_t {
        bson_type_t           value_type;
        int32_t               padding;
        union {
            bson_oid_t         v_oid;
            int64_t            v_int64;
            int32_t            v_int32;
            int8_t             v_int8;
            double             v_double;
            bool               v_bool;
            int64_t            v_datetime;
            struct {
                uint32_t        timestamp;
                uint32_t        increment;
            } v_timestamp;
            struct {
                char           *str;
                uint32_t        len;
            } v_utf8;
            struct {
                uint8_t        *data;
                uint32_t        data_len;
            } v_doc;
            struct {
                uint8_t        *data;
                uint32_t        data_len;
                bson_subtype_t  subtype;
            } v_binary;
            struct {
                char           *regex;
                char           *options;
            } v_regex;
            struct {
                char           *collection;
                uint32_t        collection_len;
                bson_oid_t      oid;
            } v_dbpointer;
            struct {
                char           *code;
                uint32_t        code_len;
            } v_code;
            struct {
                char           *code;
                uint8_t        *scope_data;
                uint32_t        code_len;
                uint32_t        scope_len;
            } v_codewscope;
            struct {
                char           *symbol;
                uint32_t        len;
            } v_symbol;
        } value;
    } bson_value_t;

    typedef struct {
        const uint8_t *raw;      /* The raw buffer being iterated. */
        uint32_t       len;      /* The length of raw. */
        uint32_t       off;      /* The offset within the buffer. */
        uint32_t       type;     /* The offset of the type byte. */
        uint32_t       key;      /* The offset of the key byte. */
        uint32_t       d1;       /* The offset of the first data byte. */
        uint32_t       d2;       /* The offset of the second data byte. */
        uint32_t       d3;       /* The offset of the third data byte. */
        uint32_t       d4;       /* The offset of the fourth data byte. */
        uint32_t       next_off; /* The offset of the next field. */
        uint32_t       err_off;  /* The offset of the error. */
        bson_value_t   value;    /* Internal value for various state. */
    } bson_iter_t;

    typedef struct _bson_context_t bson_context_t;

    typedef struct _bson_error_t {
       uint32_t domain;
       uint32_t code;
       char     message[504];
    } bson_error_t;

    void bson_oid_init (bson_oid_t *oid, bson_context_t *context);
    void bson_oid_init_from_string (bson_oid_t *oid, const char *str);
    void bson_oid_to_string (const bson_oid_t *oid, char str[25]);
    
    bson_t * bson_new (void);
    bson_t * bson_new_from_json (const uint8_t *data, size_t len, bson_error_t  *error);
    bool bson_init_from_json (bson_t *bson, const char *data, size_t len, bson_error_t *error);
    const uint8_t * bson_get_data (const bson_t *bson);
    void bson_destroy (bson_t *bson);
    char * bson_as_json (const bson_t *bson, size_t *length);
    bool bson_concat (bson_t *dst, const bson_t *src);
    
    bool bson_append_array_begin (bson_t *bson, const char *key, int key_length, bson_t *child);
    bool bson_append_array (bson_t *bson, const char   *key, int key_length, const bson_t *array);
    bool bson_append_array_end (bson_t *bson, bson_t *child);
    bool bson_append_document (bson_t *bson, const char *key, int key_length, const bson_t *value);
    bool bson_append_bool (bson_t *bson, const char *key, int key_length, bool value);
    bool bson_append_int64 (bson_t *bson, const char *key, int key_length, int64_t value);
    bool bson_append_utf8 (bson_t *bson, const char *key, int key_length, const char *value, int length);
    bool bson_iter_init_find_case (bson_iter_t *iter, const bson_t *bson, const char *key);
    bool bson_append_oid (bson_t *bson, const char *key, int key_length, const bson_oid_t *oid);
    const bson_oid_t * bson_iter_oid (const bson_iter_t *iter);

    typedef struct {
       bool (*visit_before) (const bson_iter_t *iter, const char *key, void *data);
       bool (*visit_after) (const bson_iter_t *iter, const char *key, void *data);
       void (*visit_corrupt)    (const bson_iter_t *iter, void *data);
       bool (*visit_double)     (const bson_iter_t *iter, const char *key, double v_double, void *data);
       bool (*visit_utf8)       (const bson_iter_t *iter, const char *key, size_t v_utf8_len, const char *v_utf8, void *data);
       bool (*visit_document)   (const bson_iter_t *iter, const char *key, const bson_t *v_document, void *data);
       bool (*visit_array)      (const bson_iter_t *iter, const char *key, const bson_t *v_array, void *data);
       bool (*visit_binary)     (const bson_iter_t *iter, const char *key, bson_subtype_t v_subtype, size_t v_binary_len, const uint8_t *v_binary, void *data);
       bool (*visit_undefined)  (const bson_iter_t *iter, const char *key, void *data);
       bool (*visit_oid)        (const bson_iter_t *iter, const char *key, const bson_oid_t *v_oid, void *data);
       bool (*visit_bool)       (const bson_iter_t *iter, const char *key, bool v_bool, void *data);
       bool (*visit_date_time)  (const bson_iter_t *iter, const char *key, int64_t msec_since_epoch, void *data);
       bool (*visit_null)       (const bson_iter_t *iter, const char *key, void *data);
       bool (*visit_regex)      (const bson_iter_t *iter, const char *key, const char *v_regex, const char *v_options, void *data);
       bool (*visit_dbpointer)  (const bson_iter_t *iter, const char *key, size_t v_collection_len, const char *v_collection, const bson_oid_t *v_oid, void *data);
       bool (*visit_code)       (const bson_iter_t *iter, const char *key, size_t v_code_len, const char *v_code, void *data);
       bool (*visit_symbol)     (const bson_iter_t *iter, const char *key, size_t v_symbol_len, const char *v_symbol, void *data);
       bool (*visit_codewscope) (const bson_iter_t *iter, const char *key, size_t v_code_len, const char *v_code, const bson_t *v_scope, void *data);
       bool (*visit_int32)      (const bson_iter_t *iter, const char *key, int32_t v_int32, void *data);
       bool (*visit_timestamp)  (const bson_iter_t *iter, const char *key, uint32_t v_timestamp, uint32_t v_increment, void *data);
       bool (*visit_int64)      (const bson_iter_t *iter, const char *key, int64_t v_int64, void *data);
       bool (*visit_maxkey)     (const bson_iter_t *iter, const char *key, void *data);
       bool (*visit_minkey)     (const bson_iter_t *iter, const char *key,void *data);
       void *padding[9];
    } bson_visitor_t;

    char *bson_utf8_escape_for_json (const char *utf8, ssize_t utf8_len);
    ssize_t b64_ntop (uint8_t const *src, size_t srclength, char *target, size_t targsize);
    bool bson_iter_init (bson_iter_t  *iter, const bson_t *bson);
    bool bson_iter_visit_all (bson_iter_t *iter, const bson_visitor_t *visitor, void *data);

    /* for mongoc */
    typedef struct _mongoc_uri_t mongoc_uri_t;
    typedef struct _mongoc_client_pool_t mongoc_client_pool_t;
    typedef struct _mongoc_client_t mongoc_client_t;
    typedef struct _mongoc_database_t mongoc_database_t;
    typedef struct _mongoc_collection_t mongoc_collection_t;
    typedef struct _mongoc_gridfs_t mongoc_gridfs_t;
    typedef struct _mongoc_cursor_t mongoc_cursor_t;
    typedef struct _mongoc_read_prefs_t mongoc_read_prefs_t;
    typedef struct _mongoc_write_concern_t mongoc_write_concern_t;
    typedef struct _mongoc_gridfs_file_t     mongoc_gridfs_file_t;
    typedef struct _mongoc_gridfs_file_opt_t mongoc_gridfs_file_opt_t;
    typedef struct _mongoc_gridfs_t mongoc_gridfs_t;
    typedef struct _mongoc_stream_t mongoc_stream_t;
    typedef struct _mongoc_stream_t mongoc_stream_t;
    struct _mongoc_gridfs_file_opt_t {
       const char   *md5;
       const char   *filename;
       const char   *content_type;
       const bson_t *aliases;
       const bson_t *metadata;
       uint32_t      chunk_size;
    };
    typedef struct {
       size_t  iov_len;
       char   *iov_base;
    } mongoc_iovec_t;

    typedef enum {
       MONGOC_QUERY_NONE              = 0,
       MONGOC_QUERY_TAILABLE_CURSOR   = 1 << 1,
       MONGOC_QUERY_SLAVE_OK          = 1 << 2,
       MONGOC_QUERY_OPLOG_REPLAY      = 1 << 3,
       MONGOC_QUERY_NO_CURSOR_TIMEOUT = 1 << 4,
       MONGOC_QUERY_AWAIT_DATA        = 1 << 5,
       MONGOC_QUERY_EXHAUST           = 1 << 6,
       MONGOC_QUERY_PARTIAL           = 1 << 7,
    } mongoc_query_flags_t;

    typedef enum {
       MONGOC_DELETE_NONE          = 0,
       MONGOC_DELETE_SINGLE_REMOVE = 1 << 0,
    } mongoc_delete_flags_t;

    typedef enum {
       MONGOC_UPDATE_NONE         = 0,
       MONGOC_UPDATE_UPSERT       = 1 << 0,
       MONGOC_UPDATE_MULTI_UPDATE = 1 << 1,
    } mongoc_update_flags_t;

    typedef enum {
      MONGOC_INSERT_NONE              = 0,
      MONGOC_INSERT_CONTINUE_ON_ERROR = 1 << 0,
    } mongoc_insert_flags_t;

    void mongoc_uri_destroy (mongoc_uri_t *uri);
    mongoc_uri_t *mongoc_uri_new (const char *uri_string);
    mongoc_client_pool_t *mongoc_client_pool_new (const mongoc_uri_t *uri);
    void mongoc_client_pool_destroy (mongoc_client_pool_t *pool);
    mongoc_client_t *mongoc_client_pool_pop (mongoc_client_pool_t *pool);
    void mongoc_client_pool_push (mongoc_client_pool_t *pool, mongoc_client_t *client);

    mongoc_client_t *mongoc_client_new (const char *uri_string);
    void mongoc_client_destroy (mongoc_client_t *client);
    mongoc_database_t *mongoc_client_get_database (mongoc_client_t *client, const char *name);
    mongoc_gridfs_t *mongoc_client_get_gridfs (mongoc_client_t *client, const char *db, const char *prefix, bson_error_t *error);
    mongoc_collection_t *mongoc_client_get_collection (mongoc_client_t *client, const char *db, const char *collection);
    
    void mongoc_database_destroy (mongoc_database_t *database);
    const char *mongoc_database_get_name (mongoc_database_t *database);
    mongoc_collection_t *mongoc_database_get_collection (mongoc_database_t *database, const char *name);
    mongoc_cursor_t *mongoc_database_command (mongoc_database_t *database, mongoc_query_flags_t flags, uint32_t skip, 
        uint32_t limit, uint32_t batch_size, const bson_t *command, const bson_t *fields, const mongoc_read_prefs_t *read_prefs);
    
    void mongoc_collection_destroy (mongoc_collection_t *collection);
    const char *mongoc_collection_get_name (mongoc_collection_t *collection);
    mongoc_cursor_t *mongoc_collection_command (mongoc_collection_t *collection, mongoc_query_flags_t flags, uint32_t skip, 
        uint32_t limit, uint32_t batch_size, const bson_t *command, const bson_t *fields, const mongoc_read_prefs_t *read_prefs);
    mongoc_cursor_t *mongoc_collection_find (mongoc_collection_t *collection, mongoc_query_flags_t flags, uint32_t skip, 
        uint32_t limit, uint32_t batch_size, const bson_t *query, const bson_t *fields, const mongoc_read_prefs_t *read_prefs);
    int64_t mongoc_collection_count (mongoc_collection_t *collection, mongoc_query_flags_t flags, const bson_t *query, 
        int64_t skip, int64_t limit, const mongoc_read_prefs_t *read_prefs, bson_error_t *error);
    bool mongoc_collection_insert (mongoc_collection_t *collection, mongoc_insert_flags_t flags, 
        const bson_t *document, const mongoc_write_concern_t *write_concern, bson_error_t *error);
    bool mongoc_collection_update (mongoc_collection_t *collection, mongoc_update_flags_t flags, 
        const bson_t *selector, const bson_t *update, const mongoc_write_concern_t *write_concern, bson_error_t *error);
    bool mongoc_collection_delete (mongoc_collection_t *collection, mongoc_delete_flags_t flags, 
        const bson_t *selector, const mongoc_write_concern_t *write_concern, bson_error_t *error);
    bool mongoc_cursor_next (mongoc_cursor_t *cursor, const bson_t **bson);
    void mongoc_cursor_destroy (mongoc_cursor_t *cursor);
    bool mongoc_cursor_error (mongoc_cursor_t *cursor, bson_error_t *error);

    mongoc_gridfs_file_t *mongoc_gridfs_create_file (mongoc_gridfs_t *gridfs, mongoc_gridfs_file_opt_t *opt);
    mongoc_gridfs_file_t *mongoc_gridfs_find_one (mongoc_gridfs_t *gridfs, const bson_t *query, bson_error_t *error);
    mongoc_collection_t *mongoc_gridfs_get_files (mongoc_gridfs_t *gridfs);
    mongoc_collection_t *mongoc_gridfs_get_chunks (mongoc_gridfs_t *gridfs);
    void mongoc_gridfs_destroy (mongoc_gridfs_t *gridfs);
    bool mongoc_gridfs_remove_by_filename (mongoc_gridfs_t *gridfs, const char *filename, bson_error_t *error);

    const char* mongoc_gridfs_file_get_filename (mongoc_gridfs_file_t *file);
    const char* mongoc_gridfs_file_get_md5 (mongoc_gridfs_file_t *file);
    const bson_oid_t* mongoc_gridfs_file_get_files_id (mongoc_gridfs_file_t *file);
    int64_t mongoc_gridfs_file_get_length (mongoc_gridfs_file_t *file);
    int32_t mongoc_gridfs_file_get_chunk_size (mongoc_gridfs_file_t *file);
    int64_t mongoc_gridfs_file_get_upload_date (mongoc_gridfs_file_t *file);
    bool mongoc_gridfs_file_save (mongoc_gridfs_file_t *file);
    void mongoc_gridfs_file_destroy (mongoc_gridfs_file_t *file);
    int mongoc_gridfs_file_seek (mongoc_gridfs_file_t *file, uint64_t delta, int whence);
    uint64_t mongoc_gridfs_file_tell (mongoc_gridfs_file_t *file);
    bool mongoc_gridfs_file_remove (mongoc_gridfs_file_t *file, bson_error_t *error);
    bool mongoc_gridfs_file_error (mongoc_gridfs_file_t *file, bson_error_t *error);

    ssize_t mongoc_stream_write (mongoc_stream_t *stream, void *buf, size_t count, int32_t timeout_msec);
    ssize_t mongoc_stream_read (mongoc_stream_t *stream, void *buf, size_t count, size_t min_bytes, int32_t timeout_msec);
    mongoc_stream_t *mongoc_stream_file_new_for_path (const char *path, int flags, int mode);
    mongoc_gridfs_file_t *mongoc_gridfs_create_file_from_stream (mongoc_gridfs_t *gridfs, mongoc_stream_t *stream, mongoc_gridfs_file_opt_t *opt);
    mongoc_stream_t *mongoc_stream_gridfs_new (mongoc_gridfs_file_t *file);

]]

return {
    mongoc = mongoc
}
