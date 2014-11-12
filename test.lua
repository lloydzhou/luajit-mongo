local ffi = require "ffi"
local print = require("utils").prettyPrint
local mongo = require "mongo"
local bson = mongo.bson
local oid = mongo.oid
local client = mongo.client

o = oid("")
print (o)
print (o:to_json())


o = oid("542a5b2069401b2edfb132a5")
print (o)
print (o:to_json())

o = oid('{"$oid": "542a5b2069401b2edfb132a5"}')
print (o)
print (o:to_json())


b = bson('{"BSON":["awesome",5.05,1986]}')
print (#b)
print (b:to_json())
print(b)

b = bson({BSON = {"awesome",5.05,1986}})
print (#b)
print (b:to_json())
print(b)


n = bson('{"hello": "world"}')
print (#n)
print (n:to_json())
print(n)

n = bson({["$hello"] = "world"})
print (#n)
print (n:to_json())
print(n)


n = bson({hello = {["$regex"] = "world"}})
print (#n)
print (n:to_json())
print(n:get_data())
print(tostring(n))


c = client('mongodb://127.0.0.1:27017/')
--c:testfunc('sdfsd')
d = c.test
col = d.test
print (col:name())

query = bson('{"name": "testname"}')

cursor = col:find(query)
-- print (cursor:data())
local p = ffi.new ("const bson_t *[1]")
while cursor:next(p) do
    print (p[0]:to_table())
end

print (d:cmd(bson({count = "test"})):data())
print (col:cmd(bson({count = "test"})):data())
print (c.test["system.indexes"]:find(bson()):data())
