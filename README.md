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
and logical-line editing commands), plus `caret_blink`, `Colon`, and
multiline emergency-wrapping, selection-caret and space-width fallback changes.
The launcher and Python checks default to
`../ourokit` and accept `OUROKIT_DIR` to select another compatible checkout.
No native plugin is required. Open/Save As use the desktop's
XDG file chooser portal; install your desktop's portal backend if needed.

`./run-desktop.sh --dev` enables explicit source reload. Save your draft before
reloading: Lua document state resets with the source generation. Reload does not
upgrade the native toolkit binary; that requires restarting the application.

## Keyboard

The app starts in **Normal** with a block cursor and unbound typing suppressed.
`i` enters **Insert** with a beam cursor; `Esc` returns to Normal without remounting
the editor or clearing undo history. **Visual** keeps a distinct charcoal block
at the active selection end, over the beige selection highlight. Empty-line and
end-of-line blocks use the font's space width. There is no Replace mode, so no
underline mode is shown.
Carets are steady in all modes. The writing surface has no placeholder,
keyboard hints, word count, or Open/Save buttons.

| Key | Action |
| --- | --- |
| `h j k l` | Left, visual line down/up, right |
| `w` / `e`, `b` | Native next/previous word boundary |
| `0 $` | Start/end of the hard logical line |
| `G`, `Ctrl+Home` | End/start of document |
| `a`, `A`, `I` | Insert after one grapheme, at hard line end, at hard line start |
| `o O` | Open an empty hard line below/above and enter Insert |
| `x X` | Delete the next/previous grapheme |
| `u`, `Ctrl+R` in Normal | Undo/redo |
| `p` in Normal | Paste the system clipboard at the insertion edge |
| `v` | Enter Visual selection; `v` or `Esc` returns to Normal |
| Motions in Visual | Extend or shrink the native selection |
| `y` in Visual | Copy selection to the system clipboard |
| `d` / `x` in Visual | Delete selection and return to Normal |
| `c` in Visual | Delete selection and enter Insert |
| `i` in Visual | Enter Insert; typing replaces the selection |
| `:` in Normal/Visual | Open the command palette |
| `Ctrl+S`, `Ctrl+Shift+S` | Save, Save As |
| `Ctrl+O`, `Ctrl+N`, `Ctrl+Q` | Open, New, Quit |
| `Ctrl+Z`, `Ctrl+Shift+Z` in Insert | Native undo/redo |

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
explicit native edit bindings remain available. Line insertion and subsequent
typing are separate undo steps. `o`/`O` do not auto-indent.
These are Vim-inspired bindings over the toolkit's native caret semantics, not
exact Vim behavior: `w` currently advances to the current/next word's **end**
(like native Ctrl+Right), not the next word's start. `I` goes to the hard line
start, not the first nonblank; `p` pastes at the native insertion edge, not after
the character as in Vim. There are no motion-based operators (`dw`, `cw`, `yw`),
counts, `gg`, linewise/blockwise selection,
search, sentence/paragraph text objects, or dot-repeat yet. Supporting those
properly needs a toolkit editor-command/selection API, not a second text engine.

Visual currently uses native insertion-edge selection, not Vim's inclusive
character selection: press `v`, then move to select text. Copy keeps Visual active.
`Esc`/`v` collapse at the active selection end without moving it. `i` preserves
the range so typing replaces it. With an empty range, `d`/`x`/`c` delete the next
grapheme, just like the underlying native delete action. Deletions do not update
a Vim register; copy explicitly with `y` when you need the text later.

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
unsaved-confirmation, and command-palette states. `snapshot.py` bundles the local modules for its
temporary catalog. Native interaction checks use the adjacent `ourokit`
checkout's disposable Sway/private D-Bus harness;
see `test_native.py` for overrides. Snapshot fonts come from Fontconfig.
