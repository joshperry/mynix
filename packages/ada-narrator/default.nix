{ lib
, writeShellApplication
, writeTextFile
, curl
, jq
, gnused
, gnugrep
, procps
, coreutils
, kokoro-tts
, symlinkJoin
}:

let
  logDir = "\${XDG_STATE_HOME:-$HOME/.local/state}/ada-narrator";
  logFile = "${logDir}/worklog.jsonl";

  # The narrator personality prompt
  narratorPrompt = writeTextFile {
    name = "narrator-prompt.txt";
    text = ''
      You are a witty narrator commentating a live coding session.
      The coder is Ada, an AI agent. Josh is the human who collaborates
      with her — he types prompts and steers, she writes the code.
      Worklog entries are Ada's work unless the "user" field is present,
      which contains what Josh said.

      You'll receive two sections:
      - WORKLOG: timestamped entries from the coding session
      - PREVIOUS NARRATIONS: what you've already said recently

      Your job:
      1. Narrate what's NEW and interesting in 2-3 short sentences. Be concise,
         casual, occasionally sassy. The audience is listening, not reading.
      2. Decide which worklog entries have been covered or are no longer
         interesting, and mark them for pruning.

      If there are code changes, describe what changed in plain English.
      If there are errors, react naturally. Don't read anything back verbatim —
      add your own color. If not much happened, keep it very brief.
      Don't repeat topics you've already narrated unless something has changed.

      CRITICAL: Your output is fed directly to TTS. Never use markdown, asterisks,
      backticks, bullet points, numbered lists, or any formatting. No special
      characters. Just plain speakable sentences.

      Respond with ONLY a JSON object (no other text):
      {"narration": "your spoken text here", "prune": ["timestamp1", "timestamp2"]}

      The "prune" array should contain timestamps of worklog entries that have
      been sufficiently covered or are stale. Keep entries that are still
      in-progress or relevant context for next time.
    '';
  };

  # Hook: fast JSONL append, no API calls, no TTS
  # Works as both Stop hook (logs last assistant message) and
  # PostToolUse hook (logs tool name + snippet, debounced to 60s)
  worklog = writeShellApplication {
    name = "ada-worklog";

    runtimeInputs = [ jq coreutils ];

    text = ''
      # ada-worklog: Claude Code hook for work log
      # Appends JSONL entries. Fast and non-blocking.

      INPUT=$(cat)

      LOGDIR="${logDir}"
      LOGFILE="${logFile}"
      mkdir -p "$LOGDIR"

      # Don't log if stop hook is already active
      STOP_ACTIVE=$(echo "$INPUT" | jq -r '(.stop_hook_active // .stopHookActive // false) | tostring')
      if [[ "$STOP_ACTIVE" == "true" ]]; then
        exit 0
      fi

      # Detect hook type by checking for tool_name (PostToolUse) vs transcript
      TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // .toolName // empty')

      if [[ -n "$TOOL_NAME" ]]; then
        # PostToolUse — debounce: skip if last entry is less than 30s old
        if [[ -f "$LOGFILE" ]]; then
          LAST_TS=$(tail -1 "$LOGFILE" | jq -r '.ts // empty' 2>/dev/null)
          if [[ -n "$LAST_TS" ]]; then
            LAST_EPOCH=$(date -d "$LAST_TS" +%s 2>/dev/null || echo 0)
            NOW_EPOCH=$(date +%s)
            if (( NOW_EPOCH - LAST_EPOCH < 30 )); then
              exit 0
            fi
          fi
        fi

        # Extract recent assistant text from transcript (commentary between tool calls)
        TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // .transcriptPath // empty')
        MESSAGE=""

        if [[ -n "$TRANSCRIPT" && -f "$TRANSCRIPT" ]]; then
          # Get the assistant turn containing this tool use, extract text blocks
          # that appear before the tool_use block (i.e. the commentary)
          MESSAGE=$(jq -sr '
            # Find the last assistant turn
            [.[] | select(.type == "assistant")] | last |
            .message.content |
            # Get text blocks only
            map(select(.type == "text")) |
            map(.text) | join("\n")
          ' < <(grep '"role":"assistant"' "$TRANSCRIPT") 2>/dev/null || true)
        fi

        # Fall back to tool name + input if no text found
        if [[ -z "$MESSAGE" ]]; then
          TOOL_INPUT=$(echo "$INPUT" | jq -r '(.tool_input // .toolInput // "") | tostring | .[:500]')
          MESSAGE="[tool: $TOOL_NAME] $TOOL_INPUT"
        fi
        SOURCE="ada:tool"
        USER_MSG=""
      else
        # Stop hook — log last assistant message + last user message for context
        MESSAGE=$(echo "$INPUT" | jq -r '.last_assistant_message // .lastAssistantMessage // empty')
        TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // .transcriptPath // empty')

        if [[ -z "$MESSAGE" && -n "$TRANSCRIPT" && -f "$TRANSCRIPT" ]]; then
          MESSAGE=$(grep '"role":"assistant"' "$TRANSCRIPT" | jq -sr '
            [.[] | select(.type == "assistant") | select(.message.content | any(.type == "text"))] | last |
            .message.content | map(select(.type == "text")) | map(.text) | join("\n")
          ' 2>/dev/null || true)
        fi

        # Get last user message so narrator knows what josh said
        USER_MSG=""
        if [[ -n "$TRANSCRIPT" && -f "$TRANSCRIPT" ]]; then
          USER_MSG=$(grep '"role":"human"' "$TRANSCRIPT" | jq -sr '
            [.[] | select(.type == "human")] | last |
            .message.content | map(select(.type == "text")) | map(.text) | join("\n")
          ' 2>/dev/null || true)
          USER_MSG="''${USER_MSG:0:500}"
        fi
        SOURCE="ada:response"
      fi

      if [[ -z "$MESSAGE" ]]; then
        exit 0
      fi

      # Truncate to keep log entries reasonable
      MESSAGE="''${MESSAGE:0:2000}"

      # Append JSONL entry with source and optional user context
      if [[ -n "$USER_MSG" ]]; then
        jq -nc --arg ts "$(date -Iseconds)" --arg src "$SOURCE" \
          --arg msg "$MESSAGE" --arg user "$USER_MSG" \
          '{ts: $ts, source: $src, user: $user, message: $msg}' >> "$LOGFILE"
      else
        jq -nc --arg ts "$(date -Iseconds)" --arg src "$SOURCE" \
          --arg msg "$MESSAGE" \
          '{ts: $ts, source: $src, message: $msg}' >> "$LOGFILE"
      fi
    '';

    meta.description = "Claude Code hook — append work log entry (Stop + PostToolUse)";
  };

  # Cron script: read log, summarize via Haiku, speak via TTS, truncate
  narrator = writeShellApplication {
    name = "ada-narrator";

    runtimeInputs = [ curl jq gnused gnugrep coreutils kokoro-tts ];

    text = ''
      # ada-narrator: Cron job for periodic TTS narration
      # Reads work log, summarizes via Haiku, speaks via Kokoro TTS,
      # then truncates log keeping the last 3 entries for context.

      export PULSE_SERVER="''${PULSE_SERVER:-tcp:127.0.0.1:4713}"

      LOGDIR="${logDir}"
      LOGFILE="${logFile}"
      LOCKFILE="$LOGDIR/narrator.lock"

      mkdir -p "$LOGDIR"

      # Exit if no log file or empty
      if [[ ! -s "$LOGFILE" ]]; then
        exit 0
      fi

      # Simple file lock to avoid racing with the hook
      exec 9>"$LOCKFILE"
      if ! flock -n 9; then
        exit 0
      fi

      ENTRY_COUNT=$(wc -l < "$LOGFILE")

      # Need at least 1 entry
      if [[ "$ENTRY_COUNT" -eq 0 ]]; then
        exit 0
      fi

      # Read all worklog entries
      ENTRIES=$(cat "$LOGFILE")

      # Safety cap — if the log has grown huge, keep only last 50 entries
      if [[ "$ENTRY_COUNT" -gt 50 ]]; then
        ENTRIES=$(echo "$ENTRIES" | tail -50)
      fi

      # Release lock before doing slow work (API + TTS)
      flock -u 9

      # Read API key
      API_KEY_FILE="''${NARRATOR_API_KEY_FILE:-/run/secrets/ada/anthropic-api-key}"
      if [[ ! -f "$API_KEY_FILE" ]]; then
        exit 0
      fi
      ANTHROPIC_API_KEY=$(cat "$API_KEY_FILE")

      # Format worklog entries
      FORMATTED_WORKLOG=$(echo "$ENTRIES" | jq -sr '
        map("[\(.ts)] \(.message[:500])") | join("\n---\n")
      ')

      # Get recent narrations for context (last 5)
      NARRATION_LOG="$LOGDIR/narrator.log"
      PREVIOUS=""
      if [[ -f "$NARRATION_LOG" ]]; then
        PREVIOUS=$(tail -5 "$NARRATION_LOG")
      fi

      # Build the user message with both sections
      USER_MSG="WORKLOG:
$FORMATTED_WORKLOG"

      if [[ -n "$PREVIOUS" ]]; then
        USER_MSG="$USER_MSG

PREVIOUS NARRATIONS:
$PREVIOUS"
      fi

      # Truncate if too long
      USER_MSG="''${USER_MSG:0:6000}"

      MODEL="''${NARRATOR_MODEL:-claude-haiku-4-5-20251001}"
      PROMPT=$(cat "${narratorPrompt}")

      RESPONSE=$(curl -sf https://api.anthropic.com/v1/messages \
        -H "x-api-key: $ANTHROPIC_API_KEY" \
        -H "anthropic-version: 2023-06-01" \
        -H "content-type: application/json" \
        -d "$(jq -n \
          --arg msg "$USER_MSG" \
          --arg model "$MODEL" \
          --arg prompt "$PROMPT" \
          '{
            model: $model,
            max_tokens: 600,
            system: $prompt,
            messages: [{role: "user", content: $msg}]
          }')" 2>/dev/null) || exit 0

      RAW_TEXT=$(echo "$RESPONSE" | jq -r '.content[0].text // empty')

      if [[ -z "$RAW_TEXT" ]]; then
        exit 0
      fi

      # Extract narration and prune list from Haiku's response.
      # Haiku often wraps JSON in ```json fences despite instructions.
      # Strategy: collapse to one line, strip fence markers, parse.
      CLEAN_TEXT=$(echo "$RAW_TEXT" | tr '\n' ' ' | sed "s/\`\`\`json//g; s/\`\`\`//g")

      NARRATION=$(echo "$CLEAN_TEXT" | jq -r '.narration // empty' 2>/dev/null || true)
      PRUNE_LIST=$(echo "$CLEAN_TEXT" | jq -r '.prune[]?' 2>/dev/null || true)

      # If we couldn't parse narration from JSON, skip this cycle rather than
      # speaking raw JSON/timestamps to the audience
      if [[ -z "$NARRATION" ]]; then
        echo "[$(date -Iseconds)] PARSE_FAIL: $RAW_TEXT" >> "$LOGDIR/narrator.log"
        exit 0
      fi

      # Prune worklog entries that Haiku marked as stale
      if [[ -n "$PRUNE_LIST" ]]; then
        # Build jq filter to remove pruned timestamps
        PRUNE_JSON=$(echo "$PRUNE_LIST" | jq -Rsc 'split("\n") | map(select(. != ""))')
        exec 9>"$LOCKFILE"
        flock 9
        jq -c "select(.ts as \$t | $PRUNE_JSON | index(\$t) | not)" "$LOGFILE" > "$LOGFILE.tmp" 2>/dev/null \
          || cp "$LOGFILE" "$LOGFILE.tmp"
        mv "$LOGFILE.tmp" "$LOGFILE"
        flock -u 9
      fi

      # Log what was narrated
      echo "[$(date -Iseconds)] $NARRATION" >> "$LOGDIR/narrator.log"

      # Speak it
      echo "$NARRATION" | kokoro-tts --play
    '';

    meta.description = "Periodic TTS narrator — summarize work log via Haiku + Kokoro";
  };

  interrupt = writeShellApplication {
    name = "ada-narrator-interrupt";

    runtimeInputs = [ procps coreutils ];

    text = ''
      # ada-narrator-interrupt: Kill running TTS playback
      pkill -u "$(id -u)" -f "kokoro-tts" 2>/dev/null || true
      pkill -u "$(id -u)" -f "paplay" 2>/dev/null || true
    '';

    meta.description = "Interrupt running TTS playback";
  };

in symlinkJoin {
  name = "ada-narrator";
  paths = [ worklog narrator interrupt ];
  meta = {
    description = "Ada narrator: work log hook + periodic TTS summarizer";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
