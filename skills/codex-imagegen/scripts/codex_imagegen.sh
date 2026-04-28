#!/usr/bin/env bash
# codex_imagegen.sh — Generate an image via the local Codex CLI
# (GPT-native image_gen, no FAL / no external image API key required).
#
# Usage:
#   codex_imagegen.sh <prompt> [output_path] [aspect_ratio] [reasoning_effort] [size]
#     output_path       absolute or relative; defaults to ./codex-image-<ts>.png
#     aspect_ratio      square | landscape | portrait          (default: square)
#     reasoning_effort  minimal | low | medium | high | xhigh  (default: medium)
#     size              1k | 2k | 4k | <W>x<H> | auto          (default: 1k)
#                       1k = 1024 short edge   (1024x1024 / 1536x1024 / 1024x1536)
#                       2k = 2048 short edge   (2048x2048 / 2048x1152 / 1152x2048)
#                       4k = ~3840 long edge   (LANDSCAPE/PORTRAIT only: 3840x2160 / 2160x3840;
#                                               4k square is not allowed by gpt-image-2)
#                       Or pass an explicit WxH (e.g. 2048x1536). Constraints checked:
#                         - max edge <= 3840
#                         - both edges multiples of 16
#                         - long/short ratio <= 3:1
#                         - 655,360 <= total pixels <= 8,294,400
#
# On success the last line of stdout is `FINAL_PATH=<absolute path>`.
# Exits non-zero on failure.
set -euo pipefail

PROMPT="${1:?prompt is required}"
OUT="${2:-}"
RATIO="${3:-square}"
EFFORT="${4:-medium}"
SIZE="${5:-1k}"

# Resolve output path -> absolute, ensure .png suffix.
if [[ -z "$OUT" ]]; then
    OUT="${PWD}/codex-image-$(date +%Y%m%d-%H%M%S)-$$.png"
fi
case "$OUT" in
    /*) ;;
    *)  OUT="${PWD}/${OUT}" ;;
esac
[[ "$OUT" == *.* ]] || OUT="${OUT}.png"

case "$RATIO" in
    landscape) RATIO_HINT="16:9 wide landscape composition";;
    portrait)  RATIO_HINT="9:16 tall portrait composition";;
    square)    RATIO_HINT="1:1 square composition";;
    *)         echo "ERROR: aspect_ratio must be square|landscape|portrait, got '$RATIO'" >&2; exit 2;;
esac

# Resolve size to explicit dimensions (or "auto").
resolve_size() {
    local preset="$1" ratio="$2"
    case "$preset" in
        auto) echo "auto"; return 0;;
        1k)
            case "$ratio" in
                square)    echo "1024x1024";;
                landscape) echo "1536x1024";;
                portrait)  echo "1024x1536";;
            esac
            return 0;;
        2k)
            case "$ratio" in
                square)    echo "2048x2048";;
                landscape) echo "2048x1152";;
                portrait)  echo "1152x2048";;
            esac
            return 0;;
        4k)
            case "$ratio" in
                square)
                    echo "ERROR: 4k square exceeds gpt-image-2 limits; use 2k for square or 4k landscape/portrait" >&2
                    return 2;;
                landscape) echo "3840x2160";;
                portrait)  echo "2160x3840";;
            esac
            return 0;;
        *x*)
            # Explicit WxH: validate constraints.
            local W="${preset%x*}" H="${preset#*x}"
            [[ "$W" =~ ^[0-9]+$ && "$H" =~ ^[0-9]+$ ]] || {
                echo "ERROR: size must be 1k|2k|4k|auto or WxH integers, got '$preset'" >&2; return 2; }
            (( W <= 3840 && H <= 3840 )) || {
                echo "ERROR: max edge must be <= 3840 (got ${W}x${H})" >&2; return 2; }
            (( W % 16 == 0 && H % 16 == 0 )) || {
                echo "ERROR: both edges must be multiples of 16 (got ${W}x${H})" >&2; return 2; }
            local lo hi total
            (( W <= H )) && { lo=$W; hi=$H; } || { lo=$H; hi=$W; }
            (( hi * 10 <= lo * 30 )) || {
                echo "ERROR: long/short aspect ratio must be <= 3:1 (got ${W}x${H})" >&2; return 2; }
            total=$(( W * H ))
            (( total >= 655360 && total <= 8294400 )) || {
                echo "ERROR: total pixels must be in [655360, 8294400] (got ${W}x${H} = $total)" >&2; return 2; }
            echo "${W}x${H}"
            return 0;;
        *)
            echo "ERROR: size must be 1k|2k|4k|auto or WxH, got '$preset'" >&2; return 2;;
    esac
}

SIZE_RESOLVED=$(resolve_size "$SIZE" "$RATIO")

if [[ "$SIZE_RESOLVED" == "auto" ]]; then
    SIZE_LINE="Output size: auto (let the model choose a reasonable size that matches the composition)."
else
    SIZE_LINE="Output size: render at exactly ${SIZE_RESOLVED} pixels (width x height). This is a hard requirement."
fi

command -v codex >/dev/null 2>&1 || {
    echo "ERROR: codex CLI not found on PATH" >&2; exit 127;
}

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
WORKDIR="$(mktemp -d -t codex-imagegen-XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT
mkdir -p "$(dirname "$OUT")"
START_TS=$(date +%s)

read -r -d '' CODEX_PROMPT <<EOF || true
Use the bundled imagegen skill and call the built-in image_gen tool.
Use native GPT image generation; do not produce SVG, do not call external APIs, do not fake the result.

Primary request: ${PROMPT}
Composition: ${RATIO_HINT}.
${SIZE_LINE}

When the image is ready, save the final selected PNG at exactly: ${OUT}
If sandbox limits prevent writing that exact path, that is fine — the wrapper will recover the file from \$CODEX_HOME/generated_images/.
Do not post-process or resize the file unless the generator returned a size that doesn't match the requested dimensions; if it matches, leave it alone.
End your response with a single line: FINAL_PATH=${OUT}
EOF

# Close stdin (codex hangs on stdin otherwise). xhigh reasoning is slow;
# medium is a much better default for routine generation.
codex exec \
    --skip-git-repo-check \
    --sandbox workspace-write \
    --cd "$WORKDIR" \
    -c "model_reasoning_effort=\"${EFFORT}\"" \
    "$CODEX_PROMPT" </dev/null

# Recovery: if codex couldn't write the requested path, find the newest
# ig_*.png written since we started and copy it over.
if [[ ! -f "$OUT" ]]; then
    SRC=$(find "$CODEX_HOME/generated_images" -type f -name 'ig_*.png' \
              -newermt "@$((START_TS - 5))" -printf '%T@ %p\n' 2>/dev/null \
          | sort -nr | head -n1 | cut -d' ' -f2-)
    if [[ -n "$SRC" && -f "$SRC" ]]; then
        cp "$SRC" "$OUT"
    fi
fi

if [[ ! -f "$OUT" ]]; then
    echo "ERROR: codex did not produce an image, and no recent ig_*.png was found under ${CODEX_HOME}/generated_images/" >&2
    exit 1
fi

echo "FINAL_PATH=$OUT"
