local ffi = require "ffi"
local print = require("utils").prettyPrint
local mongo = require "mongo"
local bson = mongo.bson
local oid = mongo.oid
local client = mongo.client
local client_pool = mongo.client_pool

o = oid("")
print (o)
print (o.to_json())


o = oid("542a5b2069401b2edfb132a5")
print (o)
print (o.to_json())

o = oid('{"$oid": "542a5b2069401b2edfb132a5"}')
print (o)
print (o.to_json())


b = bson('{"BSON":["awesome",5.05,1986]}')
print (#b)
print (b.to_json())
print(b)

b = bson({BSON = {"awesome",5.05,1986}})
print (#b)
print (b.to_json())
print(b)

print (bson())

n = bson('{"hello": "world"}')
print (#n)
print (n.to_json())
print(n)

n = bson({["$hello"] = "world"})
print (#n)
print (n.to_json())
print(n)


n = bson({hello = {["$regex"] = "world"}})
print (#n)
print (n.to_json())
print(n.get_data())
print(tostring(n))



--c = client('mongodb://127.0.0.1:27017/')

p = client_pool('mongodb://127.0.0.1:27017/?minPoolSize=10')

print (tostring(p))

c = p.pop()
d = c.test
col = d.test
--print (col.name())
print (col.name())


r, e = col.insert({["$name"] = "testname"})
print ("insert", r, e)

query = {name = "testname1"}
r, e = col.insert(query)
print ("insert", r, e)

cursor = col.find(query)
-- print (cursor:data())
local p = ffi.new ("const bson_t *[1]")
print ("find", cursor.data())

r, e = col.delete(query)
print ("delete", r, e)

cursor = col.find(query)
print ("find", cursor.data())

query1 = {name = "testname"}
r, e = col.update(query, {["$set"] = query1})
print ("update", r, e)

cursor = col.find(query1)
-- print (cursor:data())
local p = ffi.new ("const bson_t *[1]")
while cursor.next(p) do
    print (p[0].to_table())
end

print (d.cmd({count = "test"}).data())
print (col.cmd({count = "test"}).data())
print (c.test["system.indexes"].find().data())

