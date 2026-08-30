#!/usr/bin/env python3
"""
Un-deduplicate the archive: write device files with their commands inlined.

The archive stores each distinct command set once under codesets/ and gives every
device a small stub pointing at one, because 276,236 devices share only 54,118 sets.
This walks that indirection and writes self-contained files instead.

It is also the shortest description of the format there is — forty lines that read
every file type in the archive. Read it if you are writing a tool.

    python3 rehydrate.py --manufacturer Sony --out /tmp/sony
    python3 rehydrate.py --model-file my-devices.txt --out /tmp/mine
    python3 rehydrate.py --all --out /tmp/everything

--model-file takes one "Manufacturer<TAB>Model" (or "Manufacturer/Model") per line.
Run it from the archive root, or pass --archive.
"""
import argparse
import json
import os


def load(root, *parts):
    with open(os.path.join(root, *parts), encoding="utf-8") as f:
        return json.load(f)


def rehydrate(root, out, wanted=None, everything=False):
    """wanted: {manufacturer name: set of model names, or None for all of them}."""
    cache = {}
    n = 0
    for man in load(root, "index.json"):                     # [{"n","s","c"}, ...]
        if not everything and man["n"] not in wanted:
            continue
        models = wanted.get(man["n"]) if wanted else None
        for entry in load(root, "devices", man["s"], "index.json"):   # {"m","f","id"}
            if models and entry["m"] not in models:
                continue
            dev = load(root, "devices", man["s"], entry["f"])
            path = dev["codeset"]                            # relative to the root
            if path and path not in cache:
                cache[path] = load(root, path)["commands"]
            dev["commands"] = cache.get(path, [])
            del dev["codeset"]
            d = os.path.join(out, man["s"])
            os.makedirs(d, exist_ok=True)
            with open(os.path.join(d, entry["f"]), "w", encoding="utf-8") as f:
                json.dump(dev, f, indent=2, sort_keys=True, ensure_ascii=False)
                f.write("\n")
            n += 1
            if n % 5000 == 0:
                print("  %d devices" % n, flush=True)
    return n


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("--archive", default=".", help="archive root (default: here)")
    ap.add_argument("--out", required=True, help="directory to write into")
    ap.add_argument("--manufacturer", action="append", default=[],
                    help="rehydrate this manufacturer (repeatable)")
    ap.add_argument("--model-file",
                    help="file of 'Manufacturer<TAB>Model' lines to rehydrate")
    ap.add_argument("--all", action="store_true",
                    help="the WHOLE archive: ~5.8 GB across 276,236 files")
    args = ap.parse_args()

    wanted = {m: None for m in args.manufacturer}
    if args.model_file:
        with open(args.model_file, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                man, model = (line.split("\t", 1) if "\t" in line
                              else line.split("/", 1))
                man, model = man.strip(), model.strip()
                wanted.setdefault(man, set())
                if wanted[man] is not None:          # --manufacturer wins: all models
                    wanted[man].add(model)
    if not wanted and not args.all:
        ap.error("nothing selected: pass --manufacturer, --model-file, or --all "
                 "(--all writes ~5.8 GB across 276,236 files)")
    n = rehydrate(args.archive, args.out, wanted, args.all)
    print("wrote %d device files to %s" % (n, args.out))


if __name__ == "__main__":
    main()
