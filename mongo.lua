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
    bool bson_append_document_begin (bson_t *bson, const char *key, int key_length, bson_t *child);
    bool bson_append_document (bson_t *bson, const char *key, int key_length, const bson_t *value);
    bool bson_append_document_end (bson_t *bson, bson_t *child);
    bool bson_append_binary (bson_t *bson, const char *key, int key_length, bson_subtype_t subtype, const uint8_t *binary, uint32_t length);
    bool bson_append_bool (bson_t *bson, const char *key, int key_length, bool value);
    bool bson_append_double (bson_t *bson, const char *key, int key_length, double value);
    bool bson_append_int32 (bson_t *bson, const char *key, int key_length, int32_t value);
    bool bson_append_int64 (bson_t *bson, const char *key, int key_length, int64_t value);
    bool bson_append_null (bson_t *bson, const char *key, int key_length);
    bool bson_append_oid (bson_t *bson, const char *key, int key_length, const bson_oid_t *oid);
    bool bson_append_regex (bson_t *bson, const char *key, int key_length, const char *regex, const char *options);
    bool bson_append_utf8 (bson_t *bson, const char *key, int key_length, const char *value, int length);
    bool bson_append_now_utc (bson_t *bson, const char *key, int key_length);

]]

local bson_t = ffi.metatype("bson_t", {
    __len = function(b) return b.len end,
    __index = function (self, key)
        local sfunc, func = {
            to_json = function ( b ) return ffi.string(mongoc.bson_as_json(b, nil)) end,
            to_table = function ( b ) return cjson.decode(ffi.string(mongoc.bson_as_json(b, nil))) end,
            get_data = function ( b ) return ffi.string(mongoc.bson_get_data(b), b.len) end 
        }, {
            new = function () return ffi.gc(mongoc.bson_new(), mongoc.bson_destroy) end,
            from_json = function (str) 
                local b = ffi.gc(mongoc.bson_new(), mongoc.bson_destroy)
                local e = ffi.new('bson_error_t')
                if str then
                    mongoc.bson_init_from_json(b, str, #str, e) 
                end
                return b
            end,
        }
        local f = rawget(sfunc, key)
        return f and function () return f(self) end or rawget(func, key)
    end,
    __tostring = function ( b ) return ffi.string(mongoc.bson_as_json(b, nil))  end
})

local bson = setmetatable( {}, {
    __call = function (self, str)
        return bson_t.from_json(type(str) ~= "string" and cjson.encode(str) or str)
    end
})

local oid_t = ffi.metatype("bson_oid_t", {
    __index = {
        from_string = function ( str )
            local o = ffi.new('bson_oid_t')
            if str and #str >= 24 then
                if #str > 24 then
                    local o = ffi.new('bson_oid_t')
                    local j = cjson.decode(str)
                    str = j["$oid"]
                end
                mongoc.bson_oid_init_from_string(o, str)
            else
                mongoc.bson_oid_init(o, nil)
            end
            return o
        end,
        to_json = function ( o )
            local s = ffi.new('char[25]')
            mongoc.bson_oid_to_string(o, s)
            return '{"$oid": "' ..ffi.string(s)..'"}'
        end
    },
    __tostring = function ( o )
        local s = ffi.new('char[25]')
        mongoc.bson_oid_to_string(o, s)
        return ffi.string(s)
    end
})

local oid = setmetatable({}, {
    __call = function (self, str )
        return oid_t.from_string(str)
    end
})

ffi.cdef [[
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

local mongoc_client_pool = ffi.metatype('mongoc_client_pool_t', {
    __index = function ( self, key )
        local func = {
            pop = function ( pool )
                return mongoc.mongoc_client_pool_pop( pool )
            end,
            push = function ( pool, client )
                return mongoc.mongoc_client_pool_push( pool, client)
            end
        }
        local f = rawget( func, key )
        return f and function ( ... ) return f( self, ... )  end
    end,
    __tostring = function ( pool )
        return pool.size, pool.min_pool_size, pool.max_pool_size
        -- return "pool"
        -- return ffi.typeof(p.size), p.size, p.min_pool_size, p.max_pool_size
        -- return "min_pool_size: ".. p.min_pool_size .. ", max_pool_size: "..p.max_pool_size..", size: "..p.size
    end
})

local client_pool = setmetatable({}, {
    __call = function (self, url)
        local uri = ffi.gc(mongoc.mongoc_uri_new(url), mongoc.mongoc_uri_destroy)
        return ffi.gc(mongoc.mongoc_client_pool_new(uri), mongoc.mongoc_client_pool_destroy)
    end
})


local mongo_client = ffi.metatype('mongoc_client_t', {
    __index = function ( self, key )
        local func = {
            testfunc = function ( m )
                print (m)
            end
        }
        return rawget(func, key) or ffi.gc(mongoc.mongoc_client_get_database(self, key), mongoc.mongoc_database_destroy)
    end,
    __tostring = function (self)
        return ''
    end
})

local client = setmetatable({}, {
    __call = function (self, url)
        local c = rawget(self, url)
        if not c then
            c = ffi.gc(mongoc.mongoc_client_new(url), mongoc.mongoc_client_destroy)
            rawset(self, url, c)
        end
        return c 
    end
})


local mongo_database = ffi.metatype('mongoc_database_t', {
    __index = function ( self, key )
        local sfunc = {
            cmd = function (d, cmd, fields, skip, limit, size, flags, prefs) 
                return ffi.gc(mongoc.mongoc_database_command(d, flags or 0, skip or 0, limit or 20, size or 20, cmd, fields or nil, prefs or nil), mongoc.mongoc_cursor_destroy)
            end,
            name = function ( d )
                return ffi.string(mongoc.mongoc_database_get_name(d))
            end,
            fs = function ()
            end,
        }
        local f = rawget(sfunc, key)
        return f and function (...) return f(self, ...) end or ffi.gc(mongoc.mongoc_database_get_collection(self, key), mongoc.mongoc_collection_destroy)
    end,
    __tostring = function ( d )
        return ffi.string(mongoc.mongoc_database_get_name(d))
    end
})

local mongo_collection = ffi.metatype('mongoc_collection_t', {
    __index = function ( self, key )
        local sfunc = {
            cmd = function (c, cmd, fields, skip, limit, size, flags, prefs) 
                return ffi.gc(mongoc.mongoc_collection_command(c, flags or 0, skip or 0, limit or 20, size or 20, cmd, fields or nil, prefs or nil), mongoc.mongoc_cursor_destroy)
            end,
            name = function ( c )
                return ffi.string(mongoc.mongoc_collection_get_name(c))
            end,
            find = function (c, query, fields, skip, limit, size, flags, prefs) 
                return ffi.gc(mongoc.mongoc_collection_find(c, flags or 0, skip or 0, limit or 0, size or 0, query, fields or nil, prefs or nil), mongoc.mongoc_cursor_destroy)
            end,
            insert = function (c, query, fields, skip, limit, size, flags, prefs) 
                return ffi.gc(mongoc.mongoc_collection_find(c, flags or 0, skip or 0, limit or 0, size or 0, query, fields or nil, prefs or nil), mongoc.mongoc_cursor_destroy)
            end,
        }
        local f = rawget(sfunc, key)
        return f and function (...) return f(self, ...) end or ffi.gc(mongoc.mongoc_database_get_collection(self, key), mongoc.mongoc_collection_destroy)
    end,
    __tostring = function ( d )
        return ffi.string(mongoc.mongoc_collection_get_name(d))
    end
})

local mongo_cursor = ffi.metatype('mongoc_cursor_t', {
    __index = function (self, key)
        local func = {
            next = function (c, pb)
                return mongoc.mongoc_cursor_next(c, pb)
            end,
            data = function (c)
                local p, e, r, d, k, i = ffi.new ('const bson_t *[1]'), ffi.new ('bson_error_t *'), bson(), bson('[]'), 'res', 0
                mongoc.bson_append_array_begin(r, k, #k, d)
                while mongoc.mongoc_cursor_next(c, p) do 
                    local ii = tostring(i)
                    mongoc.bson_append_document(d, ii, #ii, p[0])
                    i = i + 1
                end
                mongoc.bson_append_array_end(r, d)
                -- mongoc.bson_append_array(r, k, #k, d)
                local err = mongoc.mongoc_cursor_error(c, e)
                mongoc.bson_append_bool(r, "error", 5, err)
                if (err) then
                    mongoc.bson_append_utf8(r, "message", 7, e.message)
                end
                -- print (e.message)
                return r
            end
        }
        local f = rawget(func, key)
        return f and function (...) return f(self, ...) end
    end
})

return {
    bson = bson, 
    oid = oid,
    client = client,
    client_pool = client_pool,
    c = mongoc
}
