# The Steam first pass — implementation plan

The den room pass is done: phases 1–5 shipped and every achievement has a badge. What's
left before Steam splits cleanly into work that needs the artist and work that doesn't,
and right now the artist is mid-revamp on the 1:1 fox.

**So this pass is scoped to everything that needs nothing from anybody.** That's not
arbitrary — half the sizing math in the game is keyed to the fox's current 5× bake
([desktop_fox.gd:73](../src/world/desktop_fox.gd#L73) hardcodes a 160px frame, and
`Den.FLOOR_Y` was *derived* from where the preview fox's feet land). Anything
fox-shaped done now gets done twice.

What's independent of the fox, and all of it real: **the build has no identity, one
achievement is impossible to earn, and the pck ships 1.5MB of scratch art.** About a
day's work, and it unblocks handing a build to anyone outside this machine.

### What this pass deliberately doesn't touch

| | Why it waits |
|---|---|
| Fox sounds | The biggest audio gap in the game, and entirely fox-shaped |
| New den finds | Artist, who is on the fox |
| GodotSteam wiring | Wants an appid and Steamworks setup, and §2 must land first |
| Onboarding | The highest-risk item left, and it's design work — its own plan |

---

## 1. The build has no identity

Not a guess — I exported a release build headlessly and inspected the binary:

| Field | In the shipped exe |
|---|---|
| Filename | **MyGame.exe** |
| ProductName | *(empty)* |
| FileDescription | *(empty)* |
| CompanyName | *(empty)* |
| FileVersion | 1.0.0.0 *(the template's default, not yours)* |
| LegalCopyright | *(empty)* |
| Icon | **the Godot robot**, 32×32 |

The export exits 0 and prints no warning, which is why this has survived. Windows
SmartScreen and AV heuristics also treat unsigned-and-unnamed worse than
unsigned-but-named, so this isn't only cosmetic.

### The fields

All in [export_presets.cfg](../export_presets.cfg):

| Key | Set to |
|---|---|
| `export_path` | `build/FocusFox.exe` |
| `application/product_name` | `Focus Fox` |
| `application/file_description` | `Focus Fox` |
| `application/company_name` | see open question 2 |
| `application/file_version` | four-part, e.g. `0.9.0.0` — Windows requires four |
| `application/product_version` | same |
| `application/copyright` | `© 2026 <name>` |
| `application/icon` | `res://icon.ico` |

`application/modify_resources=true` is already set. That's the switch that permits any
of this to be written into the PE header, so it's one less thing to discover.

### The trap: find out whether Godot writes it at all

Godot has historically needed an external **`rcedit`** binary to write the Windows icon
and version block, configured at *Editor Settings → Export → Windows → rcedit*. That
setting is **absent from `editor_settings-4.6.tres`** — i.e. sitting at its empty
default. 4.6 may well write PE resources natively now; the export produced no warning.
But every field was empty, so there was nothing to write — **the clean export proved
nothing.**

So the first action of this pass is not "fill in the metadata", it's **fill it in and
confirm it landed**:

```powershell
(Get-Item build\FocusFox.exe).VersionInfo |
  Select-Object ProductName,FileDescription,FileVersion,CompanyName
```

Still blank → download rcedit and set the editor setting. Five minutes either way, but
do it before stacking anything else on top, because a silent no-op here invalidates
everything else in this section.

### The icon

The largest fox head in the project is **32×32**: `assets/static/tray icon/headshot.png`,
the tray icon ([system_tray.gd:13](../src/world/system_tray.gd#L13)). Nothing bigger
exists — `fox_overlay_clean.png` is also 32, the mockup faces are 48, and the sprite
sheet is 448×224 of 32px frames.

Windows wants 16/32/48/64/128/256 in one `.ico`. From a 32px source, **32/64/128/256 are
exact integer multiples** (1/2/4/8×) and nearest-neighbour upscale perfectly — the right
answer for pixel art, and it'll read as deliberate. The other two don't divide:

- **16** — downscaling a 32px pixel-art head loses features. Omit it; Windows
  downsamples the 32 acceptably where it needs a 16.
- **48** — 1.5×. Either nearest-neighbour and accept mild artefacts, or centre the 32 on
  a 48 canvas (pixel-perfect, but reads visibly smaller in Explorer's medium view).

**Recommendation:** generate 32/64/128/256 into `icon.ico` now, and **ask the artist for
a 256×256 icon as part of the 1:1 fox work.** They're drawing a new fox regardless, and
this is the one asset where the 32px source is a genuine ceiling rather than a style.
Write it as `tools/make_icon.py` next to `make_shadow.py` so it regenerates when the new
art lands. Python 3.14 and PIL 12.1.1 are on the machine, and PIL writes multi-size
`.ico` natively.

Separately: `config/icon="res://icon.svg"` at [project.godot:19](../project.godot#L19)
is the Godot robot too. Point it at a res:// png and delete `icon.svg` + its `.import`.

---

## 2. Interior Foxcorator can't be earned

[achievement_store.gd:69](../src/world/achievement_store.gd#L69) wants 10 den items.
[den_catalog.gd](../src/world/den_catalog.gd) has **nine**. And the Den journal page
renders `"%d of %d found"` ([journal_book.gd:1495](../src/world/journal_book.gd#L1495)),
so a completed den shows **"9 of 9 found" directly opposite a locked achievement
demanding ten**.

**Why it's in the first pass:** the Steamworks achievement list doesn't exist yet, so
today this is a one-line edit. Once it exists, changing a live achievement's name or
description is visible to everyone who already earned it.

Landing find #10 also fixes it, but that's the artist. So: retune, reword to
*"Bring every find home."* The badge art already exists
(`assets/achievements/Interior Foxcorator/`), so nothing is orphaned.

### The decision hiding inside it

`on_item_unlocked(total)` at
[achievement_store.gd:319-325](../src/world/achievement_store.gd#L319-L325) compares
against a literal threshold. If the wording becomes "every find" but the threshold stays
a hardcoded 9, then **the day find #10 ships, "Bring every find home" fires at 9 of 10** —
the same class of bug, pointing the other way.

**Recommend catalog-relative:** derive the threshold from `DenCatalog.size()` so it can
never drift again. It makes the achievement genuinely completionist, which is the honest
reading of the label.

One caveat to accept: Steam achievement descriptions are static text on Valve's side, so
the Steam copy stays generic ("Bring every find home") even if the in-game line counts.
That's fine — it's the wording that survives every future find.

### While in this file

`_steam_init()` is defined at
[achievement_store.gd:416](../src/world/achievement_store.gd#L416) and **never called** —
step 4 of its own four-step wiring comment. Harmless today (the body is a stub), but it's
the one step that isn't self-evident when you return to this cold, and the other three
are all "fill in a body". Add the guarded call now so the GodotSteam pass is purely
body-filling.

---

## 3. The pck ships scratch art

`build/den-room2.png` and `build/den-room3.png` are untracked working files in a
gitignored folder. Godot imported them anyway, and **both are inside the exported pck** —
verified by string-searching the pck I built. ~1.5MB of dead weight in every build.

The mechanism: `export_filter="all_resources"` takes everything carrying a `.import`, and
`.gitignore` has no bearing on that whatsoever.

The deeper version is worth naming, because it'll bite again: **`.godot/` and `*.import`
are both gitignored, so what lands in a build depends on which stray PNGs happen to be
sitting in your working tree.** A fresh clone and this machine produce different pcks.
den-room2/3 is that bug already having happened, silently, for however long.

Fixes, least to most durable:

1. `exclude_filter="build/*"` on the preset. One line, stops this class of leak now.
2. Move reference art out of the project tree — it's reference, not a resource.
3. An export sanity check. The string-search I ran is three lines of PowerShell, and it
   turns "no scratch art in the build" into something testable rather than something you
   remember.

Also here: `binary_format/embed_pck=false`. For Steam, embedding means one file instead
of two and one fewer thing for a partial update to desync. **Recommend flipping it**, but
re-verify size and that the built exe actually launches — embedding changes how the
binary is assembled, and it's the kind of change that works everywhere except the one
machine that matters.

---

## 4. Two audio wins that need nobody

Deliberately the *only* audio in this pass. The rest of the sound work — and the real gap
is that [desktop_fox.gd](../src/world/desktop_fox.gd) has zero `Audio.play` calls, so the
pet on your desktop is silent — is fox-shaped and waits for the revamp.

- **`unlock.mp3` → ogg.** The odd file out among nine oggs
  ([audio.gd:16](../src/world/audio.gd#L16)), and it's the achievement sting — the most
  emotionally loaded sound in the game, on the one format with gapless quirks in Godot.
  ffmpeg 8.1 is on the machine:
  `ffmpeg -i unlock.mp3 -c:a libvorbis -q:a 6 unlock.ogg`. Repoint the preload, delete
  the mp3 and its `.import`.
- **Pitch jitter.** `play()` already takes a pitch
  ([audio.gd:45](../src/world/audio.gd#L45)) and callers pass 1.12–1.25 for journal
  pages. Add a small default jitter (±4%) *inside* `play()` so repeated
  `click`/`grab`/`drop` stop sounding mechanical. Jitter around whatever pitch was
  passed rather than replacing it, so the journal's deliberate 1.25 survives. Three lines.

---

## Recommended order

| | | Est. |
|---|---|---|
| 1 | Fill the metadata fields, export, **inspect the exe** — gates all of §1 | 30 min |
| 2 | `tools/make_icon.py` → `icon.ico`, repoint `config/icon`, delete `icon.svg` | 1 hour |
| 3 | Rest of the preset: export_path, exclude_filter, embed_pck, versions | 30 min |
| 4 | Interior Foxcorator retune + the `_steam_init()` call | 30 min |
| 5 | `unlock.ogg` + pitch jitter | 30 min |
| 6 | Full export; launch the built exe; confirm name and icon in the taskbar and Task Manager; confirm no `build/` files in the pck | 1 hour |

**About a day.** Step 1 first and alone, for the same reason 2a went first in the den
plan — it de-risks everything after it by proving the mechanism works before anything
depends on it.

Then **onboarding**, which is the highest-risk item left and deserves its own plan.
Worth writing down now while it's fresh: there is no first-run flow at all, and a new
player meets a pet that lives in a separate always-on-top window, a den hidden behind a
drawer pull-tab, and a launcher that **parks itself off-screen 1.5s into their first
session** — which will read as a crash to a real fraction of players.

---

## Open questions

1. **Version number** — `0.9.0.0` through Steam review, or `1.0.0.0` from the first
   upload? Nothing technical rides on it, but Steam surfaces the build version.
2. **Company name** — your own name or a studio name? It goes in the exe metadata and
   should match the Steamworks publisher, so it's easier to settle before the appid.
3. **Interior Foxcorator** — fixed 9, or catalog-relative? Recommending catalog-relative
   (§2).
4. **Does `build/` want to keep being both output and scratch?** Splitting it (`build/`
   for exports, `ref/` for working art) makes the exclude_filter unnecessary and the
   class of bug in §3 structurally impossible.
</content>
