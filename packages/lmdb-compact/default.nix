{
  writeShellApplication,
  lmdb,
  lsof,
  coreutils,
  gnused,
}:

writeShellApplication {
  name = "lmdb-compact";
  runtimeInputs = [
    lmdb
    lsof
    coreutils
    gnused
  ];

  text = ''
    set -euo pipefail

    usage() {
      cat <<'USAGE'
    Usage: sudo lmdb-compact [--no-backup] <lmdb-environment-directory>

    Compact an offline LMDB environment with mdb_copy -c, verify its logical
    contents, then replace the environment directory. The destination is staged
    beside the source, so the compacted database needs temporary free space.

    By default the original is retained as <environment>.precompact.<UTC timestamp>.
    --no-backup removes the original only after the compact copy verifies.
    USAGE
    }

    die() {
      echo "lmdb-compact: $*" >&2
      exit 1
    }

    no_backup=0
    case "''${1:-}" in
      -h|--help)
        usage
        exit 0
        ;;
      --no-backup)
        no_backup=1
        shift
        ;;
    esac

    [[ $# -eq 1 ]] || { usage >&2; exit 2; }
    [[ $EUID -eq 0 ]] || die "run as root (sudo) to check open files and preserve ownership"

    db=$(realpath -e -- "$1") || die "cannot resolve LMDB directory: $1"
    [[ -d "$db" ]] || die "not a directory: $db"
    [[ -f "$db/data.mdb" ]] || die "missing $db/data.mdb"
    [[ "$db" != / ]] || die "refusing to operate on /"

    parent=$(dirname -- "$db")
    name=$(basename -- "$db")
    open_pids=$(lsof -t "$db/data.mdb" "$db/lock.mdb" 2>/dev/null || true)
    [[ -z "$open_pids" ]] || die "LMDB files are open by PID(s): $open_pids; stop Garage and retry"

    echo "Environment: $db"
    df -h -- "$parent"
    if (( no_backup )); then
      confirmation="COMPACT WITHOUT BACKUP $name"
      echo "WARNING: the original environment will be removed after verification."
    else
      confirmation="COMPACT $name"
    fi
    read -r -p "Confirm Garage is stopped; type '$confirmation': " answer
    [[ "$answer" == "$confirmation" ]] || die "confirmation did not match"

    tmp=$(mktemp -d --tmpdir="$parent" ".''${name}.compact.XXXXXXXX")
    source_removed=0
    cleanup() {
      if [[ -n "''${tmp:-}" && -d "$tmp" ]]; then
        if (( source_removed )); then
          echo "lmdb-compact: preserving verified compact copy at $tmp" >&2
        else
          rm -rf -- "$tmp"
        fi
      fi
    }
    trap cleanup EXIT

    echo "Compacting into temporary directory: $tmp"
    mdb_copy -c "$db" "$tmp"

    echo "Verifying logical database contents (this may take a while)..."
    # mdb_dump headers include environment-specific mapsize/mapaddr/maxreaders;
    # strip those fields so the digest compares database records, not map settings.
    source_hash=$(mdb_dump -a "$db" | sed -E '/^(mapsize|mapaddr|maxreaders)=/d' | sha256sum | cut -d' ' -f1)
    compact_hash=$(mdb_dump -a "$tmp" | sed -E '/^(mapsize|mapaddr|maxreaders)=/d' | sha256sum | cut -d' ' -f1)
    [[ "$source_hash" == "$compact_hash" ]] || die "logical content hashes differ; original left untouched"
    echo "Verified identical logical contents: $source_hash"
    du -h -- "$db/data.mdb" "$tmp/data.mdb"

    chown --reference="$db" "$tmp"
    chmod --reference="$db" "$tmp"
    chown --reference="$db/data.mdb" "$tmp/data.mdb"
    chmod --reference="$db/data.mdb" "$tmp/data.mdb"

    if (( no_backup )); then
      echo "Removing original environment (no-backup mode)."
      rm -rf -- "$db"
      source_removed=1
      if ! mv -- "$tmp" "$db"; then
        die "replacement failed; verified compact copy remains at $tmp"
      fi
    else
      backup="$db.precompact.$(date -u +%Y%m%dT%H%M%SZ)"
      [[ ! -e "$backup" ]] || die "backup path already exists: $backup"
      mv -- "$db" "$backup"
      if ! mv -- "$tmp" "$db"; then
        mv -- "$backup" "$db" || die "replacement and automatic rollback failed; original is at $backup"
        die "replacement failed; original restored"
      fi
      echo "Original retained at: $backup"
    fi

    tmp=""
    sync
    echo "Compaction complete: $db"
  '';

  meta = {
    description = "Safely compact an offline LMDB environment and verify its contents";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
