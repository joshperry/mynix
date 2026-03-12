{ lib
, python312Packages
, fetchPypi
, fetchurl
, espeak-ng
, writeShellApplication
, pipewire
}:

let
  python = python312Packages;

  dlinfo = python.buildPythonPackage rec {
    pname = "dlinfo";
    version = "2.0.0";
    src = fetchPypi {
      inherit pname version;
      hash = "sha256-iKK8H0E/UL0xRhfhO4ODYTQY3lw0+Y+jt+cYcImpgRc=";
    };
    doCheck = false;
  };

  phonemizer-fork = python.buildPythonPackage rec {
    pname = "phonemizer-fork";
    version = "3.3.2";
    src = fetchPypi {
      pname = "phonemizer_fork";
      inherit version;
      hash = "sha256-EOFp6JSS+fEhCUnbDaANpgbWBikvfQcf6EzMpr4Mzwk=";
    };
    build-system = [ python.setuptools ];
    dependencies = [
      python.attrs
      dlinfo
      python.joblib
      python.segments
      python.typing-extensions
    ];
    doCheck = false;
    # Hard-code path to system espeak-ng shared library
    postPatch = ''
      substituteInPlace phonemizer/backend/espeak/wrapper.py \
        --replace-fail \
          "def _espeak_library():" \
          "def _espeak_library():
          return '${espeak-ng}/lib/libespeak-ng.so'"
    '';
  };

  kokoro-onnx = python.buildPythonPackage rec {
    pname = "kokoro-onnx";
    version = "0.5.0";
    pyproject = true;
    src = fetchPypi {
      pname = "kokoro_onnx";
      inherit version;
      hash = "sha256-W+sV8IXigo7Y1JOffywJ+rhRA6styuoREsF2BYV6wpE=";
    };
    build-system = [ python.hatchling ];
    dependencies = [
      python.onnxruntime
      python.numpy
      python.colorlog
      phonemizer-fork
    ];
    # Drop bundled espeak-ng loader — we use system espeak-ng
    postPatch = ''
      substituteInPlace pyproject.toml \
        --replace-fail '"espeakng-loader>=0.2.4",' ""
    '';
    doCheck = false;
    pythonImportsCheck = [ "kokoro_onnx" ];
  };

  model = fetchurl {
    url = "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v1.0.onnx";
    hash = "sha256-fV347PfUsYeAFaMmhgU/0O6+K8N3I0YIdkzA7zY2psU=";
  };

  voices = fetchurl {
    url = "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/voices-v1.0.bin";
    hash = "sha256-vKYQuDCOjZnzLm/kGX5+wBZ5Jk7+0MrJFA/pwp8fv30=";
  };

  pythonEnv = python.python.withPackages (ps: [
    kokoro-onnx
    ps.soundfile
  ]);

in writeShellApplication {
  name = "kokoro-tts";

  runtimeInputs = [ pythonEnv pipewire ];

  runtimeEnv = {
    PHONEMIZER_ESPEAK_LIBRARY = "${espeak-ng}/lib/libespeak-ng.so";
    ESPEAK_DATA_PATH = "${espeak-ng}/share/espeak-ng-data";
    KOKORO_MODEL = "${model}";
    KOKORO_VOICES = "${voices}";
  };

  text = ''
    # kokoro-tts: text-to-speech via kokoro-onnx
    # Usage: echo "Hello" | kokoro-tts          # wav to stdout
    #        echo "Hello" | kokoro-tts --play    # play via PipeWire
    #        kokoro-tts --play "Hello"           # text as argument

    VOICE="''${KOKORO_VOICE:-af_heart}"
    SPEED="''${KOKORO_SPEED:-1.0}"
    PLAY=false
    TEXT=""

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --play) PLAY=true; shift ;;
        --voice) VOICE="$2"; shift 2 ;;
        --speed) SPEED="$2"; shift 2 ;;
        *) TEXT="$1"; shift ;;
      esac
    done

    if [[ -z "$TEXT" ]]; then
      TEXT="$(cat)"
    fi

    if [[ -z "$TEXT" ]]; then
      exit 0
    fi

    if [[ "$PLAY" == "true" ]]; then
      python3 -c "
import sys, os, io, soundfile as sf
from kokoro_onnx import Kokoro
kokoro = Kokoro(os.environ['KOKORO_MODEL'], os.environ['KOKORO_VOICES'])
samples, sr = kokoro.create(sys.argv[1], text=sys.argv[2], speed=float(sys.argv[3]))
buf = io.BytesIO()
sf.write(buf, samples, sr, format='WAV', subtype='PCM_16')
sys.stdout.buffer.write(buf.getvalue())
" "$VOICE" "$TEXT" "$SPEED" | pw-play -
    else
      python3 -c "
import sys, os, io, soundfile as sf
from kokoro_onnx import Kokoro
kokoro = Kokoro(os.environ['KOKORO_MODEL'], os.environ['KOKORO_VOICES'])
samples, sr = kokoro.create(sys.argv[1], text=sys.argv[2], speed=float(sys.argv[3]))
buf = io.BytesIO()
sf.write(buf, samples, sr, format='WAV', subtype='PCM_16')
sys.stdout.buffer.write(buf.getvalue())
" "$VOICE" "$TEXT" "$SPEED"
    fi
  '';

  meta = {
    description = "Kokoro TTS — text-to-speech via kokoro-onnx";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
  };
}
