local MIXINUUID_FUNCTIONUUID = load("stuff",nil,"b",_ENV)

local function do_stuff(a)
    MIXINUUID_FUNCTIONUUID()
    print("did stuff "  .. a)
end

for i=1,10 do
    print("hello world")
end

do_stuff(4)