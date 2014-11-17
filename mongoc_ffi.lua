local ffi = require "ffi"
local mongoc = ffi.load("libmongoc-1.0.so")
local cjson = require "cjson" 

ffi.cdef [[

    typedef struct
    {
       uint8_t bytes[12];
    } bson_oid_t;

    typedef struct _bson_t
    {
       uint32_t flags;        /* Internal flags for the bson_t. */
       uint32_t len;          /* Length of BSON data. */
       uint8_t padding[120];  /* Padding for stack allocation. */
    } bson_t;
    
    typedef struct _bson_context_t bson_context_t;

    typedef struct _bson_error_t
    {
       uint32_t domain;
       uint32_t code;
       char     message[504];
    } bson_error_t;

    typedef enum
    {
       BSON_SUBTYPE_BINARY = 0x00,
       BSON_SUBTYPE_FUNCTION = 0x01,
       BSON_SUBTYPE_BINARY_DEPRECATED = 0x02,
       BSON_SUBTYPE_UUID_DEPRECATED = 0x03,
       BSON_SUBTYPE_UUID = 0x04,
       BSON_SUBTYPE_MD5 = 0x05,
       BSON_SUBTYPE_USER = 0x80,
    } bson_subtype_t;

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

    /* for mongoc */
    typedef struct _mongoc_uri_t mongoc_uri_t;
    typedef struct _mongoc_client_pool_t mongoc_client_pool_t;
    typedef struct _mongoc_client_t mongoc_client_t;
    typedef struct _mongoc_database_t mongoc_database_t;
    typedef struct _mongoc_collection_t mongoc_collection_t;
    typedef struct _mongoc_gridfs_t mongoc_gridfs_t;
    typedef struct _mongoc_cursor_t mongoc_cursor_t;
    typedef struct _mongoc_read_prefs_t mongoc_read_prefs_t;

    typedef enum
    {
       MONGOC_QUERY_NONE              = 0,
       MONGOC_QUERY_TAILABLE_CURSOR   = 1 << 1,
       MONGOC_QUERY_SLAVE_OK          = 1 << 2,
       MONGOC_QUERY_OPLOG_REPLAY      = 1 << 3,
       MONGOC_QUERY_NO_CURSOR_TIMEOUT = 1 << 4,
       MONGOC_QUERY_AWAIT_DATA        = 1 << 5,
       MONGOC_QUERY_EXHAUST           = 1 << 6,
       MONGOC_QUERY_PARTIAL           = 1 << 7,
    } mongoc_query_flags_t;

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
/*
    int64_t mongoc_collection_count (mongoc_collection_t *collection, mongoc_query_flags_t flags, const bson_t *query, 
        int64_t skip, int64_t limit, const mongoc_read_prefs_t *read_prefs, bson_error_t *error);
    bool mongoc_collection_insert (mongoc_collection_t *collection, mongoc_insert_flags_t flags, 
        const bson_t *document, const mongoc_write_concern_t *write_concern, bson_error_t *error);
    bool mongoc_collection_update (mongoc_collection_t *collection, mongoc_update_flags_t flags, 
        const bson_t *selector, const bson_t *update, const mongoc_write_concern_t *write_concern, bson_error_t *error);
    bool mongoc_collection_delete (mongoc_collection_t *collection, mongoc_delete_flags_t flags, 
        const bson_t *selector, const mongoc_write_concern_t *write_concern, bson_error_t *error);
    bool mongoc_collection_find_and_modify (mongoc_collection_t *collection, const bson_t *query, 
        const bson_t *sort, const bson_t *update, const bson_t *fields, bool _remove, bool upsert, 
        bool _new, bson_t *reply, bson_error_t *error);
    bool mongoc_collection_remove (mongoc_collection_t *collection, mongoc_remove_flags_t flags, 
        const bson_t *selector, const mongoc_write_concern_t *write_concern, bson_error_t *error);
*/
    bool mongoc_cursor_next (mongoc_cursor_t *cursor, const bson_t **bson);
    void mongoc_cursor_destroy (mongoc_cursor_t *cursor);
    bool mongoc_cursor_error (mongoc_cursor_t *cursor, bson_error_t *error);

]]

return {
    mongoc = mongoc
}