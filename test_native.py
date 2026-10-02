#!/usr/bin/env python3
"""Run: python3 test_native.py

Uses ../ourokit (override OUROKIT_DIR) and its native verification harness.
Starts a disposable headless Sway/private D-Bus session; never uses your desktop.
Set FOLIO_CAPTURE_DIR to retain review screenshots of the exercised window.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parent
TOOLKIT = Path(os.environ.get("OUROKIT_DIR", ROOT.parent / "ourokit")).resolve()
os.environ["OUROKIT_TEST_BINARY"] = str(TOOLKIT / "zig-out/bin/ouroctl")
sys.path.insert(0, str(TOOLKIT / "tests"))
from application_services import BINARY, development_path
from development_runtime import cli, inspect, png_pixel
from desktop_native import portal_source, wait_for, wait_portal
import verify_development as verify


def session():
    with tempfile.TemporaryDirectory(prefix="folio-native-") as directory:
        root = Path(directory)
        env = dict(os.environ, XDG_RUNTIME_DIR=directory,
                   WAYLAND_DISPLAY=os.environ["OUROKIT_TEST_WAYLAND_DISPLAY"])
        saved, opened = root / "saved draft.md", root / "opened.md"
        opened.write_bytes("Fresh café\r\nsecond paragraph".encode())
        portal = root / "portal.lua"
        portal.write_text(portal_source(saved.as_uri(), opened.as_uri(), root / "portal.log"))
        portal_process = subprocess.Popen(
            [str(BINARY), "run", str(portal), "--headless"], env=env,
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True, start_new_session=True)
        with (root / "app.log").open("w+") as log:
            process = subprocess.Popen(
                [str(BINARY), "run", str(ROOT / "ouro.json"), "--dev", "--software"],
                env=env, stdout=log, stderr=log, start_new_session=True)
            keyboard = None
            try:
                wait_portal(portal_process, env)
                endpoint = development_path(root, process, windows=("main",))
                # Keep a seat keyboard alive: otherwise removing the last wtype
                # device drops native keyboard focus and hides captured carets.
                keyboard = subprocess.Popen(["wtype", "-s", "100", "-k", "F12", "-s", "120000"],
                                            env=env, start_new_session=True)
                time.sleep(.2)

                def tree():
                    return inspect(env, endpoint, "main")

                def builds():
                    return json.loads(cli(env, "metrics", endpoint, {}))["windows"][0]["metrics"]["builds"]["count"]

                def editor():
                    return next(n for n in tree()["nodes"] if n["label"] == "Draft")

                def filename():
                    return next(n["label"] for n in tree()["nodes"]
                                if n["path"] and n["path"].endswith("/filename"))

                def input_(**args):
                    # Caret blink can advance the frame between CLI calls.
                    # Retry only an explicit pre-input stale-token rejection.
                    for _ in range(3):
                        arguments = dict(window="main", token=tree()["token"], **args)
                        result = subprocess.run([str(BINARY), "dev", "input", str(endpoint),
                            json.dumps(arguments)], env=env, capture_output=True, text=True, timeout=12)
                        reply = json.loads(result.stdout)
                        if reply.get("error", {}).get("code") == "StaleDevelopmentTarget":
                            continue
                        assert result.returncode == 0, (reply, result.stderr)
                        return reply
                    raise AssertionError("input remained stale across three fresh inspections")

                def key(name, **modifiers):
                    input_(action="key", key=name, **modifiers)

                def text(value):
                    input_(action="text", text=value)

                def click(suffix, exits=False):
                    target = next(n["path"] for n in tree()["nodes"]
                                  if n["path"] and n["path"].endswith(suffix))
                    if not exits:
                        input_(action="click", target=target)
                        return
                    # Quit can close the control socket before its RPC reply.
                    # The caller must still verify clean exit and persisted bytes.
                    result = subprocess.run([str(BINARY), "dev", "input", str(endpoint),
                        json.dumps(dict(window="main", token=tree()["token"],
                                        action="click", target=target))],
                        env=env, capture_output=True, timeout=12)
                    assert result.returncode == 0 or (
                        result.returncode == 1 and result.stderr == b"ouroctl: ConnectionClosed\n"
                    ), (result.returncode, result.stdout, result.stderr)

                def capture(name):
                    if output := os.environ.get("FOLIO_CAPTURE_DIR"):
                        path = Path(output)
                        path.mkdir(parents=True, exist_ok=True)
                        cli(env, "capture", endpoint, dict(window="main", token=tree()["token"]),
                            output=path / f"{name}.png")

                def palette():
                    subprocess.run(["wtype", "-s", "100", ":"], env=env, check=True)
                    wait_for(lambda: any(n["label"] == "Command" and n["focused"] for n in tree()["nodes"]),
                             "physical colon did not focus the command palette")

                def check_backdrop(label):
                    state = tree()
                    dialog = next(n for n in state["nodes"] if n["label"] == label)
                    path = root / "backdrop.png"
                    cli(env, "capture", endpoint, dict(window="main", token=state["token"]), output=path)
                    width, height, interior = png_pixel(path, 20, 20)
                    assert dialog["bounds"] == dict(x=0, y=0, width=width, height=height), "backdrop must fill the window, not its content inset"
                    for x, y in ((1, 1), (width - 2, 1), (1, height - 2), (width - 2, height - 2)):
                        assert png_pixel(path, x, y)[2] == interior, "window padding was not dimmed"
                    if label == "Commands":
                        body = next(n["bounds"] for n in state["nodes"] if (n["path"] or "").endswith("/palette/body"))
                        # Below the panel's 16px padding + 1px border, on blank backdrop.
                        shadow = png_pixel(path, int(body["x"] + body["width"] / 2), int(body["y"] + body["height"] + 25))[2]
                        assert all(shadow[i] < interior[i] for i in range(3)), "palette shadow must extend outside the card"

                assert editor()["focused"] and not editor()["read_only"] and not editor()["text_entry"]
                identity = editor()["id"]
                assert not any(n["label"] in ("Open", "Save", "0 words", "Press i. Begin anywhere.") for n in tree()["nodes"])
                capture("empty")
                key("i")
                assert editor()["text_entry"], "i must enter Insert without typing i"
                before_typing = builds()
                text("alpha βeta\nsecond line")
                assert editor()["value"] == "alpha βeta\nsecond line"
                assert builds() == before_typing + 1, "typing must only rebuild for the dirty marker"
                assert filename().endswith("•")
                key("escape")
                assert not editor()["text_entry"]
                palette()
                assert editor()["read_only"]
                check_backdrop("Commands")
                capture("commands")
                key("arrow_down"); key("arrow_up")
                text("unknown"); key("enter")
                assert any(n["label"] == "No matching commands" for n in tree()["nodes"])
                assert editor()["value"] == "alpha βeta\nsecond line"
                capture("commands-empty")
                key("escape")
                assert editor()["focused"] and editor()["id"] == identity
                palette(); text("enew"); key("enter")
                assert any(n["label"] == "Unsaved changes" for n in tree()["nodes"])
                key("escape")
                assert editor()["value"] == "alpha βeta\nsecond line"
                key("i")
                subprocess.run(["wtype", "-s", "100", ":"], env=env, check=True)
                wait_for(lambda: editor()["value"].endswith(":"), "Insert colon was not typed")
                key("z", control=True); key("escape")
                key("home", control=True)
                key("l"); key("l"); key("h"); key("i"); text("X")
                assert editor()["value"] == "aXlpha βeta\nsecond line", editor()
                key("z", control=True)
                assert editor()["value"] == "alpha βeta\nsecond line", "mode switches must retain undo"
                # Until the toolkit exposes custom motions, w is native Ctrl+Right:
                # the current word's trailing insertion edge, not Vim's next start.
                key("escape"); key("home", control=True); key("w"); key("i"); text("Y")
                assert editor()["value"] == "alphaY βeta\nsecond line", editor()
                key("z", control=True)
                key("escape"); key("g", shift=True); key("b"); key("i"); text("Z")
                assert editor()["value"] == "alpha βeta\nsecond Zline", editor()
                key("z", control=True)
                key("escape"); key("home", control=True); key("j"); key("i"); text("Q")
                assert editor()["value"] == "alpha βeta\nQsecond line", editor()
                key("z", control=True)
                key("escape"); key("g", shift=True); key("k"); key("home"); key("i"); text("R")
                assert editor()["value"] == "Ralpha βeta\nsecond line", editor()
                key("z", control=True)
                key("escape"); key("g", shift=True)
                # Give Sway time to attach wtype's new virtual keyboard before
                # its first key, then wait for the app's observable caret move.
                subprocess.run(["wtype", "-s", "100", "-k", "0"], env=env, check=True)
                wait_for(lambda: editor()["selection"]["extent"] == len("alpha βeta\n".encode()),
                         "physical 0 did not reach the line start")
                key("i"); text("T")
                assert editor()["value"] == "alpha βeta\nTsecond line", editor()
                key("z", control=True)
                key("escape"); key("home", control=True)
                subprocess.run(["wtype", "-s", "100", "-M", "shift", "-k", "4", "-m", "shift"], env=env, check=True)
                wait_for(lambda: editor()["selection"]["extent"] == len("alpha βeta".encode()),
                         "physical $ did not reach the line end")
                key("i"); text("S")
                assert editor()["value"] == "alpha βetaS\nsecond line", editor()
                key("z", control=True)

                # Native selection and Unicode deletion remain intact in Insert.
                key("home", control=True); key("arrow_right", control=True)
                key("arrow_right")  # Cross the space to β's leading insertion edge.
                key("arrow_right", shift=True); key("backspace")
                assert editor()["value"] == "alpha eta\nsecond line", editor()
                key("z", control=True)
                key("escape")
                before = editor()["value"]
                subprocess.run(["wtype", "-s", "100", "-d", "10", "ftz!?"], env=env, check=True)
                assert editor()["value"] == before, "Normal leaked unbound printable input"

                # Native line insertion and typing are separate undo steps. Both
                # motions operate on hard lines even when the caret is mid-line.
                key("home", control=True); key("l"); key("o")
                assert editor()["text_entry"] and editor()["value"] == "alpha βeta\n\nsecond line", editor()
                text("below")
                assert editor()["value"] == "alpha βeta\nbelow\nsecond line", editor()
                key("escape"); key("u")
                assert editor()["value"] == "alpha βeta\n\nsecond line", editor()
                key("u"); assert editor()["value"] == before
                key("r", control=True); key("r", control=True)
                assert editor()["value"] == "alpha βeta\nbelow\nsecond line", editor()
                key("u"); key("u")
                key("g", shift=True); key("o", shift=True); text("above")
                assert editor()["value"] == "alpha βeta\nabove\nsecond line", editor()
                key("escape"); key("u"); key("u"); assert editor()["value"] == before
                key("home", control=True); key("o", shift=True)
                assert editor()["value"] == "\n" + before and editor()["selection"]["extent"] == 0, editor()
                key("escape"); key("u"); key("g", shift=True); key("o")
                assert editor()["value"] == before + "\n" and editor()["selection"]["extent"] == len((before + "\n").encode()), editor()
                key("escape"); key("u"); assert editor()["value"] == before

                key("home", control=True); key("a"); text("!")
                assert editor()["value"] == "a!lpha βeta\nsecond line", editor()
                key("escape"); key("u"); key("a", shift=True); text("!")
                assert editor()["value"] == "alpha βeta!\nsecond line", editor()
                key("escape"); key("u"); key("i", shift=True); text("!")
                assert editor()["value"] == "!alpha βeta\nsecond line", editor()
                key("escape"); key("u"); assert editor()["value"] == before

                key("home", control=True); key("w"); key("l"); key("x")
                assert editor()["value"] == "alpha eta\nsecond line", editor()
                key("u"); assert editor()["value"] == before

                # Visual motions retain a native anchor, including backwards and
                # multi-byte selection. Replacing it must use native undo history.
                key("home", control=True); key("w"); key("l"); key("v"); key("l")
                assert any(n["label"] == "VISUAL" for n in tree()["nodes"])
                assert editor()["selection"]["anchor"] == 6 and editor()["selection"]["extent"] == 8, editor()
                capture("visual-forward")
                subprocess.run(["wtype", "-s", "100", "y"], env=env, check=True)
                key("escape"); key("g", shift=True); key("p")
                wait_for(lambda: editor()["value"] == before + "β", "Visual copy / Normal paste failed")
                key("u"); assert editor()["value"] == before
                key("home", control=True); key("w"); key("l"); key("v"); key("l")
                key("i"); text("Z")
                assert editor()["value"] == "alpha Zeta\nsecond line", editor()
                key("z", control=True)
                assert editor()["value"] == before
                key("escape"); key("g", shift=True); key("v"); key("b")
                assert editor()["selection"]["anchor"] == len(before.encode()), editor()
                assert editor()["selection"]["extent"] == len("alpha βeta\nsecond ".encode()), editor()
                capture("visual-backward")
                key("v")
                assert any(n["label"] == "NORMAL" for n in tree()["nodes"])
                assert editor()["value"] == before
                assert editor()["selection"]["anchor"] == editor()["selection"]["extent"] == len("alpha βeta\nsecond ".encode()), editor()
                key("home", control=True); key("v"); key("w"); key("d")
                assert editor()["value"] == " βeta\nsecond line" and not editor()["text_entry"], editor()
                key("u"); assert editor()["value"] == before
                key("home", control=True); key("v"); key("w"); key("c"); text("New")
                assert editor()["value"] == "New βeta\nsecond line" and editor()["text_entry"], editor()
                key("escape"); key("u"); key("u"); assert editor()["value"] == before
                assert editor()["id"] == identity, "mode changes or native edits remounted the editor"

                key("n", control=True)
                assert any(n["label"] == "Unsaved changes" for n in tree()["nodes"])
                check_backdrop("Unsaved changes")
                capture("unsaved")
                key("escape")
                assert editor()["value"] == before and editor()["focused"]
                key("n", control=True); click("/buttons/discard")
                assert editor()["value"] == "" and not editor()["text_entry"]
                key("o")
                assert editor()["value"] == "\n" and editor()["text_entry"], editor()
                key("escape"); key("u")
                assert editor()["value"] == "", editor()
                key("i"); key("z", control=True)
                assert editor()["value"] == "", "New must not inherit the previous document's undo"
                text("A room for words\n\nThe first thing I noticed was the quiet. Not the absence of sound, "
                     "but the space between things: a cup on the table, rain at the window, a sentence waiting "
                     "to be finished.\n\nI had spent the morning moving words around. A paragraph moved up. "
                     "A sentence disappeared. What remained was closer to what I meant.\n\nWriting is sometimes "
                     "like that. Less a matter of finding something new than making enough room to see what "
                     "is already there.")
                key("home", control=True)
                capture("insert")
                key("escape"); capture("normal")
                key("g", shift=True); capture("normal-eol")
                key("o"); key("escape"); capture("normal-empty-line")
                key("u")
                key("home", control=True); key("v"); key("j"); capture("visual")
                selection = editor()["selection"]
                identity = editor()["id"]
                palette(); key("escape")
                assert editor()["selection"] == selection and editor()["id"] == identity
                key("escape")
                assert json.loads(cli(env, "diagnostics", endpoint))["diagnostic"] is None, "runtime diagnostics"

                # Real portal RPC, file-worker I/O, and byte-for-byte persistence.
                draft = editor()["value"]
                palette(); text("w"); capture("commands-filtered"); key("enter")
                wait_for(lambda: filename() == "saved draft.md", "save did not clear dirty state")
                assert saved.read_bytes() == draft.encode()
                key("i"); key("home", control=True); text("Revised ")
                key("s", control=True)
                wait_for(lambda: filename() == "saved draft.md", "second save did not finish")
                assert saved.read_bytes() == ("Revised " + draft).encode()
                key("escape"); palette(); text("e"); key("enter")
                wait_for(lambda: filename() == "opened.md", "open did not finish")
                assert editor()["value"] == "Fresh café\nsecond paragraph" and not editor()["text_entry"]

                # Bad files leave the current buffer and saved filename untouched.
                opened.write_bytes(b"bad\xff")
                key("o", control=True)
                wait_for(lambda: any("not UTF-8" in n["label"] for n in tree()["nodes"]), "invalid file error missing")
                assert filename() == "opened.md" and editor()["value"] == "Fresh café\nsecond paragraph"
                capture("invalid-file")

                # Selection must follow graphemes, not UTF-8 bytes or codepoints.
                graphemes = "A e\u0301 👩‍💻 Z\nShort"
                opened.write_text(graphemes)
                key("o", control=True)
                wait_for(lambda: editor()["value"] == graphemes, "grapheme fixture did not load")
                key("home", control=True); key("l"); key("l"); key("v"); key("l")
                assert editor()["selection"]["anchor"] == 2 and editor()["selection"]["extent"] == 5, editor()
                key("h"); key("h")  # Shrink to the anchor, then reverse over the space.
                assert editor()["selection"]["anchor"] == 2 and editor()["selection"]["extent"] == 1, editor()
                key("i"); text("X")
                assert editor()["value"] == "AXe\u0301 👩‍💻 Z\nShort", editor()
                key("z", control=True)
                assert editor()["value"] == graphemes
                key("escape"); key("home", control=True)
                for _ in range(4): key("l")
                key("v"); key("l")
                assert editor()["selection"]["anchor"] == 6 and editor()["selection"]["extent"] == 17, editor()
                key("i"); text("Q")
                assert editor()["value"] == "A e\u0301 Q Z\nShort", editor()
                key("z", control=True)
                assert editor()["value"] == graphemes

                wrapped = "A wrapped paragraph with words. " * 12
                opened.write_text(wrapped + "\nTail")
                key("o", control=True)
                wait_for(lambda: editor()["value"] == wrapped + "\nTail", "wrapped fixture did not load")
                key("home", control=True); key("j"); key("o")
                assert editor()["value"] == wrapped + "\n\nTail", "o split a wrapped visual line"
                text("Between")
                assert editor()["value"] == wrapped + "\nBetween\nTail", editor()
                key("escape"); key("u"); key("u")
                key("home", control=True); key("j"); key("a", shift=True)
                text("!")
                assert editor()["value"] == wrapped + "!\nTail", "A stopped at a visual line edge"
                key("escape"); key("u")
                key("home", control=True); key("j"); key("o", shift=True); text("Before")
                assert editor()["value"] == "Before\n" + wrapped + "\nTail", "O split a wrapped visual line"
                key("escape"); key("u"); key("u")

                # One hard line with no spaces must have multiple visual rows.
                # End is a visual motion; $ and O/o remain hard-line commands.
                unbroken = "d" * 101
                opened.write_text(unbroken)
                key("o", control=True)
                wait_for(lambda: editor()["value"] == unbroken, "unbroken fixture did not load")
                key("home", control=True); key("end")
                first_end = editor()["selection"]["extent"]
                assert 0 < first_end < len(unbroken), "unbroken word did not wrap"
                capture("wrapped")
                key("g", shift=True); key("home")
                assert 0 < editor()["selection"]["extent"] < len(unbroken)
                key("o"); text("Tail")
                assert editor()["value"] == unbroken + "\nTail"
                key("escape"); key("u"); key("u")
                assert editor()["value"] == unbroken

                # Load a long draft rather than simulating 1,000 individual keystrokes.
                long_draft = "Fresh café\nsecond paragraph\n" + "A line of prose.\n" * 60
                opened.write_text(long_draft)
                key("o", control=True)
                wait_for(lambda: editor()["value"] == long_draft, "long file did not load")
                key("i"); key("end", control=True); text("An ending.")
                assert editor()["scroll_offset"] > 0, "long draft must scroll to the caret"
                final = editor()["value"]
                key("q", control=True)
                assert any(n["label"] == "Unsaved changes" for n in tree()["nodes"])
                click("/buttons/save", exits=True)
                assert process.wait(timeout=10) == 0
                assert opened.read_bytes() == final.encode(), "Save and Quit lost edits"
                print("PASS: native modes, motions, Visual selection, graphemes, undo, Normal input guard, New/Cancel/Discard, portal open/save, invalid-file preservation, scrolling, Save and Quit")
            except BaseException:
                log.seek(0)
                print(log.read(), file=sys.stderr)
                raise
            finally:
                if keyboard is not None:
                    verify.stop(keyboard)
                verify.stop(process)
                verify.stop(portal_process)


if __name__ == "__main__":
    if os.environ.get("OUROKIT_TEST_WAYLAND_DISPLAY"):
        session()
    else:
        verify.TESTS = (str(Path(__file__).resolve()),)
        verify.verify(BINARY)
