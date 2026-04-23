local console_vector = 0
local function zeros(len)
    local t = {}
    for i = 0, len - 1 do t[i] = 0 end
    return t
end

local ram = zeros(0x10000)
local dev = zeros(0x100)
local ptr = { [0]=0, [1]=0 }
local stk = { [0]=zeros(0x100), [1]=zeros(0x100) }

local function emu_dei(port)
    return dev[port&0xFF]
end

local function emu_deo(port, value)
    dev[port&0xFF] = value
    if port == 0x11 then
        console_vector = dev[0x10] << 8 | value
    elseif port == 0x18 then
        io.write(string.char(value))
    elseif port == 0x19 then
        io.stderr:write(string.char(value))
    end
end

local ops
local d, r, k
local pc, a, b, c = 0, {0}, {0}, {0}
local x, y, z = zeros(2), zeros(2), zeros(2)
local function OPC(opc, A, B)
    ops[0x00|opc] = function() d=0;r=0;A();B() end
    ops[0x20|opc] = function() d=1;r=0;A();B() end
    ops[0x40|opc] = function() d=0;r=1;A();B() end
    ops[0x60|opc] = function() d=1;r=1;A();B() end
    ops[0x80|opc] = function() d=0;r=0;k=ptr[0];A();ptr[0]=k;B() end
    ops[0xa0|opc] = function() d=1;r=0;k=ptr[0];A();ptr[0]=k;B() end
    ops[0xc0|opc] = function() d=0;r=1;k=ptr[1];A();ptr[1]=k;B() end
    ops[0xe0|opc] = function() d=1;r=1;k=ptr[1];A();ptr[1]=k;B() end
end
local function DEC(m) local t=ptr[m]-1&0xFF;ptr[m]=t;return t end
local function INC(m) local t=ptr[m];ptr[m]=t+1&0xFF;return t end
local function IMM() a[1]=ram[pc] << 8 | ram[pc+1&0xFFFF];pc = pc+2&0xFFFF end
local function MOV() pc = d > 0 and a[1] or pc + (a[1]~0x80)-0x80 & 0xFFFF end
local function POx(o,m) o[1] = stk[r][DEC(r)]; if m > 0 then o[1] = o[1] | stk[r][DEC(r)] << 8 end end
local function PUx(i,m,s) if m > 0 then c = i; stk[s][INC(s)] = c >> 8 & 0xFF; stk[s][INC(s)] = c & 0xFF else stk[s][INC(s)] = i&0xFF end end
local function GOT(o) if d > 0 then o[1] = stk[r][DEC(r)] end o[0] = stk[r][DEC(r)] end
local function PUT(i,s) stk[s][INC(s)] = i[0]; if d > 0 then stk[s][INC(s)] = i[1] end end
local function DEO(o,v) emu_deo(o, v[0]); if d > 0 then emu_deo(o + 1, v[1]) end end
local function DEI(i,v) v[0] = emu_dei(i); if d > 0 then v[1] = emu_dei(i + 1) end; PUT(v,r) end
local function POK(o,v,m) ram[o] = v[0]; if d > 0 then ram[(o + 1) & m] = v[1] end end
local function PEK(i,v,m) v[0] = ram[i]; if d > 0 then v[1] = ram[(i + 1) & m] end; PUT(v,r) end
ops = {
    [0x00]=function() return 1 end, -- BRK
    [0x20]=function() if stk[0][DEC(0)] > 0 then IMM(); pc=pc+a[1]&0xFFFF else pc=pc+2&0xFFFF end end, -- JCI
    [0x40]=function() IMM(); pc=pc+a[1]&0xFFFF end, -- JMI
    [0x60]=function() IMM(); PUx(pc, 1, 1); pc=pc+a[1]&0xFFFF end, -- JSI
    [0x80]=function() stk[0][INC(0)] = ram[pc]; pc=pc+1&0xFFFF end, -- LIT
    [0xa0]=function() stk[0][INC(0)] = ram[pc]; stk[0][INC(0)] = ram[pc+1&0xFFFF]; pc=pc+2&0xFFFF end, -- LI2
    [0xc0]=function() stk[1][INC(1)] = ram[pc]; pc=pc+1&0xFFFF end, -- LIr
    [0xe0]=function() stk[1][INC(1)] = ram[pc]; stk[1][INC(1)] = ram[pc+1&0xFFFF]; pc=pc+2&0xFFFF end, -- L2r
}
OPC(0x01, function() POx(a,d) end, function() PUx(a[1] + 1,d, r) end) -- INC
OPC(0x02, function() ptr[r]=ptr[r]-1-d&0xFF end, function()end) -- POP
OPC(0x03, function() GOT(x) ptr[r]=ptr[r]-1-d&0xFF end, function() PUT(x,r) end) -- NIP
OPC(0x04, function() GOT(x); GOT(y) end, function() PUT(x,r); PUT(y,r) end) -- SWP
OPC(0x05, function() GOT(x); GOT(y); GOT(z) end, function() PUT(y,r) PUT(x,r) PUT(z,r) end) -- ROT
OPC(0x06, function() GOT(x) end, function() PUT(x,r); PUT(x,r) end) -- DUP
OPC(0x07, function() GOT(x); GOT(y) end, function() PUT(y,r); PUT(x,r); PUT(y,r) end) -- OVR
OPC(0x08, function() POx(a,d); POx(b,d) end, function() PUx(b[1] == a[1] and 1 or 0,0,r) end) -- EQU
OPC(0x09, function() POx(a,d); POx(b,d) end, function() PUx(b[1] ~= a[1] and 1 or 0,0,r) end) -- NEQ
OPC(0x0a, function() POx(a,d); POx(b,d) end, function() PUx(b[1] > a[1] and 1 or 0,0,r) end) -- GTH
OPC(0x0b, function() POx(a,d); POx(b,d) end, function() PUx(b[1] < a[1] and 1 or 0,0,r) end) -- LTH
OPC(0x0c, function() POx(a,d) end, function() MOV() end) -- JMP
OPC(0x0d, function() POx(a,d); POx(b,0) end, function() if b[1] > 0 then MOV() end end) -- JCN
OPC(0x0e, function() POx(a,d) end, function() PUx(pc,1,r~1); MOV() end) -- JSR
OPC(0x0f, function() GOT(x) end, function() PUT(x,r~1) end) -- STH
OPC(0x10, function() POx(a,0) end, function() PEK(a[1], x, 0xff) end) -- LDZ
OPC(0x11, function() POx(a,0); GOT(y) end, function() POK(a[1], y, 0xff) end) -- STZ
OPC(0x12, function() POx(a,0) end, function() PEK(pc + (a[1]~0x80)-0x80, x, 0xffff) end) -- LDR
OPC(0x13, function() POx(a,0); GOT(y) end, function() POK(pc + (a[1]~0x80)-0x80, y, 0xffff) end) -- STR
OPC(0x14, function() POx(a,1) end, function() PEK(a[1], x, 0xffff) end) -- LDA
OPC(0x15, function() POx(a,1); GOT(y) end, function() POK(a[1], y, 0xffff) end) -- STA
OPC(0x16, function() POx(a,0) end, function() DEI(a[1], x) end) -- DEI
OPC(0x17, function() POx(a,0); GOT(y) end, function() DEO(a[1], y) end) -- DEO
OPC(0x18, function() POx(a,d); POx(b,d) end, function() PUx(b[1] + a[1], d,r) end) -- ADD
OPC(0x19, function() POx(a,d); POx(b,d) end, function() PUx(b[1] - a[1], d,r) end) -- SUB
OPC(0x1a, function() POx(a,d); POx(b,d) end, function() PUx(b[1] * a[1], d,r) end) -- MUL
OPC(0x1b, function() POx(a,d); POx(b,d) end, function() if a[1] > 0 then a[1] = b[1] // a[1] end PUx(a[1], d,r) end) -- DIV
OPC(0x1c, function() POx(a,d); POx(b,d) end, function() PUx(b[1] & a[1], d,r) end) -- AND
OPC(0x1d, function() POx(a,d); POx(b,d) end, function() PUx(b[1] | a[1], d,r) end) -- ORA
OPC(0x1e, function() POx(a,d); POx(b,d) end, function() PUx(b[1] ~ a[1], d,r) end) -- EOR
OPC(0x1f, function() POx(a,0) POx(b,d) end, function() PUx(b[1] >> (a[1] & 0xf) << (a[1] >> 4), d,r) end) -- SFT

local function uxn_eval(start_pc)
    pc = start_pc
    start_pc = pc
    pc=pc+1&0xFFFF
    while not ops[ram[start_pc]]() do
        start_pc = pc
        pc=pc+1&0xFFFF
    end
end

local function console_input(c, type)
    dev[0x12] = c
    dev[0x17] = type
    if console_vector then uxn_eval(console_vector) end
end

local file = io.open(arg[1], "rb")
local rom = file:read("a")
file:close()
for i = 1, #rom do
    ram[i + 0xFF] = rom:byte(i, i)
end
uxn_eval(0x100)
if console_vector > 0 then
    while dev[0x0f] == 0 do
        local c = io.read(1);
        if c == nil then break end
        console_input(string.byte(c), 1);
    end
    console_input(0x0a, 4);
end
return dev[0x0f] & 0x7f;
