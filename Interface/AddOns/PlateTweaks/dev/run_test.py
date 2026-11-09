import lupa, io, os, sys

ADDON = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HERE = os.path.dirname(os.path.abspath(__file__))

# Lua 5.4 rejects "\B" in strings; WoW's 5.1 does not. Only this harness cares,
# so the paths are neutralised in the copy that is loaded here.
def read(path):
    src = io.open(path, encoding="utf-8").read()
    return src.replace(chr(92) + chr(92), "/").replace(chr(92), "/")


def run(harness_file, sources):
    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    loader = L.eval("""
    function(name, src)
      local f, e = load(src, name)
      if not f then error(e, 0) end
      return f
    end
    """)
    g = L.globals()
    g.PT_SOURCES = L.table()
    for rel in sources:
        g.PT_SOURCES[rel] = read(os.path.join(ADDON, rel))

    harness = read(os.path.join(HERE, harness_file))
    harness = harness.replace(
        'local chunk = assert(loadfile(dir .. "/" .. path))',
        'local chunk = assert(load(PT_SOURCES[path], path))')
    harness = harness.replace(
        'local chunk = assert(loadfile(dir .. "/Learned.lua"))',
        'local chunk = assert(load(PT_SOURCES["Learned.lua"], "Learned.lua"))')
    harness = harness.replace(
        'local chunk = assert(loadfile(dir .. "/Migrate.lua"))',
        'local chunk = assert(load(PT_SOURCES["Migrate.lua"], "Migrate.lua"))')
    harness = harness.replace(
        'local chunk = assert(loadfile(dir .. "/Share.lua"))',
        'local chunk = assert(load(PT_SOURCES["Share.lua"], "Share.lua"))')
    harness = harness.replace(
        'local chunk = assert(loadfile(dir .. "/Libs/Flex/Flex.lua"))',
        'local chunk = assert(load(PT_SOURCES["Libs/Flex/Flex.lua"], "Flex.lua"))')
    # test_alignment.lua reads the spec straight out of Options.lua, so give it
    # the file rather than a second copy of those numbers.
    harness = harness.replace(
        'local source = assert(io.open(dir .. "/Options.lua")):read("a")',
        'local source = PT_SOURCES["Options.lua"]')

    print("==== " + harness_file)
    return loader(harness_file, harness)(ADDON) or 0


failures = 0
failures += run("test_engine.lua", ["Threat.lua", "Tints.lua"])
failures += run("test_flex_layout.lua", ["Libs/Flex/Flex.lua"])
failures += run("test_alignment.lua", ["Libs/Flex/Flex.lua", "Options.lua"])
failures += run("test_migrate.lua", ["Migrate.lua"])
failures += run("test_learned.lua", ["Learned.lua"])
failures += run("test_share.lua", ["Share.lua"])
# Every file the TOC loads, compiled.
#
# A syntax error in Options.lua does not fail any suite here -- the alignment
# suite reads that file as TEXT -- so a broken chunk reached the game as
# "attempt to call a nil value" on whatever the file was supposed to define.
# One load() per file catches it before a reload does.
#
# The blunt read() above turns every backslash into a slash, which is fine for
# a texture path and fatal for an escaped quote. This one only rewrites the
# escapes Lua 5.4 rejects and 5.1 accepts, and leaves real ones alone.
LUA_ESCAPES = set('ntr' + chr(34) + chr(39) + chr(92) + 'abvfz0123456789x')


def portable(src):
    out, i, bs = [], 0, chr(92)
    while i < len(src):
        c = src[i]
        if c == bs and i + 1 < len(src):
            nxt = src[i + 1]
            if nxt == bs:
                out.append(bs + bs)
                i += 2
                continue
            if nxt in LUA_ESCAPES:
                out.append(c)
                out.append(nxt)
                i += 2
                continue
            out.append("/")
            i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


def compile_all():
    toc = io.open(os.path.join(ADDON, "PlateTweaks.toc"), encoding="utf-8").read()
    files = [line.strip() for line in toc.splitlines()
             if line.strip().lower().endswith(".lua") and not line.startswith("#")
             # Vendored libraries are not ours to hold to this.
             and not line.strip().lower().startswith("libs")]
    L = lupa.LuaRuntime()
    loader = L.eval(
        "function(s, n) local f, e = load(s, n) if not f then error(e, 0) end return true end")
    bad = 0
    print("==== compile")
    for rel in files:
        path = os.path.join(ADDON, rel.replace(chr(92), os.sep))
        if not os.path.exists(path):
            print("FAIL missing " + rel)
            bad += 1
            continue
        try:
            loader(portable(io.open(path, encoding="utf-8").read()), rel)
        except Exception as exc:
            print("FAIL " + rel + ": " + str(exc).splitlines()[0])
            bad += 1
    if bad == 0:
        print("ok   %d files compile" % len(files))
    return bad


failures += compile_all()
sys.exit(0 if failures == 0 else 1)
