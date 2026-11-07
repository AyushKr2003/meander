# Third-party notices

## Serpantinum

Meander is a modified version of Serpantinum 2.4.2
(https://github.com/ilyamiro/serpantinum, commit `246061b`).

Copyright (C) 2026 Illia Miroshnichenko and the Serpantinum contributors.
Licensed under the GNU Affero General Public License version 3 or later.

Everything under `src/` started as Serpantinum's `src/`. The changes for Omarchy
are listed in [CHANGELOG.md](CHANGELOG.md) and [docs/parity.md](docs/parity.md);
new files are `src/quickshell/MeanderBar.qml`, `src/quickshell/omarchy/`,
`src/quickshell/singletons/system/OmarchyHost.qml`, `src/scripts/core/`,
`bin/meander-core`, `bin/meander-gamma`, `bin/meander-audio`, `bin/meander-setup`,
`keybinds.lua` and `meander.lua`.

Copyright (C) 2026 AyushKr2003 for those modifications, under the same license.

## Fonts

`src/assets/fonts/` keeps Serpantinum's bundled fonts that may be redistributed:
the Nerd Fonts patched families (MIT / SIL OFL 1.1, see
https://github.com/ryanoasis/nerd-fonts), JetBrains Mono, Fira Code, IBM Plex
Mono, Roboto, Google Sans Flex, Bitcount, Edu VIC WA NT Hand (SIL OFL 1.1 /
Apache 2.0) and Comic Mono (MIT).

Serpantinum also shipped SF Pro Display, SF Mono and TT Commons Pro. Their
licenses don't allow redistribution, so Meander leaves them out; install them
yourself and they show up in Settings > Theme > Font.

## Sounds and images

`src/assets/sounds/`, `src/assets/pushy.gif` and `src/assets/pushy2.gif` come from
Serpantinum unchanged. The Meander logo (`src/assets/logo.svg`) is new.
