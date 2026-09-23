# Divinum Officium for Omarchy

The traditional Roman liturgy in your bar. The widget shows the canonical hour
being prayed now — Matutinum through Completorium — with the liturgical colour
of the day beside it. Clicking it opens the day's **Office**: the title and rank,
the commemoration, and the full text in one or two languages, with the hours,
the days, and the rubrical edition all one keypress away. The same panel reads
the day's **Mass** too — propers, or the propers set inside the Ordinary, and
any votive Mass from the missal.

The texts come from a **Divinum Officium** server
([DivinumOfficium/divinum-officium](https://github.com/DivinumOfficium/divinum-officium)),
the same data and Perl engine that power divinumofficium.com — the breviary's
`Pofficium.pl` for the hours and the missal's `missa.pl` for the Mass.

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

## The Mass

The panel opens on the Office. Switch it to the Mass with the **Officium /
Missa** pills, the `m` key, or:

```bash
omarchy-shell io.github.ofrades.divinum-officium mass
```

The Mass view keeps the same day navigation, rubrics, and languages, and adds:

- **Propers / Full Mass** — Propers is the day's own texts (Introit, Collect,
  Epistle, Gospel, Offertory, Secret, Communion, Postcommunion); Full Mass sets
  them inside the Ordinary, which is what the website shows by default.
- **Mass** — the Mass of the day, or a votive and communal Mass: Requiem,
  Beatae Mariae Virginis, a Martyr Pontiff, a Confessor, a Virgin Martyr,
  Dedication, St Joseph, the Passion, for the Pope, for the spread of the faith.

The bar keeps showing the hour either way: the Mass has no hour of its own.

## Settings

Settings live in the widget's entry in `~/.config/omarchy/shell.json` and are
also editable from **Setup › Plugins**. The panel's pills and dropdowns write the
same keys, so a choice made while reading survives a restart.

| Setting | Default | What it does |
| --- | --- | --- |
| `sourceUrl` | `https://divinumofficium.hu` | Which Divinum Officium server to read. |
| `rite` | `Officium` | Which book the panel opens on. |
| `version` | `Rubrics 1960 - 1960` | Rubrical edition, from Tridentine 1570 to Ordo Praedicatorum 1962. |
| `language` | `Latin` | The left column, and the only column when the right one is off. |
| `language2` | `English` | The right column. `None` (or the same language twice) gives a single-column text. |
| `massForm` | `Propers` | Propers alone, or the propers inside the Ordinary of the Mass. |
| `massVotive` | `Hodie` | The Mass of the day, or a votive code from the missal (see the panel's list). |
| `hourSchedule` | `00:00,06:00,07:30,09:00,12:00,15:00,18:00,21:00` | Eight times, one per hour from Matins to Compline, deciding which hour the bar calls current. |
| `refreshIntervalSec` | `900` | How often the text is re-checked while the shell runs. |
| `cacheTtlMinutes` | `360` | How long a fetched text is reused before it is fetched again. |
| `hideVerseNumbers` | `Off` | Hide the small verse numbers psalms are pointed by. The mediant asterisks stay. |
| `showColourDot` | `On` | Show the liturgical colour next to the hour in the bar. |

## Keys

| Key | Action |
| --- | --- |
| click | Open / close the reader |
| right click | Refetch the current hour |
| middle click | Jump back to the hour the clock is on |
| `o` / `m` | Read the Office / the Mass |
| `j` / `k` | Next / previous hour (stepping past Compline moves to the next day) |
| `h` / `l` | Previous / next day |
| `1`–`8` | Pick an hour directly (Office) |
| `t` | Today, following the clock again |
| `r` | Refetch |
| `Return` | Advance to the next hour (Office) |
| `c` / `e` | Collapse / expand every section |
| `Esc` | Close |

The same actions are on IPC, for keybindings and scripts:

```bash
omarchy-shell io.github.ofrades.divinum-officium toggle
omarchy-shell io.github.ofrades.divinum-officium next
omarchy-shell io.github.ofrades.divinum-officium previousDay
omarchy-shell io.github.ofrades.divinum-officium today
omarchy-shell io.github.ofrades.divinum-officium mass          # the day's Mass
omarchy-shell io.github.ofrades.divinum-officium votive C9     # a Requiem
omarchy-shell io.github.ofrades.divinum-officium office        # back to the hours
```

`open`, `close`, `show`, `hide`, `refresh`, `next`, `previous`, `nextDay`,
`previousDay`, `today`, `rite`, `mass`, `office`, and `votive` are the full set.

To reach the reader from anywhere, bind it in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + O", "Divine Office", "omarchy-shell io.github.ofrades.divinum-officium toggle")
o.bind("SUPER + ALT + M", "Divine Mass", "omarchy-shell io.github.ofrades.divinum-officium mass")
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
- `divinum_officium.py` does the network side. It asks for one hour or one Mass,
  parses the server's HTML table into sections with marked-up lines, and caches
  the result under `~/.cache/omarchy/divinum-officium/`. On a failed fetch it
  serves the last saved text and says so in the panel.

The colour names are the server's own, which are not what they sound like: it
paints a white feast in `black` (it omits the colour attribute entirely) and a
requiem in `grey`. The plugin shows those as White and Black, which is what the
vestments are.

```bash
python3 divinum_officium.py cache-path     # where offices are cached
python3 divinum_officium.py clear-cache    # forget every saved office
```

## Generating a dataset

The reader asks a server for one hour at a time. If you would rather own the
text — no mirror, no crawl delay, no surprise when a volunteer site moves —
`tools/generate_slice.py` walks the Divinum Officium engine over a date range
and writes the same JSON the reader parses, one file per office or Mass:

```
dist/api/index.json
dist/api/office/rubrics-1960-1960/2026/09-23/prima-latin-portugues.json
dist/api/mass/rubrics-1960-1960/2026/09-23/hodie-full-latin-portugues.json
```

It reads the engine in place, so a checkout plus Perl modules is all it needs:

```bash
# Arch: everything is packaged
sudo pacman -S --needed perl-cgi perl-date-calc perl-algorithm-diff perl-uri \
  perl-cgi-session perl-cpanel-json-xs perl-timedate

git clone --depth 1 https://github.com/DivinumOfficium/divinum-officium ~/divinum-officium

python3 tools/generate_slice.py \
  --engine local --repo ~/divinum-officium \
  --from 2026-01-01 --to 2026-12-31 \
  --version "Rubrics 1960 - 1960" --lang1 Latin --lang2 Portugues \
  --out dist/api --jobs 8
```

A running server works too — `--engine http --base-url http://127.0.0.1:8080` —
which is the better mode when the engine lives in a container.

Measured on a desktop: a month of everything (eight hours + the Mass each day,
270 payloads) takes 5.5 seconds and 9 MB; a year is about a minute and 110 MB.
Re-running skips finished files, so an interrupted slice resumes; `--force`
regenerates. `--rites office` or `--hours Prima,Vesperae` narrow the slice, and
`--propers` takes the Mass without the Ordinary.

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

The texts, their rubrics, and the liturgical engine belong to the
[Divinum Officium Project](https://github.com/DivinumOfficium/divinum-officium),
released under the MIT licence. This plugin is an independent reader for it and
is not affiliated with the project.

MIT licensed — see [LICENSE](LICENSE).
