{ lib
, writeShellApplication
, writeTextFile
, curl
, jq
, procps
, coreutils
, kokoro-tts
, symlinkJoin
}:

let
  # The narrator personality prompt
  narratorPrompt = writeTextFile {
    name = "narrator-prompt.txt";
    text = ''
      You are a witty narrator commentating a live coding session. Your output
      goes directly to a text-to-speech engine and will be spoken aloud — write
      exactly what should be said, nothing else.

      Describe what just happened in 1-2 short sentences. Be concise, casual,
      occasionally sassy. The audience is listening, not reading.

      If there's a diff or code change, describe what changed in plain English.
      If there's a plan or bullet list, summarize the gist. If there's an error,
      react naturally. Don't read anything back verbatim — add your own color.

      CRITICAL: Your output is fed directly to TTS. Never use markdown, asterisks,
      backticks, bullet points, numbered lists, or any formatting. No special
      characters. Just plain speakable sentences.
    '';
  };

  narrator = writeShellApplication {
    name = "ada-narrator";

    runtimeInputs = [ curl jq coreutils kokoro-tts ];

    text = ''
      # ada-narrator: Claude Code Stop hook
      # Reads hook JSON from stdin, uses lastAssistantMessage or falls back
      # to transcript parsing, calls Haiku for commentary, speaks via TTS

      # Route audio to josh's PipeWire via PulseAudio TCP (unless already set)
      export PULSE_SERVER="''${PULSE_SERVER:-tcp:127.0.0.1:4713}"

      INPUT=$(cat)

      # Debug: dump stdin for troubleshooting
      LOGDIR="''${XDG_STATE_HOME:-$HOME/.local/state}/ada-narrator"
      mkdir -p "$LOGDIR"
      echo "[$(date -Iseconds)] stdin: $INPUT" >> "$LOGDIR/debug.log"

      # Don't narrate if stop hook is already active (prevents loops)
      # Handle both snake_case and camelCase field names
      STOP_ACTIVE=$(echo "$INPUT" | jq -r '(.stop_hook_active // .stopHookActive // false) | tostring')
      if [[ "$STOP_ACTIVE" == "true" ]]; then
        exit 0
      fi

      # Try lastAssistantMessage first (direct from Claude Code), then
      # last_assistant_message, then fall back to transcript parsing
      MESSAGE=$(echo "$INPUT" | jq -r '.last_assistant_message // .lastAssistantMessage // empty')

      if [[ -z "$MESSAGE" ]]; then
        # Fall back to transcript JSONL parsing
        # Each assistant turn is split across multiple JSONL lines (text, tool_use, thinking).
        # We need the last line that actually has text content, not just tool calls.
        TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // .transcriptPath // empty')
        if [[ -n "$TRANSCRIPT" && -f "$TRANSCRIPT" ]]; then
          MESSAGE=$(grep '"role":"assistant"' "$TRANSCRIPT" | jq -sr '
            [.[] | select(.type == "assistant") | select(.message.content | any(.type == "text"))] | last |
            .message.content | map(select(.type == "text")) | map(.text) | join("\n")
          ' 2>/dev/null || true)
        fi
      fi

      # Skip if no message
      if [[ -z "$MESSAGE" ]]; then
        echo "[$(date -Iseconds)] no message found, exiting" >> "$LOGDIR/debug.log"
        exit 0
      fi

      # Read API key from sops secret
      API_KEY_FILE="''${NARRATOR_API_KEY_FILE:-/run/secrets/ada/anthropic-api-key}"
      if [[ ! -f "$API_KEY_FILE" ]]; then
        exit 0
      fi
      ANTHROPIC_API_KEY=$(cat "$API_KEY_FILE")

      # Truncate very long messages to save tokens
      MESSAGE="''${MESSAGE:0:4000}"

      # Call narrator model
      MODEL="''${NARRATOR_MODEL:-claude-haiku-4-5-20251001}"
      PROMPT=$(cat "${narratorPrompt}")

      RESPONSE=$(curl -sf https://api.anthropic.com/v1/messages \
        -H "x-api-key: $ANTHROPIC_API_KEY" \
        -H "anthropic-version: 2023-06-01" \
        -H "content-type: application/json" \
        -d "$(jq -n \
          --arg msg "$MESSAGE" \
          --arg model "$MODEL" \
          --arg prompt "$PROMPT" \
          '{
            model: $model,
            max_tokens: 150,
            system: $prompt,
            messages: [{role: "user", content: $msg}]
          }')" 2>/dev/null) || exit 0

      SUMMARY=$(echo "$RESPONSE" | jq -r '.content[0].text // empty')

      if [[ -z "$SUMMARY" ]]; then
        exit 0
      fi

      # Write to a log for debugging
      LOGDIR="''${XDG_STATE_HOME:-$HOME/.local/state}/ada-narrator"
      mkdir -p "$LOGDIR"
      echo "[$(date -Iseconds)] $SUMMARY" >> "$LOGDIR/narrator.log"

      # Speak it — kokoro-tts generates wav, pw-play sends to PipeWire
      echo "$SUMMARY" | kokoro-tts --play
    '';

    meta = {
      description = "Claude Code narrator hook — Haiku commentary + Kokoro TTS";
    };
  };

  interrupt = writeShellApplication {
    name = "ada-narrator-interrupt";

    runtimeInputs = [ procps coreutils ];

    text = ''
      # ada-narrator-interrupt: Claude Code UserPromptSubmit hook
      # Kills any running TTS playback so the narrator doesn't talk over the user

      # Kill narrator pipeline: wrapper, python TTS, and audio playback
      # Use pkill with negation to avoid killing ourselves (ada-narrator-interrupt
      # matches the "ada-narrator" pattern)
      pkill -u "$(id -u)" -f "kokoro-tts" 2>/dev/null || true
      pkill -u "$(id -u)" -f "paplay" 2>/dev/null || true
      pkill -u "$(id -u)" -f "bin/ada-narrator$" 2>/dev/null || true
    '';

    meta = {
      description = "Interrupt running TTS playback on user input";
    };
  };

in symlinkJoin {
  name = "ada-narrator";
  paths = [ narrator interrupt ];
  meta = {
    description = "Claude Code narrator: Haiku commentary + Kokoro TTS playback";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
