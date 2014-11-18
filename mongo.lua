local ffi = require "ffi"
local mongoc_ffi = require "mongoc_ffi"
local mongoc = mongoc_ffi.mongoc
local cjson = require "cjson" 

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
    __index = function(self, key)
        local from_string = function ( str )
            local o = ffi.new('bson_oid_t')
            if str and #str >= 24 then
                if #str > 24 then
                    local j = cjson.decode(str)
                    str = j["$oid"]
                end
                mongoc.bson_oid_init_from_string(o, str)
            else
                mongoc.bson_oid_init(o, nil)
            end
            return o
        end
        local to_json = function ( o )
            local s = ffi.new('char[25]')
            mongoc.bson_oid_to_string(o, s)
            return '{"$oid": "' ..ffi.string(s)..'"}'
        end
        return key == "to_json" and function () return to_json(self) end or from_string
    end,
    __tostring = function ( o ) 
        local s = ffi.new("char[25]")
        mongoc.bson_oid_to_string(o, s)
        return ffi.string(s)
    end
})

local oid = setmetatable({}, {
    __call = function (self, str )
        return oid_t.from_string(str)
    end
})

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
        return ffi.gc(mongoc.mongoc_client_get_database(self, key), mongoc.mongoc_database_destroy)
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
                local size = 20 
                return ffi.gc(mongoc.mongoc_database_command(d, flags or 0, skip or 0, limit or size, size, bson(cmd), bson(fields or nil), prefs or nil), mongoc.mongoc_cursor_destroy)
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
                local size = size or 20
                return ffi.gc(mongoc.mongoc_collection_command(c, flags or 0, skip or 0, limit or size, size, bson(cmd), bson(fields or nil), prefs or nil), mongoc.mongoc_cursor_destroy)
            end,
            name = function ( c )
                return ffi.string(mongoc.mongoc_collection_get_name(c))
            end,
            find = function (c, query, fields, skip, limit, size, flags, prefs)
                local size = size or 20
                return ffi.gc(mongoc.mongoc_collection_find(c, flags or 0, skip or 0, limit or size, size, bson(query), bson(fields or nil), prefs or nil), mongoc.mongoc_cursor_destroy)
            end,
            insert = function (c, document)
                local d, i, e, id = bson(document), ffi.new("bson_iter_t"), ffi.new("bson_error_t"), nil
                if mongoc.bson_iter_init_find_case(i, d, "_id") then
                    id = mongoc.bson_iter_oid(d)
                else
                    id = oid("")
                    mongoc.bson_append_oid(d, "_id", 3, id)
                end
                local r = mongoc.mongoc_collection_insert(c, 0, d, nil, e)
                return r and id, ffi.string(e.message)
            end,
            update = function (c, select, update, flags)
                if not select then return false end
                local s, u, e = bson(select), bson(update), ffi.new("bson_error_t")
                local r = mongoc.mongoc_collection_update(c, flags or 3, s, u, nil, e)
                return r, ffi.string(e.message)
            end,
            delete = function (c, select, flags)
                if not select then return false end
                local s, e = bson(select), ffi.new("bson_error_t")
                local r = mongoc.mongoc_collection_delete(c, flags or 0, s, nil, e)
                return r, ffi.string(e.message)
            end
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
                mongoc.bson_append_int64(r, "length", 6, i)
                local err = mongoc.mongoc_cursor_error(c, e)
                mongoc.bson_append_bool(r, "error", 5, err)
                if (err) then
                    mongoc.bson_append_utf8(r, "message", 7, e.message)
                end
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
