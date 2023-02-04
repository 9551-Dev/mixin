local mixin        = {}
local manipulation = {}

local function lookupify(tbl)
    local lookup = {}
    for k,v in pairs(tbl) do lookup[v] = k end
    return lookup
end

local function combined_lookup(a,b)
    local lookup = {}
    for k,v in pairs(b) do lookup[a[k]] = v end
    return lookup
end

local keywords = {
    "and",   "break", "do",  "else",    "elseif",
    "end",   "false", "for", "function","if",
    "in",    "local", "nil", "not",     "or",
    "repeat","return","then","true",    "until","while"
}

local tokens = {
    "+", "-", "*", "/", "%", "^","#",
    "==","~=","<=",">=","<", ">","=",
    "(", ")", "{", "}", "[", "]",
    ";", ":", ",", ".", "..","..."
}

local keyword_typing = {
    "boolean_operator","keyword_break"   ,"scope_open","scope_open"         ,"scope_open",
    "scope_end"       ,"value"           ,"loop"      ,"function_definition","condition",
    "keyword_iterator","local_definition","value"     ,"boolean_operator"   ,"boolean_operator",
    "loop"            ,"function_return" ,"scope_open","value","scope_end"  ,"loop"
}

local token_typing = {
    "add","sub","mul","div","mod","pow","len",
    "eq","neq","lqt","mqt","lt","mt","set",
    "bracket","bracket","bracket","bracket","bracket","bracket",
    "semicolon","self_index","separator","index","concat","args"
}

local keyword_value_proccessor = {
    value={
        ["true"] =function() return true  end,
        ["false"]=function() return false end,
        ["nil"]  =function() return nil   end
    },
}

local expansible_tokens = {
    ["="]  ="=",
    ["=="] ="=",
    ["~"]  ="=",
    ["~="] ="=",
    ["<"]  ="=",
    ["<="] ="=",
    [">"]  ="=",
    [">="] ="=",
    ["."]  =".",
    [".."] =".",
    ["..."]="",
    ["["]  ="[",
    ["[["] ="[",
    ["]"]  ="]",
    ["]]"] ="]"
}

local scope = {
    open_begin = lookupify{
        "if","elseif","while","for"
    },
    open = lookupify{
        "do","else","then","function","repeat"
    },
    close = lookupify{
        "end","elseif","else","until"
    }
}

local keyword_lookup = combined_lookup(keywords,keyword_typing)
local token_lookup   = lookupify      (tokens)

local function make_type(token)
    local out
    if keyword_lookup[token] then
        out = "lua_keyword"
    elseif token_lookup[token] then
        out = "lua_token"
    elseif token:match("^\".+\"$") then
        out = "string"
    elseif token:match("(%d*%.?%d+)") then
        out = "number"
    else out = "variable" end
    
    return out
end

local function make_value(token)
    local out
    if keyword_lookup[token] then
        local keyword_type = keyword_lookup[token]
        if keyword_type and keyword_value_proccessor[keyword_type] then
            out = keyword_value_proccessor[keyword_type][token]()
        end
    elseif token_lookup[token] then
        out = "lua_token"
    elseif token:match("^\".+\"$") then
        out = token:match("^\"(.+)\"$")
    elseif token:match("(%d*%.?%d+)") then
        out = tonumber(token)
    else out = token end
    
    return out
end

local scope_token_processor = {
    ["if"] = function(out,buffer,token_index)
        out.index  = token_index
        out.start  = buffer[1]
        out.finish = buffer[#buffer]

        out.condition = {table.unpack(buffer,2,#buffer-1)}

        return out
    end,
    ["elseif"] = function(out,buffer,token_index)
        out.index  = token_index
        out.start  = buffer[1]
        out.finish = buffer[#buffer]

        out.condition = {table.unpack(buffer,2,#buffer-1)}

        return out
    end,
    ["while"] = function(out,buffer,token_index)
        out.index  = token_index
        out.start  = buffer[1]
        out.finish = buffer[#buffer]
        
        out.condition = {table.unpack(buffer,2,#buffer-1)}

        return out
    end,
    ["for"] = function(out,buffer,token_index)
        out.index  = token_index
        out.start  = buffer[1]
        out.finish = buffer[#buffer]

        out.condition = {table.unpack(buffer,2,#buffer-1)}

        return out
    end
}

local TOKEN_MT = {__tostring=function(self) return "TOKEN: " .. self.type  end}
local SCOPE_MT = {__tostring=function(self) return "SCOPE: " .. self.index end}

local function parse_token(out,token)
    out.object = "token"
    out.name   = token
    out.type   = make_type(token)
    out.value  = make_value(token)

    setmetatable(out,TOKEN_MT)

    return out
end

local function parse_tokens(tokens)
    local conditions = tokens.condition
    if conditions then
        for k,v in pairs(conditions) do
            conditions[k] = parse_token({},v)
        end
    end
    return tokens
end

local function remove_parents(t)
    t.parent = nil
    for k,v in pairs(t) do
        if type(v) == "table" then
            remove_parents(v)
        end
    end

    return t
end

local function tokenize(str)
    local tokens = {}
    local token = ""

    local is_string   = false
    local is_number   = false
    local escape_next = false

    local can_expand = ""

    for i=1,#str do
        local char      = str:sub(i,i)
        local next_char = str:sub(i+1,i+1)

        if char == "\'" or char == "\"" then
            if not escape_next then is_string = not is_string end
        end
        if char == "\\" then
            escape_next = true
        end

        if not is_string and (char:match("%d") or (char == "." and next_char:match("%d"))) then
            is_number = true
        elseif char ~= "." then
            is_number = false
        end

        if char:match("%s") and not is_string then
            if token ~= "" then tokens[#tokens+1] = token end
            token = ""
        elseif token_lookup[char] and not is_string and not is_number then
            if token ~= "" then tokens[#tokens+1] = token end
            
            if not expansible_tokens[char] then
                tokens[#tokens+1] = char
            end

            token = ""
        elseif not expansible_tokens[char] or is_string or is_number then
            token = token .. char
            escape_next = false
        end

        if (((expansible_tokens[can_expand] == char) or (can_expand == "" and expansible_tokens[char])) and not is_string) and not is_number then
            can_expand = can_expand .. char
            if not expansible_tokens[can_expand .. next_char] then
                tokens[#tokens+1] = can_expand
                can_expand = ""
            end
        end
    end

    if token ~= "" then tokens[#tokens+1] = token end

    return tokens
end

local function process_tokens(t)
    local current_scope = {}

    local token_buffer = {}
    local buffer_open  = false

    local scope_index = 0

    for i=1,#t do
        local current_token = t[i]

        if scope.open_begin[current_token] then
            buffer_open = true
        end
        if buffer_open then
            token_buffer[#token_buffer+1] = current_token
        end

        if scope.close[current_token] then
            current_scope = current_scope.parent
        end

        current_scope[#current_scope+1] = parse_token({},current_token)
        
        if scope.open[current_token] then

            scope_index = scope_index + 1

            local definition_tokens = scope_token_processor[token_buffer[1]]
            local finished_token_list
            if definition_tokens then
                finished_token_list = parse_tokens(definition_tokens({},token_buffer,i))
            end

            local new_scope = setmetatable({
                index = scope_index,
                definition_tokens = finished_token_list,
                parent  = current_scope,
                keyword = current_token,
                object  = "scope"
            },SCOPE_MT)

            token_buffer = {}
            buffer_open = false

            current_scope[#current_scope+1] = new_scope

            current_scope = new_scope
        end
    end

    return current_scope
end

local function construct_code(t)
    local code = ""

    for k,v in ipairs(t) do
        if v.object == "scope" then
            code = code .. construct_code(v) .. "\n"
        else
            code = code .. v.name .. " "
        end
    end

    return code
end

function mixin.create_system()
end

local to_tokenize = {"nimg.lua"}
local data = {}

for k,v in ipairs(to_tokenize) do
    local f = fs.open(v,"r")
    local d = f.readAll()
    f.close()
    data[v] = tokenize(d)
end

return construct_code(remove_parents(process_tokens(data["nimg.lua"])))