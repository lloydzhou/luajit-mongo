luajit-mongo
============

mongo driver by using ffi, based on mongo-c-driver 1.0 or above

using for nginx
============
init the mongodb connection, it can using in every location.

    init_by_lua '
           mongo  = require "mongo"
           c = mongo.client("mongodb://127.0.0.1:27017")
    ';

define location, need another lua module [router](https://github.com/lloydzhou/router.lua).

    location /mongo {
       default_type application/json;
       content_by_lua '
           local router = require "router"
           local r = router.new()
    
           r:get("/mongo/:db/:coll", function(p)
               ngx.print(c[p.db][p.coll].find(mongo.bson(), mongo.bson(), 0, 20).data().to_json())
           end)
    
           if r:execute(
               string.lower(ngx.req.get_method()),
               ngx.var.request_uri,
               ngx.req.get_uri_args()
           ) then
               ngx.status = 200
           else
               ngx.status = 404
               ngx.print("{\"error\": true, \"message\": \"Not found!\"}")
           end
    
           ngx.eof()
       ';
    }



test
===========
    local ffi = require "ffi"
    local print = require("utils").prettyPrint
    local mongo = require "mongo"
    local bson = mongo.bson
    local oid = mongo.oid
    local client = mongo.client
    local client_pool = mongo.client_pool
    
    -- create one object id
    o = oid("")
    print (o)
    print (o.to_json())
    
    -- init obejct id by string
    o = oid("542a5b2069401b2edfb132a5")
    print (o)
    print (o.to_json())
    
    -- init object id by using json string
    o = oid('{"$oid": "542a5b2069401b2edfb132a5"}')
    print (o)
    print (o.to_json())
    
    -- init bson object by using json string
    b = bson('{"BSON":["awesome",5.05,1986]}')
    print (#b)
    print (b.to_json())
    print(b)
    
    -- init bson object by using lua table
    b = bson({BSON = {"awesome",5.05,1986}})
    print (#b)
    print (b.to_json())
    print(b)
    
    -- init one empty bson object
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
    
    
    -- connect mongodb by using uri string.
    --c = client('mongodb://127.0.0.1:27017/')
    
    -- using connection pool.
    p = client_pool('mongodb://127.0.0.1:27017/?minPoolSize=10')
    
    -- get one connection from pool
    c = p.pop()
    -- get one database object
    d = c.test
    -- get one collection object
    col = d.test
    print (col.name())
    
    -- test for insert
    r, e = col.insert({["$name"] = "testname"})
    print ("insert", r, e)
    
    query = {name = "testname1"}
    r, e = col.insert(query)
    print ("insert", r, e)
    
    -- test for query data from database
    cursor = col.find(query)
    -- cursor.data() return the results in bson format. will output in json by call "__tostring" function of bson object.
    print ("find", cursor.data())
    -- test delete data
    r, e = col.delete(query)
    print ("delete", r, e)
    
    cursor = col.find(query)
    print ("find", cursor.data())
    
    -- test update function
    query1 = {name = "testname"}
    r, e = col.update(query, {["$set"] = query1})
    print ("update", r, e)
    
    -- test the "next" function of cursor object.
    cursor = col.find(query1)
    local p = ffi.new ("const bson_t *[1]")
    while cursor.next(p) do
        print (p[0].to_table())
    end
    
    print (d.cmd({count = "test"}).data())
    print (col.cmd({count = "test"}).data())
    print (c.test["system.indexes"].find().data())
