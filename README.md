# Divinum Officium for Omarchy

The traditional Roman Breviary in your bar. The widget shows the canonical hour
being prayed now — Matutinum through Completorium — with the liturgical colour
of the day beside it. Clicking it opens the office itself: the day's title and
rank, the commemoration, and the full text in one or two languages, with the
hours, the days, and the rubrical edition all one keypress away.

The office text comes from a **Divinum Officium** server
([DivinumOfficium/divinum-officium](https://github.com/DivinumOfficium/divinum-officium)),
the same data and Perl engine that power divinumofficium.com.

## Install

```bash
omarchy plugin add https://github.com/ofrades/omarchy-divinum-officium
omarchy plugin enable io.github.ofrades.divinum-officium
```

Installing by hand works too: drop the folder into
`~/.config/omarchy/plugins/<id>/`, run `omarchy-shell shell rescanPlugins`, then
`omarchy plugin enable <id>`. The widget lands at the right end of the bar; move
it with `omarchy bar move io.github.ofrades.divinum-officium --section center`
if you would rather read the hour next to the clock.

Only `python3` is needed at runtime, and it is already on an Omarchy system.

## Where the text comes from

The official site blocks automated access to its office CGI: `robots.txt`
disallows `/cgi-bin/`, and Cloudflare answers dated requests with a 403. This
plugin therefore never talks to it. The default source is the Hungarian mirror,
`https://divinumofficium.hu`, which runs the same software and allows crawling
with a ten second delay — the helper identifies itself, spaces its requests
according to that delay, and caches every office it fetches.

If you would rather not depend on a mirror, run the official container and point
the plugin at it. That also makes the office work offline and removes the
Crawl-delay wait:

```yaml
# docker-compose.yml
services:
  web:
    image: ghcr.io/divinumofficium/divinum-officium:master
    ports:
      - "8080:8080"
    restart: unless-stopped
```

```bash
docker compose up -d
```

then set **Divinum Officium server** to `http://127.0.0.1:8080` in the widget's
settings. The image is around 460 MB compressed; it serves the whole site, so
any edition and language is available.

## Settings

Settings live in the widget's entry in `~/.config/omarchy/shell.json` and are
also editable from **Setup › Plugins**. The panel's dropdowns write the same
keys, so a choice made while reading survives a restart.

| Setting | Default | What it does |
| --- | --- | --- |
| `sourceUrl` | `https://divinumofficium.hu` | Which Divinum Officium server to read. |
| `version` | `Rubrics 1960 - 1960` | Rubrical edition, from Tridentine 1570 to Ordo Praedicatorum 1962. |
| `language` | `Latin` | The left column, and the only column when the right one is off. |
| `language2` | `English` | The right column. `None` (or the same language twice) gives a single-column office. |
| `hourSchedule` | `00:00,06:00,07:30,09:00,12:00,15:00,18:00,21:00` | Eight times, one per hour from Matins to Compline, deciding which hour the bar calls current. |
| `refreshIntervalSec` | `900` | How often the office is re-checked while the shell runs. |
| `cacheTtlMinutes` | `360` | How long a fetched office is reused before it is fetched again. |
| `hideVerseNumbers` | `Off` | Hide the small verse numbers psalms are pointed by. The mediant asterisks stay. |
| `showColourDot` | `On` | Show the liturgical colour next to the hour in the bar. |

## Keys

| Key | Action |
| --- | --- |
| click | Open / close the office |
| right click | Refetch the current hour |
| middle click | Jump back to the hour the clock is on |
| `j` / `k` | Next / previous hour (stepping past Compline moves to the next day) |
| `h` / `l` | Previous / next day |
| `1`–`8` | Pick an hour directly |
| `t` | Today, following the clock again |
| `r` | Refetch |
| `Return` | Advance to the next hour |
| `c` / `e` | Collapse / expand every section |
| `Esc` | Close |

The same actions are on IPC, for keybindings and scripts:

```bash
omarchy-shell io.github.ofrades.divinum-officium toggle
omarchy-shell io.github.ofrades.divinum-officium next
omarchy-shell io.github.ofrades.divinum-officium previousDay
omarchy-shell io.github.ofrades.divinum-officium today
```

`open`, `close`, `show`, `hide`, `refresh`, `next`, `previous`, `nextDay`,
`previousDay`, and `today` are the full set.

To reach the reader from anywhere, bind it in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + O", "Divine Office", "omarchy-shell io.github.ofrades.divinum-officium toggle")
```

## How it works

- `BarWidget.qml` owns the bar slot and loads `Panel.qml`. It reads the hour,
  the day title, and the colour off the panel, so the bar stays honest without
  asking for anything itself.
- `Panel.qml` is the reader: hours, days, rubrics, languages, and the office
  text. It fetches through a debounced `Process` so clicking through the hours
  does not put a request on the wire for every click.
- `Model.js` holds the pure logic: the hour schedule, the liturgical colour
  table, date arithmetic, and the RichText rendering of the office lines.
- `divinum_officium.py` does the network side. It asks for one hour, parses the
  server's HTML table into sections with marked-up lines, and caches the result
  under `~/.cache/omarchy/divinum-officium/`. On a failed fetch it serves the
  last saved office and says so in the panel.

The colour names are the server's own, which are not what they sound like: it
paints a white feast in `black` (it omits the colour attribute entirely) and a
requiem in `grey`. The plugin shows those as White and Black, which is what the
vestments are.

```bash
python3 divinum_officium.py cache-path     # where offices are cached
python3 divinum_officium.py clear-cache    # forget every saved office
```

## Tests

```bash
./tests/run
```

Parses a fixture office page, exercises `Model.js` under node, and validates the
manifest. No network access.

## Troubleshooting

- **The panel is empty and the bar says "Officium".** The first fetch failed:
  the panel prints why above the text. `r` refetches, and a saved office keeps
  being served with a warning if the server is down.
- **A change to a plugin file did not appear.** The shell reloads plugin code on
  save, but a bar widget that is already in the bar can keep its old instance.
  Restart the shell with `omarchy restart shell`.
- **Reading is slow or the panel waits.** Each fetch waits out the mirror's
  `Crawl-delay: 10` before it goes out, so a cold office can take ten seconds.
  Everything after that is cached for `cacheTtlMinutes`.

## Credits

The office text, its rubrics, and the liturgical engine belong to the
[Divinum Officium Project](https://github.com/DivinumOfficium/divinum-officium),
released under the MIT licence. This plugin is an independent reader for it and
is not affiliated with the project.

MIT licensed — see [LICENSE](LICENSE).
