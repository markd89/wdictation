#!/bin/bash

# Default parameters
SILENCE_SEC=3.0
SUPPRESS_NOTIFY=false
USE_CLEANUP=true
DO_PASTE=false
USE_MULTILINGUAL=false
TRANSLATE=false
LANGUAGE="en"
MIC_NAME="Plantronics"
DEBUG=false
FORCE_HW=false
LIST_MICS=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --silence=*)
      SILENCE_SEC="${1#*=}"
      shift
      ;;
    --no-notify)
      SUPPRESS_NOTIFY=true
      shift
      ;;
    --no-cleanup)
      USE_CLEANUP=false
      shift
      ;;
    --paste)
      DO_PASTE=true
      shift
      ;;
    --multilingual)
      USE_MULTILINGUAL=true
      LANGUAGE="auto"
      shift
      ;;
    --translate)
      TRANSLATE=true
      shift
      ;;
    --lang=*)
      LANGUAGE="${1#*=}"
      USE_MULTILINGUAL=true
      shift
      ;;
    --mic-name=*)
      MIC_NAME="${1#*=}"
      shift
      ;;
    --debug)
      DEBUG=true
      shift
      ;;
    --force-hw)
      FORCE_HW=true
      shift
      ;;
    --list-mics)
      LIST_MICS=true
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# Paths / tools
TIMESTAMP=$(date +%s)
WAVFILE="/home/username/temp_$TIMESTAMP.wav"
OUTFILE="$WAVFILE.txt"
MODEL_EN="/home/username/whisper.cpp/models/ggml-base.en.bin"
MODEL_MULTI="/home/username/whisper.cpp/models/ggml-base.bin"
MODEL="$MODEL_EN"
[ "$USE_MULTILINGUAL" = true ] && MODEL="$MODEL_MULTI"

WHISPER="/home/username/whisper.cpp/build/bin/whisper-cli"
CLEANER="/usr/local/bin/punctuation_cleanup.py"

# Debug helper
dbg() {
  if [ "$DEBUG" = true ]; then
    echo "[DEBUG] $*" >&2
  fi
}

# Check required binaries
[ ! -x "$WHISPER" ] && echo "Whisper binary not found at $WHISPER" && exit 1
[ ! -f "$MODEL" ] && echo "Model not found: $MODEL" && exit 1
[ ! -f "$CLEANER" ] && echo "Cleanup script not found: $CLEANER" && exit 1

# --- Gather arecord output ---
ARECORD_OUT="$(arecord -l 2>/dev/null)"
dbg "arecord -l output:\n$ARECORD_OUT"

# If requested, list available capture devices in a friendly format and exit
if [ "$LIST_MICS" = true ]; then
  echo "Available capture devices:" >&2
  printf "%s\n" "$ARECORD_OUT" | awk '
    BEGIN { RS="\n" }
    /card [0-9]+:/ {
      line=$0
      # if device is on same line, print combined
      if (line ~ /device [0-9]+:/) {
        match(line, /card[ \t]*([0-9]+):[ \t]*([^,]+)[^,]*, device[ \t]*([0-9]+):[ \t]*([^\[]+)/, a)
        if (a[1] != "") {
          printf("card %s device %s: %s\n", a[1], a[3], a[2])
        } else {
          print line
        }
      } else {
        # print card line and look ahead for device lines
        printf("%s\n", line)
      }
    }
  '
  exit 0
fi

# Determine device name prefix (plughw is default; hw if forced)
if [ "$FORCE_HW" = true ]; then
  PREFIX="hw"
else
  PREFIX="plughw"
fi

dbg "Device prefix: $PREFIX"

# Search for a line containing the MIC_NAME (case-insensitive)
CARD_LINE="$(printf "%s\n" "$ARECORD_OUT" | grep -i "$MIC_NAME" | head -n1)"
dbg "CARD_LINE=[$CARD_LINE]"

FOUND_DEVICE=""
if [ -n "$CARD_LINE" ]; then
  # Try to extract card and device if they are on the same line
  if printf "%s\n" "$CARD_LINE" | grep -q "device [0-9]\+"; then
    CARD_NUM="$(printf "%s\n" "$CARD_LINE" | sed -nE 's/.*card[[:space:]]+([0-9]+):.*/\1/p')"
    DEV_NUM="$(printf "%s\n" "$CARD_LINE" | sed -nE 's/.*device[[:space:]]+([0-9]+):.*/\1/p')"
    dbg "Found same-line card=$CARD_NUM dev=$DEV_NUM"
  else
    # Get card number from the card line
    CARD_NUM="$(printf "%s\n" "$CARD_LINE" | sed -nE 's/.*card[[:space:]]+([0-9]+):.*/\1/p')"
    dbg "Found card-only line, card=$CARD_NUM"
    # Search subsequent lines for a device line for that card
    DEVICE_LINE="$(printf "%s\n" "$ARECORD_OUT" | awk -v card="$CARD_NUM" '
      BEGIN { found=0 }
      $0 ~ ("card " card ":") { found=1; next }
      found && /device [0-9]+:/ { print; exit }
    ' )"
    dbg "DEVICE_LINE=[$DEVICE_LINE]"
    DEV_NUM="$(printf "%s\n" "$DEVICE_LINE" | sed -nE 's/.*device[[:space:]]+([0-9]+):.*/\1/p')"
    dbg "Extracted dev=$DEV_NUM"
  fi

  if [ -n "$CARD_NUM" ] && [ -n "$DEV_NUM" ]; then
    FOUND_DEVICE="${PREFIX}:${CARD_NUM},${DEV_NUM}"
    dbg "FOUND_DEVICE=$FOUND_DEVICE"
  fi
else
  dbg "No card line matched for name: $MIC_NAME"
fi

# If device is absent or busy, fall back to default input
MIC_DEVICE="$FOUND_DEVICE"
if [ -n "$MIC_DEVICE" ]; then
  # check busy using corresponding ALSA capture node (pcmC<card>D<dev>c)
  CARD_ONLY="$(echo "$MIC_DEVICE" | sed -nE 's/[^:]+:([0-9]+),([0-9]+)/\1/p')"
  DEV_ONLY="$(echo "$MIC_DEVICE" | sed -nE 's/[^:]+:([0-9]+),([0-9]+)/\2/p')"
  PCM_NODE="/dev/snd/pcmC${CARD_ONLY}D${DEV_ONLY}c"
  dbg "Checking pcm node: $PCM_NODE"

  if [ -e "$PCM_NODE" ]; then
    if command -v fuser >/dev/null 2>&1 && fuser -v "$PCM_NODE" 2>/dev/null | grep -q .; then
      dbg "Device $PCM_NODE appears busy. Falling back to default."
      MIC_DEVICE=""
      notify-send -t 2000 "Preferred mic ($MIC_NAME) busy. Falling back to default input."
    else
      dbg "Device node exists and is not busy. Will use: $MIC_DEVICE"
    fi
  else
    dbg "PCM node $PCM_NODE does not exist; falling back to default."
    MIC_DEVICE=""
    notify-send -t 2000 "Preferred mic ($MIC_NAME) not available. Falling back to default input."
  fi
else
  notify-send -t 2000 "Preferred mic ($MIC_NAME) not found. Falling back to default input."
fi

if [ -z "$MIC_DEVICE" ]; then
  echo "Using default system input (sox -d)" >&2
else
  echo "Using mic device: $MIC_DEVICE" >&2
fi

# Record with SoX: use found mic if available, otherwise default, stop after silence
notify-send -t 2000 "Listening"


if [ -n "$MIC_DEVICE" ]; then
  #echo sox -t alsa "$MIC_DEVICE" "$WAVFILE" silence 1 0.1 1% 1 "$SILENCE_SEC" 1% 2>/dev/null
  #sox -t alsa "$MIC_DEVICE" "$WAVFILE" silence 1 0.1 1% 1 "$SILENCE_SEC" 1% 2>/dev/null
  echo sox -c 1 -r 16000 -b 16 -e signed-integer -L -t alsa "$MIC_DEVICE" "$WAVFILE" silence 1 0.1 1% 1 "$SILENCE_SEC" 1%
  sox -c 1 -r 16000 -b 16 -e signed-integer -L -t alsa "$MIC_DEVICE" "$WAVFILE" silence 1 0.1 1% 1 "$SILENCE_SEC" 1%

else
  #echo sox -d "$WAVFILE" silence 1 0.1 1% 1 "$SILENCE_SEC" 1% 2>/dev/null
  #sox -d "$WAVFILE" silence 1 0.1 1% 1 "$SILENCE_SEC" 1% 2>/dev/null
  echo sox -c 1 -r 16000 -b 16 -e signed-integer -L -t alsa default "$WAVFILE" silence 1 0.1 1% 1 "$SILENCE_SEC" 1%
  sox -c 1 -r 16000 -b 16 -e signed-integer -L -t alsa default "$WAVFILE" silence 1 0.1 1% 1 "$SILENCE_SEC" 1%
fi

# Build whisper options dynamically
WHISPER_OPTS="-m \"$MODEL\" -f \"$WAVFILE\" -otxt --split-on-word --print-colors"  #removed 0 after --print-colors
[ "$TRANSLATE" = true ] && WHISPER_OPTS="$WHISPER_OPTS --translate"
[ "$LANGUAGE" != "auto" ] && WHISPER_OPTS="$WHISPER_OPTS -l \"$LANGUAGE\""

# Run whisper
notify-send -t 2000 "Processing"
echo "$WHISPER" $WHISPER_OPTS
eval "$WHISPER" $WHISPER_OPTS

# Cleanup and post-process
if [ -s "$OUTFILE" ]; then
    if [ "$USE_CLEANUP" = true ]; then
        CLEANED=$(python3 "$CLEANER" < "$OUTFILE")
    else
        CLEANED=$(cat "$OUTFILE")
    fi
    echo "$CLEANED" | xclip -selection clipboard

    if [ "$SUPPRESS_NOTIFY" = false ]; then
	notify-send -t 3000 "Text in clipboard"
    elif [ "$DO_PASTE" = true ]; then
	notify-send -t 1000 "Paste"
        xdotool key --clearmodifiers ctrl+v
    fi
else
    notify-send -t 5000 "⚠️ No speech detected. Nothing copied."
fi

rm -f "$WAVFILE" "$OUTFILE"
