#!/bin/bash
#
# Generates fake AppImages for the test suite.
#
# A fixture has to be a real ELF, not a shell script: the AppImage type magic
# lives at offset 8, which inside a "#!" script falls in the middle of the
# interpreter path. A freshly linked ELF has 00 00 00 there (EI_ABIVERSION plus
# padding), which is exactly where real AppImages stamp their magic, so patching
# it is faithful rather than a trick.
#
# The stub execs an adjacent behaviour script by absolute path, so the fixture
# keeps working after the install command moves it into ~/Applications.
#
# Usage: make_appimage <path> [--name N] [--categories C] [--wmclass W]
#                             [--icon-key K] [--type 1|2] [--no-icon]
#                             [--no-desktop] [--extra-desktop] [--icon-128]
#                             [--mime M] [--comment C] [--refuse-extract]

# A 1x1 PNG (no recognised hicolor size, so it lands in the 256x256 fallback) and
# a real 128x128 one, for asserting size-aware icon filing.
FIXTURE_ICON_1PX='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='
FIXTURE_ICON_128PX='iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAIAAABMXPacAAAAyElEQVR42u3RQQ0AAAjEsJOIMIQhCxnwaDIFa6pHh8UCAAAEAIAAABAAAAIAQAAACAAAAQAgAAAEAIAAABAAAAIAQAAACAAAAQAgAAAEAIAAABAAAAIAQAAACAAAAQAgAAAEAIAAABAAAAIAQAAACAAAAQAAwAUAAAQAgAAAEAAAAgBAAAAIAAABACAAAAQAgAAAEAAAAgBAAAAIAAABACAAAAQAgAAAEAAAAgBAAAAIAAABACAAAAQAgAAAEAAAAgBAAAAIwIcWCz0GKK/Rr3UAAAAASUVORK5CYII='

make_appimage() {
  local path="$1"; shift
  local name="Fixture App" categories="Utility;" wmclass="fixture-app"
  local icon_key="fixture-icon" type=2 want_icon=1 want_desktop=1 extra_desktop=0
  local icon_b64="$FIXTURE_ICON_1PX" mime="" comment="" refuse_extract=0

  while (($#)); do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      --categories) categories="$2"; shift 2 ;;
      --wmclass) wmclass="$2"; shift 2 ;;
      --icon-key) icon_key="$2"; shift 2 ;;
      --type) type="$2"; shift 2 ;;
      --no-icon) want_icon=0; shift ;;
      --no-desktop) want_desktop=0; shift ;;
      --extra-desktop) extra_desktop=1; shift ;;
      --icon-128) icon_b64="$FIXTURE_ICON_128PX"; shift ;;
      --mime) mime="$2"; shift 2 ;;
      --comment) comment="$2"; shift 2 ;;
      --refuse-extract) refuse_extract=1; shift ;;
      *) echo "make_appimage: unknown option $1" >&2; return 1 ;;
    esac
  done

  mkdir -p "$(dirname "$path")"
  local behaviour="$path.behaviour"

  {
    echo '#!/bin/bash'
    echo 'if [[ ${1-} == "--appimage-extract" ]]; then'
    if ((type == 1)) || ((refuse_extract)); then
      # Type-1 bundles have no --appimage-extract at all; --refuse-extract fakes
      # a type-2 bundle that cannot be extracted, as happens without FUSE.
      echo '  echo "unknown option" >&2; exit 1'
    else
      echo '  mkdir -p squashfs-root/usr/share/icons/hicolor/256x256/apps'
      if ((want_desktop)); then
        printf '  cat >squashfs-root/%s.desktop <<'"'"'DESK'"'"'\n' "$icon_key"
        echo '[Desktop Entry]'
        printf 'Name=%s\n' "$name"
        printf 'Exec=AppRun\n'
        [[ -n $categories ]] && printf 'Categories=%s\n' "$categories"
        [[ -n $mime ]] && printf 'MimeType=%s\n' "$mime"
        [[ -n $comment ]] && printf 'Comment=%s\n' "$comment"
        [[ -n $wmclass ]] && printf 'StartupWMClass=%s\n' "$wmclass"
        printf 'Icon=%s\n' "$icon_key"
        echo 'Type=Application'
        echo 'DESK'
      fi
      if ((extra_desktop)); then
        # A second top-level entry, to prove selection is deterministic.
        printf '  printf "[Desktop Entry]\\nName=Zzz Decoy\\n" >squashfs-root/zzz-decoy.desktop\n'
      fi
      if ((want_icon)); then
        printf '  printf %s | base64 -d >squashfs-root/usr/share/icons/hicolor/256x256/apps/%s.png\n' \
          "'$icon_b64'" "$icon_key"
        # .DirIcon as a symlink, the way real bundles ship it.
        printf '  ln -sf usr/share/icons/hicolor/256x256/apps/%s.png squashfs-root/.DirIcon\n' "$icon_key"
      fi
    fi
    echo '  exit 0'
    echo 'fi'
    echo 'printf "%s\n" "$*" >>"${LAUNCH_LOG:-/dev/null}"'
  } >"$behaviour"
  chmod +x "$behaviour"

  # The behaviour path lands inside a C string literal, so escape backslash and
  # double quote for C. A fixture path containing " or ` is exactly what the
  # escaping round-trip tests need, so the generator has to survive them too.
  local c_path=${behaviour//\\/\\\\}
  c_path=${c_path//\"/\\\"}

  cc -O0 -w -o "$path" -DBEHAVIOUR="\"$c_path\"" -x c - <<'CSRC'
#include <unistd.h>
int main(int argc, char **argv) {
  char *args[64];
  int i;
  args[0] = "bash";
  args[1] = BEHAVIOUR;
  for (i = 1; i < argc && i < 60; i++) args[i + 1] = argv[i];
  args[i + 1] = 0;
  execv("/bin/bash", args);
  return 127;
}
CSRC

  # Stamp the AppImage magic into the ELF e_ident padding at offset 8.
  if ((type == 1)); then
    printf '\x41\x49\x01' | dd of="$path" bs=1 seek=8 conv=notrunc status=none
  else
    printf '\x41\x49\x02' | dd of="$path" bs=1 seek=8 conv=notrunc status=none
  fi
  chmod +x "$path"
}

# A file that is not an AppImage at all: correct ELF header, no magic.
make_not_an_appimage() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cc -O0 -w -o "$path" -x c - <<'CSRC'
int main(void) { return 0; }
CSRC
  chmod +x "$path"
}
