local ffi = require "ffi"
local print = require("utils").prettyPrint
local mongo = require "mongo"
local bson = mongo.bson
local client_pool = mongo.client_pool

local p = client_pool('mongodb://127.0.0.1:27017/?minPoolSize=10')
local c = p.pop()
local fs = c.fs('test', 'fs')

local file = fs.create('testname')
print (tostring(file))
file.write("sdfsdfgf")
file.save()
local id = ffi.new("bson_value_t")
file.get_id(id)
print (id.value.v_oid)
print (file.files_id.value.v_oid)

