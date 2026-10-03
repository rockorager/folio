# Folio

A native Linux prose editor built with [Ourokit](https://github.com/rockorager/ourokit).
Folio is a working name. This is an early, single-document prototype, not a full Vim implementation.

## Run

Build Ourokit with Zig 0.16.0 and its documented native dependencies:

```sh
# In the adjacent ourokit checkout:
zig build -Dvulkan=false -Doptimize=ReleaseFast
# Back in this directory, in a Wayland desktop session:
./run-desktop.sh
```

Requires Ourokit's modal-editing/caret-shape support (`text_entry`, `caret_shape`,
and logical-line editing commands), plus native multi-stroke binding recipes,
Vim word motions/objects, whole-line selection commands, and the unnamed
characterwise/linewise register. Older Ourokit
binaries cannot load these bindings.
The launcher and Python checks default to
`../ourokit` and accept `OUROKIT_DIR` to select another compatible checkout.
No native plugin is required. Open/Save As use the desktop's
XDG file chooser portal; install your desktop's portal backend if needed.

Folio follows the desktop's light/dark preference from the XDG Settings portal
(`org.freedesktop.appearance` `color-scheme`) and switches live without
remounting the editor or losing undo history. With no portal or no preference
it stays light. There is no in-app theme toggle.

`./run-desktop.sh --dev` enables explicit source reload. Save your draft before
reloading: Lua document state resets with the source generation. Reload does not
upgrade the native toolkit binary; that requires restarting the application.

## Keyboard

The app starts in **Normal** with a block cursor and unbound typing suppressed.
`i` enters **Insert** with a beam cursor; `Esc` returns to Normal without remounting
the editor or clearing undo history. All modes use the same rust cursor color;
**Visual** keeps a translucent block at the active selection end, over the beige
selection highlight. Empty-line and end-of-line blocks use the font's `0` width.
Double-click selection shows the block before mouse release. There is no Replace mode, so no
underline mode is shown.
Carets are steady in all modes. The writing surface has no placeholder,
keyboard hints, word count, or Open/Save buttons.

| Key | Action |
| --- | --- |
| `h j k l` | Left, visual line down/up, right |
| `w`, `e`, `b` | Next word start, word's last grapheme, previous word start |
| `0 $` | Start/end of the hard logical line |
| `gg`, `G`, `Ctrl+Home` | Start/end/start of document |
| `{`, `}` | Previous/next paragraph boundary |
| `a`, `A`, `I` | Insert after one grapheme, at hard line end, at hard line start |
| `o O` | Open an empty hard line below/above and enter Insert |
| `x X` | Delete the current/previous grapheme without crossing a hard newline; holding repeats |
| `dd`, `cc` / `S`, `yy` | Delete/change/yank the current hard line |
| `D`, `C` | Delete/change through the hard line end |
| `dw de db`, `cw ce cb`, `yw ye yb` | Delete/change/yank by word motion |
| `diw ciw yiw`, `daw caw yaw` | Delete/change/yank a word, or a word with adjacent spaces |
| `dip cip yip`, `dap cap yap` | Delete/change/yank a paragraph, or a paragraph with blank separator lines |
| `u`, `Ctrl+R` in Normal | Undo/redo |
| `p P` in Normal | Put the unnamed register after/before the character, or below/above the hard line |
| `v` | Enter Visual selection; `v` or `Esc` returns to Normal |
| `V` | Enter Visual-line; `V` or `Esc` returns to Normal |
| `j k`, `gg G`, `{ }` in Visual-line | Extend/shrink whole hard lines, independent of wrapping |
| `h l`, `w b e`, `0 $` in Visual-line | Move the active cursor while keeping whole lines selected |
| `o` in either Visual mode | Swap the active cursor and anchor |
| `v` / `V` between Visual modes | Convert the selection without losing its endpoints |
| Motions in Visual | Extend or shrink the native selection |
| `iw aw`, `ip ap` in Visual | Select an inner/around word or paragraph (`viw`, `vap`, etc.) |
| `y` in either Visual mode | Yank selection and return to Normal |
| `d` / `x` in Visual | Delete selection and return to Normal |
| `c` in Visual | Delete selection and enter Insert |
| `d` / `x`, `c` in Visual-line | Remove selected lines, or replace them with one blank line and enter Insert |
| `:` in Normal/Visual | Open the command palette |
| `Ctrl+S`, `Ctrl+Shift+S` | Save, Save As |
| `Ctrl+O`, `Ctrl+N`, `Ctrl+Q` | Open, New, Quit |
| `Ctrl+Z`, `Ctrl+Shift+Z` in Insert | Native undo/redo |
| `Ctrl++` / `Ctrl+=`, `Ctrl+-` | Increase/decrease the writing font by 2 pixels (12–48) |
| `Ctrl+0` | Reset the writing font to 23 pixels |

Font size is a session-only view setting; it does not change the document or
the size of the surrounding UI. The writing surface requests Fontconfig's
`serif` family; the UI and command input request `sans-serif`.

The command palette filters by name or Vim-style alias: `w` (Save), `e` (Open),
`saveas`, `enew` (New document), `wq` (Save and quit), and `q` (Quit). Up/Down select, Enter runs,
and Escape closes without changing the draft or selection. `:` is ordinary text
in Insert. Commands use the existing file chooser and unsaved-change protection;
this is not an Ex interpreter and does not accept paths or `!` force variants.
Names such as “New document” remain searchable, but there are no Vim splits
(`:new`), and `:e` opens a chooser rather than reloading the current file.
`:x` is not an alias: unlike `:wq`, Vim's `:x` only writes a changed file.

Insert supports normal typing, selection, clipboard, wrapping, scrolling, and IME
through Ourokit's editor. Long unbroken runs wrap between graphemes without
inserting newlines into the document. Normal/Visual reject unbound typing and IME entry while
explicit native edit bindings remain available. Changes (`cw`, `ciw`, `cc`,
paragraph changes, and Visual `c`) and subsequent typing form one undo step.
Moving the cursor, leaving Insert, or changing focus ends that group. `o`/`O`
still use separate undo steps for line insertion and typing, and do not auto-indent. Multi-stroke commands
have no timeout; Escape cancels a pending prefix. An unmatched key cancels the
prefix and is interpreted normally. Changing focus, clicking, or rebuilding
the editor's bindings also cancels a prefix.

Visual-line retains the cursor separately from the highlighted line bounds;
entering or leaving it does not jump to the next line. Its vertical motions
retain a grapheme column across shorter hard lines, rather than Neovim's
terminal-cell column (tabs and wide characters can therefore differ).

`w` moves to the next word's start; `e` lands on the final grapheme, and `de`/`ce`
include it. `dw`/`yw` include trailing spaces but stop before the current hard
newline. `cw` on a word preserves the following spaces, including when the caret
is already on the word's final character. Word motions and `iw`/`aw` group Unicode
letters/numbers/underscore separately from punctuation, with spaces, tabs, and LF
as separators. They preserve combining marks and joined emoji; they do not implement
configurable `iskeyword` or every Vim Unicode word-class distinction. Insert's
Ctrl+Arrow behavior is unchanged.

Deletes, changes, and yanks update an app-local unnamed register and also publish
the text to the system clipboard. `dd`/`cc`/`yy`, paragraph operators, and Visual-line
operations retain linewise type; ordinary word/character selections are characterwise.
`p`/`P` use this register even if another app changes the clipboard. It survives
New/Open, but not quitting. Insert Ctrl+C/X/V continue to use the system clipboard
without changing the register. Puts are a single undo step.

Normal motions land on characters, not the insertion position after a hard
line's last character. `$` lands on the final grapheme; `a` inserts after it
without crossing the newline. `yy` and backward `yb` retain the original cursor.
Insert retains native insertion-edge behavior. Escape clamps a trailing
insertion edge onto the final character, but does not step left within a line.

These remain Vim-inspired bindings, not a complete Vim implementation.
`I` goes to the hard line start, not the first nonblank. Paragraphs are runs of nonempty hard lines; whitespace-only
lines count as content. `ap` includes following blank lines, or preceding blank
lines at the end of the document. No counts, general operator grammar beyond the
listed bindings, blockwise selection, search, sentence objects, named/numbered
registers, or dot-repeat yet.

Visual selection includes the characters under both cursor endpoints. `v`
selects the current grapheme immediately, `vl` selects two, and reversing or
converting through Visual-line retains those endpoints. `Esc`/`v` return to the
active character rather than the exclusive selection boundary. `i` and `a`
start text-object commands; use `c` to replace a selection. Visual
put/replacement is not implemented; return to Normal to use `p`/`P`.

Files remain plain UTF-8 text (including Markdown source); there is no rendered
Markdown mode. Opens are limited to 1 MiB and reject NUL/invalid UTF-8. Line endings
normalize to LF. Save uses Ourokit's atomic replacement API, which currently writes
mode 0600 files and replaces destination symlinks rather than following them.
New/Open/Quit and window-close requests prompt before losing unsaved changes.
There is no autosave or crash recovery yet; do not use the prototype for your only copy.

## Check

```sh
lua test_document.lua
lua test_app.lua
python3 test_native.py
python3 snapshot.py --output /tmp/folio-stories
```

Storybook renders the same view as the app in empty, Normal, Insert, narrow,
unsaved-confirmation, and command-palette states, plus dark Normal, Insert,
unsaved-confirmation, and command-palette states. `snapshot.py` bundles the local modules for its
temporary catalog. Native interaction checks use the adjacent `ourokit`
checkout's disposable Sway/private D-Bus harness;
see `test_native.py` for overrides. Snapshot fonts come from Fontconfig.
