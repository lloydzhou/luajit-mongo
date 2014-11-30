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
        if key == 'gridfs' or key == 'fs' then return function(dbname, prefix) 
            return ffi.gc(mongoc.mongoc_client_get_gridfs(self, dbname, prefix or 'fs', ffi.new('bson_error_t')), mongoc.mongoc_gridfs_destroy) end 
        end
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
            end
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
                pb = pb or ffi.new('const bson_t *[1]')
                return mongoc.mongoc_cursor_next(c, pb) and pb[0] or nil
            end,
            data = function (c)
                local p, e, r, d, k, i = ffi.new ('const bson_t *[1]'), ffi.new ('bson_error_t'), bson(), bson('[]'), 'res', 0
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
                    mongoc.bson_append_int64(r, "code", 4, e.code)
                    mongoc.bson_append_utf8(r, "message", 7, e.message)
                end
                return r
            end
        }
        local f = rawget(func, key)
        return f and function (...) return f(self, ...) end
    end
})
local mongoc_gridfs = ffi.metatype('mongoc_gridfs_t', {
    __index = function(self, key)
        local new = function(f, name, content_type, chunk_size)
            local opt = ffi.new('mongoc_gridfs_file_opt_t')
            opt.filename = name 
            opt.content_type = content_type or "application/octet-stream"
            opt.chunk_size = chunk_size or 262144
            return mongoc.mongoc_gridfs_create_file(f, opt)
        end
        local func = {
            get = function(g, query_or_filename)
                local e = ffi.new('bson_error_t')
                local query = type(query_or_filename) == "string" and bson({["filename"] = query_or_filename}) or bson(query_or_filename)
                print(query)
                return mongoc.mongoc_gridfs_find_one(g, query, e), e
            end,
            put = function(g, filename, content_type, chunk_size)
                local stream = mongoc.mongoc_stream_file_new_for_path(filename, 0, 0)
                local opt = ffi.new('mongoc_gridfs_file_opt_t')
                opt.filename = filename 
                opt.content_type = content_type or "application/octet-stream"
                opt.chunk_size = chunk_size or 262144
                local file = mongoc.mongoc_gridfs_create_file_from_stream(g, stream, opt)
                return mongoc.mongoc_gridfs_file_save(file)
            end
        }
        local f = rawget(func, key)
        return f and function(...) return f(self, ...) end or ffi.gc(mongoc.mongoc_gridfs_create_file(self, nil), mongoc.mongoc_gridfs_file_destroy)
    end,
    __tostring = function (g)
        return tostring(mongoc.mongoc_gridfs_get_files(g)) .. ", " .. tostring(mongoc.mongoc_gridfs_get_chunks(g))
    end
})
local mongoc_gridfs_file = ffi.metatype('mongoc_gridfs_file_t', {
    __index = function(self, key)
        local func = {
            save = function(f)
                return mongoc.mongoc_gridfs_file_save(f)
            end,
            read = function(f)
                local r, size, s = {}, 4096, ffi.gc(mongoc.mongoc_stream_gridfs_new(f), mongoc.mongoc_stream_destroy)
                local buf = ffi.new('char[?]', size)
                while 1 do
                    local bs = mongoc.mongoc_stream_read(s, buf, size-1, -1, 0)
                    if (bs == 0) then break end
                    table.insert(r, ffi.string(buf, bs))
                end
                return table.concat(r)
            end,
            write = function(f, buffer)
                local iov = ffi.new('mongoc_iovec_t[2]')
                -- , #buffer, ffi.cast('char*', buffer)
                -- local stream = mongoc.mongoc_stream_gridfs_new(f)
                local stream = ffi.new('mongoc_stream_t*')
                local st = mongoc.mongoc_stream_buffered_new(stream, 4096)
                iov[0].iov_len = #buffer-1
                iov[0].iov_base = ffi.cast('char*', buffer)
                iov[1].iov_len = #buffer
                iov[1].iov_base = ffi.cast('char*', buffer)
                print (iov, f)
                print (iov[0].iov_len, ffi.string(iov[0].iov_base, iov[0].iov_len))
                print (iov[1].iov_len, ffi.string(iov[1].iov_base, iov[1].iov_len))
                print (f, iov)
                -- mongoc.mongoc_stream_writev(st, iov, 0, 0)
                -- mongoc.mongoc_gridfs_file_save(f)
                mongoc.mongoc_gridfs_file_writev(f, iov, 1, 0)
                -- return mongoc.mongoc_gridfs_file_save(f)
            end
        }
        local f = rawget(func, key)
        return f and function(...) return f(self, ...) end
    end,
    -- __tostring = function(f)
    --     return f and "filename: " .. ffi.string(mongoc.mongoc_gridfs_file_get_filename(f))
    -- end
})
return {
    bson = bson, 
    oid = oid,
    client = client,
    client_pool = client_pool,
    c = mongoc
}
