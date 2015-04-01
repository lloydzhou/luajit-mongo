local ffi = require "ffi"
local mongoc_ffi = require "mongoc_ffi"
local mongoc = mongoc_ffi.mongoc
local cjson = require "cjson" 

local bson_t = ffi.metatype("bson_t", {
    __len = function(b) return b.len end,
    __index = function (self, key)
        local sfunc, func = {
            to_json = function ( b ) return ffi.string(mongoc.bson_as_json(b, nil)) end,
            to_table = function ( b ) return bson_decode(b) end,
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
            end,
            table = function(c)
                return bson_decode(func.data(c))
            end
        }
        local f = rawget(func, key)
        return f and function (...) return f(self, ...) end
    end
})
local mongoc_gridfs = ffi.metatype('mongoc_gridfs_t', {
    __index = function(self, key)
        local getopt = function(filename, content_type, chunk_size)
            local opt = ffi.new('mongoc_gridfs_file_opt_t')
            opt.filename = filename 
            opt.content_type = content_type or "application/octet-stream"
            opt.chunk_size = chunk_size or 262144
            return opt
        end
        local func = {
            get = function(g, query_or_filename)
                local e = ffi.new('bson_error_t')
                local query = type(query_or_filename) == "string" and bson({["filename"] = query_or_filename}) or bson(query_or_filename)
                return mongoc.mongoc_gridfs_find_one(g, query, e), e
            end,
            put = function(g, filename, content_type, chunk_size)
                local stream, opt = mongoc.mongoc_stream_file_new_for_path(filename, 0, 0), getopt(filename, content_type, chunk_size)
                local file = mongoc.mongoc_gridfs_create_file_from_stream(g, stream, opt)
                return mongoc.mongoc_gridfs_file_save(file)
            end,
            create = function(g, filename)
                local file = mongoc.mongoc_gridfs_create_file(self, getopt(filename))
                mongoc.mongoc_gridfs_file_save(file)
                return file
            end,
            files = function(g)

            end
        }
        local f = rawget(func, key)
        return f and function(...) return f(self, ...) end or func.create(self, key)
    end,
    __tostring = function (g)
        return tostring(mongoc.mongoc_gridfs_get_files(g)) .. ", " .. tostring(mongoc.mongoc_gridfs_get_chunks(g))
    end
})
local mongoc_gridfs_file = ffi.metatype('mongoc_gridfs_file_t', {
    __index = function(self, key)
        local func = {
            read = function(f)
                local r, size, s = {}, 4096, mongoc.mongoc_stream_gridfs_new(f)
                local buf = ffi.new('char[?]', size)
                while 1 do
                    local bs = mongoc.mongoc_stream_read(s, buf, size-1, -1, 0)
                    if (bs == 0) then break end
                    table.insert(r, ffi.string(buf, bs))
                end
                return table.concat(r)
            end,
            write = function(f, buffer)
                return mongoc.mongoc_stream_write(mongoc.mongoc_stream_gridfs_new(f), ffi.cast('char*', buffer), #buffer, 0) 
            end
        }
        local cfunc = function(key)
            local t = { ['get_filename'] = 1, ['get_length'] = 1,  ['get_chunk_size'] = 1, ['get_upload_date'] = 1, 
                        ['save'] = 1, ['seek'] = 1, ['tell'] = 1, ['remove'] = 1, ['error'] = 1}
            if not rawget(t , key) then 
                return function() print ("function \"mongoc_gridfs_file_" .. key .. "\" not avalible!") end 
            end
            -- if function not define in mongoc, will catch exception.
            local cf = mongoc["mongoc_gridfs_file_" .. key]
            return cf and function(...) return cf(self, ...) end
        end
        local f = rawget(func, key)
        return f and function(...) return f(self, ...) end or cfunc(key)
    end,
    -- __tostring = function(f)
    --     return f and "filename: " .. ffi.string(mongoc.mongoc_gridfs_file_get_filename(f))
    -- end
})
function bson_decode (bson, keys, depth)
    local values, depth = setmetatable({}, {__index={isobj=keys ~= false}}), depth or 0
    if depth > 1000 then return values end
    local append = function(k,v)
        if values.isobj then
            values[ffi.string(k)] = v
        else
            table.insert(values, v)
        end
        return false
    end

    local v = ffi.new("bson_visitor_t")
    v.visit_int32 = function(i, k, v, d) return append(k, v) end
    v.visit_int64 = function(i, k, v, d) return append(k, v) end
    v.visit_double = function(i, k, v, d) return append(k, v) end
    v.visit_utf8 = function(i, k, vl, v, d) return append(k, ffi.string(v, vl)) end
    v.visit_document = function(i, k, vd, d) return append(k, bson_decode(vd, true, depth+1)) end
    v.visit_array = function(i, k, vd, d) return append(k, bson_decode(vd, false, depth+1)) end
    v.visit_bool = function(i, k, vb, d) return append(k, vb) end
    v.visit_null = function(i, k, d) return append(k, nil) end
    v.visit_regex = function(i, k, r, o, d) return append(k, {["$regex"] = ffi.string(r), ["$options"] = ffi.string(o)}) end
    v.visit_date_time = function(i, k, m, d) return append(k, {["$date"] = m}) end
    v.visit_timestamp = function(i, k, t, i, d) return append(k, {["$timestamp"] = {["t"] = t, ["i"] = i}}) end
    v.visit_maxkey = function(i, k, d) return append(k, {["$maxkey"] = 1}) end
    v.visit_minkey = function(i, k, d) return append(k, {["$minkey"] = 1}) end
    v.visit_undefined = function(i, k, d) return false end
    v.visit_code = function(i, k, cl, c, d) return append(k, ffi.string(mongoc.bson_utf8_escape_for_json(c, cl))) end
    v.visit_codewscope = function(i, k, cl, c, s, d) return append(k, ffi.string(mongoc.bson_utf8_escape_for_json(c, cl))) end
    v.visit_symbol = function(i, k, sl, s, d) return append(k, ffi.string(s, sl)) end
    v.visit_oid = function(i, k, vo, d)
        local s = ffi.new("char[25]")
        mongoc.bson_oid_to_string(vo, s)
        append(k, {["$oid"] = ffi.string(s)})
        return false
    end
    v.visit_binary = function(i, k, sub, bl, vb, d)
        local b64l = (bl/3+1)*4+1
        local b64 = mongoc.bson_malloc0(b64l)
        mongoc.b64_ntop(vb, bl, b64, b64l)
        append(k, {["$type"] = sub, ["$binary"] = ffi.string(b64, b64l)})
        return false
    end
    v.visit_dbpointer = function(i, k, collen, col, oid, d)
        local dp = {["$ref"] = ffi.string(col, collen)}
        if oid then
            local s = ffi.new("char[25]")
            mongoc.bson_oid_to_string(oid, s)
            dp["$id"] = ffi.string(s)
        end
        return append(k, dp)
    end

    local i = ffi.new("bson_iter_t")
    if mongoc.bson_iter_init(i, bson) then
        mongoc.bson_iter_visit_all(i, v, nil)
    end
    i, v = nil, nil
    return values
end
return {
    bson = bson, 
    oid = oid,
    client = client,
    client_pool = client_pool,
    bson_decode = bson_decode,
    c = mongoc
}
