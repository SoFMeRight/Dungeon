#!/bin/sh
# Copies each source mailbox into folders under one target login, one way and
# duplicate-free, with imapsync. Every value is the caller's: see the CronJob's env.
#   SOURCE_DIR           mounted Secret: one JSON file per mailbox, plus the target password
#   ENTRY_PREFIX         file-name prefix of a mailbox entry; the rest names its folder
#                        (an entry holds HOST, PORT, USERNAME, PASSWORD; empty ones are skipped)
#   TARGET_HOST, TARGET_PORT, TARGET_TLS_NAME, TARGET_USERNAME
#   TARGET_PASSWORD_KEY  file in SOURCE_DIR holding the target login's password
#   FOLDER_PREFIX        target folder the mailboxes land under: <prefix>/<name>
#   EXCLUDE              source folders to leave out (imapsync --exclude regex; may be empty)
#   IMAPSYNC_OPTIONS     further imapsync options, space-separated
set -eu
: "${SOURCE_DIR:?}" "${ENTRY_PREFIX:?}" "${TARGET_HOST:?}" "${TARGET_PORT:?}" "${TARGET_TLS_NAME:?}" \
  "${TARGET_USERNAME:?}" "${TARGET_PASSWORD_KEY:?}" "${FOLDER_PREFIX:?}"
umask 077
field() { K="$2" perl -MJSON::PP -0777 -ne 'print decode_json($_)->{$ENV{K}} // ""' "$1"; }
printf '%s' "$(cat "$SOURCE_DIR/$TARGET_PASSWORD_KEY")" > /tmp/pass2

failed=""
for f in "$SOURCE_DIR/$ENTRY_PREFIX"*; do
  [ -e "$f" ] || { echo "no $ENTRY_PREFIX* entries"; break; }
  name=${f##*/"$ENTRY_PREFIX"}
  login=$(field "$f" USERNAME)
  printf '%s' "$(field "$f" PASSWORD)" > /tmp/pass1
  if [ -z "$login" ] || [ ! -s /tmp/pass1 ]; then echo "== $name: not filled in yet, skipped"; continue; fi
  echo "== $name"
  set -- --host1 "$(field "$f" HOST)" --port1 "$(field "$f" PORT)" --ssl1 --sslargs1 SSL_verify_mode=1 \
    --user1 "$login" --passfile1 /tmp/pass1 \
    --host2 "$TARGET_HOST" --port2 "$TARGET_PORT" --ssl2 --sslargs2 SSL_verify_mode=1 \
    --sslargs2 "SSL_verifycn_name=$TARGET_TLS_NAME" --sslargs2 "SSL_hostname=$TARGET_TLS_NAME" \
    --user2 "$TARGET_USERNAME" --passfile2 /tmp/pass2 \
    --subfolder2 "$FOLDER_PREFIX/$name" --nolog --noreleasecheck --tmpdir /tmp
  [ -z "${EXCLUDE:-}" ] || set -- "$@" --exclude "$EXCLUDE"
  # shellcheck disable=SC2086 # options are space-separated by design
  imapsync "$@" ${IMAPSYNC_OPTIONS:-} || failed="$failed $name"
  rm -f /tmp/pass1
done
rm -f /tmp/pass2
[ -z "$failed" ] || { echo "failed:$failed"; exit 1; }
