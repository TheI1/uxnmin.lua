# uxnmin.lua

A direct port of the [uxnmin](https://git.sr.ht/~rabbits/uxnmin) [Uxn](https://100r.co/site/uxn.html) emulator by Devine Lu Linvega in C for Lua.

The uxnmin-compat.lua version is made to work on other/older Lua versions, e.g. [LuaJIT](https://luajit.org/). It avoids using the bitwize and floor division operations of the latest Lua version, making use of libraries instead.
