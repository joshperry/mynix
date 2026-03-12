{ lib
, writeShellApplication
, writeTextFile
, curl
, jq
, pipewire
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
      You are a witty narrator commentating a live coding session. Your audience
      is listening, not reading — they can't see the terminal. Describe what just
      happened in 1-2 short sentences. Be concise, casual, occasionally sassy.

      If there's a diff or code change, describe what changed and why in plain
      English. If there's a plan or bullet list, summarize the gist. If there's
      an error, react naturally. If it's a direct text response, don't read it
      back verbatim — add your own color and character.

      Never quote code literally. Never use markdown. Never use backticks or
      special characters. Just speak naturally, like you're the play-by-play
      announcer for a pair programming stream.

      Keep it to 1-2 sentences max. Be entertaining but informative.
    '';
  };

  narrator = writeShellApplication {
    name = "ada-narrator";

    runtimeInputs = [ curl jq coreutils kokoro-tts pipewire ];

    text = ''
      # ada-narrator: Claude Code Stop hook
      # Reads hook JSON from stdin, calls Haiku for commentary, speaks via TTS

      INPUT=$(cat)

      # Don't narrate if stop hook is already active (prevents loops)
      STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
      if [[ "$STOP_ACTIVE" == "true" ]]; then
        exit 0
      fi

      MESSAGE=$(echo "$INPUT" | jq -r '.last_assistant_message // empty')

      # Skip if no message
      if [[ -z "$MESSAGE" ]]; then
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
      pkill -u "$(id -u)" -f "ada-narrator" 2>/dev/null || true
      pkill -u "$(id -u)" -f "kokoro-tts" 2>/dev/null || true
      pkill -u "$(id -u)" -f "pw-play" 2>/dev/null || true
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
