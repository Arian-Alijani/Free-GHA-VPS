
#!/usr/bin/env bash
# ============================================================
# Free GHA VPS - Configure Chrome Remote Desktop
# First run: Google auth code + PIN
# Returning run: saved credentials + PIN
# ============================================================

set -Eeuo pipefail

PIN="${1:-${CRD_PIN:-}}"
AUTH_CODE="${AUTH_CODE:-${2:-}}"

CRD_DIR="$HOME/.config/google-chrome-remote-desktop"
START_HOST="/opt/google/chrome-remote-desktop/start-host"
HOST_BIN="/opt/google/chrome-remote-desktop/chrome-remote-desktop"
HOST_NAME="Free-GHA-VPS"
REDIRECT_URL="https://remotedesktop.google.com/_/oauthredirect"

# Validate PIN
if [[ -z "$PIN" ]]; then
  echo "ERROR: CRD PIN is missing."
  exit 1
fi

# Chrome Remote Desktop requires a numeric PIN of at least 6 digits.
if [[ ! "$PIN" =~ ^[0-9]{6,}$ ]]; then
  echo "ERROR: PIN must contain at least 6 digits (numbers only)."
  exit 1
fi

# Mask temporary Google authorization code in GitHub Actions logs.
if [[ -n "$AUTH_CODE" ]]; then
  echo "::add-mask::$AUTH_CODE"
fi

mkdir -p "$CRD_DIR"
chmod 700 "$CRD_DIR"

printf '%s\n' "$PIN" > "$CRD_DIR/pin"
chmod 600 "$CRD_DIR/pin"

# Check required binary
if [[ ! -x "$HOST_BIN" ]]; then
  echo "ERROR: Chrome Remote Desktop host binary not found:"
  echo "$HOST_BIN"
  exit 1
fi

# Returning user: use saved credentials
if [[ -s "$CRD_DIR/Credentials" ]]; then
  echo "Saved CRD credentials found."
  echo "Starting existing Chrome Remote Desktop host..."

  "$HOST_BIN" --stop >/dev/null 2>&1 || true
  sleep 2

  DISPLAY=:0 nohup "$HOST_BIN" --start \
    </dev/null >/tmp/crd-start.log 2>&1 &

  for _ in $(seq 1 30); do
    if pgrep -u "$(id -u)" -f 'chrome-remote-desktop' >/dev/null 2>&1; then
      echo "Chrome Remote Desktop start command launched."
      echo "Connect at: https://remotedesktop.google.com/access"
      exit 0
    fi
    sleep 2
  done

  echo "ERROR: CRD did not appear to start."
  echo "Check /tmp/crd-start.log"
  exit 1
fi

# First-time setup requires Google's authorization code
if [[ -z "$AUTH_CODE" ]]; then
  echo "ERROR: First-time setup requires Google's auth code."
  echo
  echo "1. Open https://remotedesktop.google.com/headless"
  echo "2. Click Begin, then Authorize."
  echo "3. Choose Debian Linux."
  echo "4. Copy only the value after --code=."
  echo "5. Run the workflow again and enter it in auth_code."
  echo
  echo "Do not share the code or paste the complete command."
  exit 1
fi

if [[ ! -x "$START_HOST" ]]; then
  echo "ERROR: start-host utility not found:"
  echo "$START_HOST"
  exit 1
fi

echo "Starting first-time Chrome Remote Desktop authorization..."

# Run Google's documented headless setup command.
set +e
DISPLAY= "$START_HOST" \
  --code="$AUTH_CODE" \
  --redirect-url="$REDIRECT_URL" \
  --name="$HOST_NAME" \
  --pin="$PIN" \
  >/tmp/crd-setup.log 2>&1
SETUP_STATUS=$?
set -e

unset AUTH_CODE

if [[ $SETUP_STATUS -ne 0 ]]; then
  echo "ERROR: CRD authorization/setup failed."
  echo "The authorization code may have expired or already been used."
  echo "Generate a fresh code at:"
  echo "https://remotedesktop.google.com/headless"
  echo "Check /tmp/crd-setup.log for diagnostics."
  exit "$SETUP_STATUS"
fi

# Verify credentials were created
for _ in $(seq 1 30); do
  if [[ -s "$CRD_DIR/Credentials" ]]; then
    chmod 600 "$CRD_DIR/Credentials"
    echo "Chrome Remote Desktop authorization completed."
    echo "Connect at: https://remotedesktop.google.com/access"
    echo "Look for: $HOST_NAME"
    exit 0
  fi
  sleep 2
done

echo "ERROR: Setup returned, but Credentials file was not found."
echo "Check /tmp/crd-setup.log."
exit 1
