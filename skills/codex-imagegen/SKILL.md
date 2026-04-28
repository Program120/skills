---
name: codex-imagegen
description: Generate AI images locally by delegating to the installed Codex CLI's GPT-native image_gen tool. Use this skill whenever the user asks to generate, create, draw, render, or make any kind of bitmap image, picture, illustration, photo, hero, banner, poster, sprite, mockup, icon-as-bitmap, or visual asset — including 生图, 画一张, AI 生图, AI 画图, make me a picture, draw me, render an illustration — and Claude does not otherwise have a working native image generation tool in this session. Also use it when the deliverable for a task is a PNG/JPG (UI mockup, blog hero, social card, product shot, concept art, game asset). Do NOT use for matching an existing SVG/vector icon system, simple shapes/diagrams that should stay as code (HTML/CSS/canvas/SVG), or for editing a user-supplied image where they only asked for trivial cropping/resizing — defer to the user's tools or simpler approaches in those cases.
---

# Codex Imagegen

Use the locally-installed `codex` CLI to call GPT-native image generation. The wrapper script handles the writable workspace, the prompt scaffold, and the file recovery from `~/.codex/generated_images/` so you can treat it as a one-shot tool.

## When to use

- The user asks for a new bitmap image (photo, illustration, hero, poster, mockup, sprite, concept art, etc.).
- A task needs a generated raster asset and there is no other native `image_gen` tool available in the session.
- The user said "生图 / 画一张 / AI 画图" or any other phrasing that clearly asks for an AI-generated picture.

## When NOT to use

- The visual should be **vector** (logo system, icon set, simple diagram) — produce SVG/HTML/CSS instead.
- A simpler editing tool (ImageMagick, ffmpeg, Pillow) already does what the user wants — don't spin up Codex for crop/resize.
- The user wants to *edit* their own attached image with only trivial changes — ask whether they want a regenerate or a local edit first.

## Prerequisites (verify quickly, don't belabor)

- `command -v codex` is on PATH.
- `codex login status` says `Logged in using ChatGPT` **or** `OPENAI_API_KEY` is set.
- `~/.codex/config.toml` controls the default model (currently `gpt-5.5`). You normally don't need to override it.

If any prerequisite is missing, tell the user exactly what's missing and stop — don't try to silently work around it.

## How to invoke

Prefer the bundled wrapper. It accepts a prompt, optional output path, optional aspect ratio, and optional reasoning effort, and prints `FINAL_PATH=<absolute path>` on success.

```bash
~/.claude/skills/codex-imagegen/scripts/codex_imagegen.sh \
  "<prompt>" \
  [output_path] \
  [square|landscape|portrait] \
  [minimal|low|medium|high|xhigh] \
  [1k|2k|4k|<W>x<H>|auto]
```

Defaults: aspect_ratio=`square`, reasoning_effort=`medium`, size=`1k`.

### Size

| arg     | square      | landscape   | portrait    |
|---------|-------------|-------------|-------------|
| `1k`    | 1024×1024   | 1536×1024   | 1024×1536   |
| `2k`    | 2048×2048   | 2048×1152   | 1152×2048   |
| `4k`    | *(invalid)* | 3840×2160   | 2160×3840   |
| `auto`  | model picks composition-appropriate dimensions |
| `WxH`   | explicit override (validated against the constraints below) |

Constraints for explicit `WxH`: max edge ≤ 3840 · both edges multiples of 16 · long/short ≤ 3:1 · 655,360 ≤ total pixels ≤ 8,294,400. The wrapper validates and exits with a clear error on violations. 4K square exceeds the total-pixel cap, so it's rejected — use 2K square for the largest square output.

Always run it with `run_in_background: true` (or background it with `&` + `disown`) and a Monitor on the log — even with `medium` reasoning, generation takes 1–3 minutes. With `xhigh` it can take 15–20 minutes; only use that when the user explicitly asked for the highest quality.

After the script exits, parse the `FINAL_PATH=...` line for the absolute path. The file is a real PNG on disk; you can `Read` it back to show inline, or pass it on to the user.

### Examples

```bash
# Default 1K square draft (~1–3 min)
~/.claude/skills/codex-imagegen/scripts/codex_imagegen.sh \
  "a single bright red apple on a white plain background, simple flat illustration" \
  /tmp/apple.png

# 2K landscape hero
~/.claude/skills/codex-imagegen/scripts/codex_imagegen.sh \
  "a minimal landing-page hero of a ceramic coffee mug on a marble counter, soft studio light, generous negative space" \
  /tmp/hero.png \
  landscape medium 2k

# 4K wallpaper, with high reasoning for cleaner composition
~/.claude/skills/codex-imagegen/scripts/codex_imagegen.sh \
  "a serene alpine lake at golden hour, low-poly stylized 3D render, no text" \
  /tmp/wallpaper.png \
  landscape high 4k

# Explicit non-standard dimensions (must satisfy constraints)
~/.claude/skills/codex-imagegen/scripts/codex_imagegen.sh \
  "geometric abstract poster, bold primary colors" \
  /tmp/poster.png \
  portrait medium 1280x1920
```

## Writing good prompts for codex's imagegen

Codex's bundled imagegen skill expects a labelled spec internally. The wrapper already wires in the primary request and the composition; the rest is up to you to include in the prompt argument when it materially helps. A good prompt usually has 3–5 of:

- **Subject** — the main thing in the frame.
- **Scene/backdrop** — environment around the subject.
- **Style/medium** — photo, watercolor, 3D render, line art, etc.
- **Lighting/mood** — soft studio / golden hour / harsh noon / moody.
- **Composition/framing** — wide shot, close-up, top-down; placement.
- **Constraints** — "no text", "no watermark", "no logos", things to avoid.

Quote any in-image text **verbatim** with quotes. For tricky words, spell them letter-by-letter and demand verbatim rendering. For edits or iterative variants, list invariants explicitly ("change only the background; keep the subject and pose unchanged").

Don't pad. If the user gave a specific prompt, normalize it without adding unrequested objects, brand names, or beats.

## Output handling

- On success the wrapper prints `FINAL_PATH=<absolute path>`. Prefer that path over scanning directories yourself.
- The wrapper may fall back to copying from `~/.codex/generated_images/<session_id>/ig_*.png` (newest file by mtime, written after the run started). This is normal — codex sometimes can't write the requested path due to sandbox limits, and the wrapper recovers it.
- If you need a different size/aspect than what came back, prefer telling codex via the prompt and aspect_ratio argument rather than post-resizing — re-running gives a better image than a forced ffmpeg scale. Only post-process for trimming/converting formats.
- If the user wants the asset committed into a project, copy or move the final PNG into the workspace yourself; don't leave it under `/tmp` or `~/.codex/generated_images/`.

## Common failure modes & fixes

- **Hangs forever, no output, no session log written**: stdin not closed. The wrapper closes it (`</dev/null`); if you bypass the wrapper and call `codex exec` directly, you must do the same.
- **`/tmp/foo.png` not written even though codex says it generated**: sandbox blocked the write. The wrapper handles recovery automatically; if you ran codex directly, scan `~/.codex/generated_images/` for an `ig_*.png` newer than your start time and copy it.
- **Slow (10+ minutes for a simple image)**: reasoning effort is `xhigh` (the user's default). Pass `medium` to the wrapper, or override at the command via `-c model_reasoning_effort=medium`.
- **`ERROR codex_core::session: ... thread ... not found`**: harmless, appears at the end of some runs; the image still gets written.
- **Wrong model**: the default model comes from `~/.codex/config.toml`. To override per-call: `codex exec -c model="gpt-5.5" ...` (or a different model id the account supports).

## Direct invocation reference

If you need to bypass the wrapper (e.g., for a one-off shell command in front of the user), the minimum recipe is:

```bash
codex exec --skip-git-repo-check --sandbox workspace-write --cd "$(mktemp -d)" \
  -c model_reasoning_effort=medium \
  "Use the imagegen skill / built-in image_gen tool. Generate <prompt>. Save the final PNG at /abs/path/out.png and end with: FINAL_PATH=/abs/path/out.png" </dev/null
```

Then check that the file exists; if not, recover with:

```bash
find "${CODEX_HOME:-$HOME/.codex}/generated_images" -type f -name 'ig_*.png' \
  -newermt "@$START_TS" -printf '%T@ %p\n' | sort -nr | head -1
```

## Reasoning effort guide

| Effort   | Roughly | When to use                                                         |
|----------|---------|---------------------------------------------------------------------|
| minimal  | <1 min  | Quick mockups, throw-away drafts.                                   |
| low      | ~1 min  | Simple subjects, no fine text, drafts.                              |
| medium   | 1–3 min | **Default.** Most generation requests.                              |
| high     | 3–8 min | Detailed scenes, multi-element compositions, exact text rendering.  |
| xhigh    | 10–20+m | Identity-sensitive edits, complex layouts; only on explicit request.|

## Files

- `scripts/codex_imagegen.sh` — the wrapper described above. Idempotent, no external deps beyond `codex`, `find`, `cp`. Cleans up its temp workdir.
