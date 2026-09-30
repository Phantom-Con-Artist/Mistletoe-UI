# Shared Mistletoe QML

`Shard.qml`, `Gem.qml` and `Overlay.qml` are used by several widgets. Plasma
widget packages can't import from one another and must stay self-contained,
so these files are the single source and `scripts/sync-shared.py` copies them
into each package that uses them.

Edit them here, then run `python3 scripts/sync-shared.py` (install.sh does
too). `python3 scripts/sync-shared.py --check` fails if a copy has drifted.
