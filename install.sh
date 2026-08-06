#!/bin/bash

# Function to display messages
function info {
  echo -e "\033[1;34m[INFO]\033[0m $1"
}

function success {
  echo -e "\033[1;32m[SUCCESS]\033[0m $1"
}

function error {
  echo -e "\033[1;31m[ERROR]\033[0m $1"
}

# Function to check if nvm is installed and sourced
function check_nvm {
  if [ -s "$HOME/.nvm/nvm.sh" ]; then
    # Load nvm if it exists in the typical location
    source "$HOME/.nvm/nvm.sh"
  fi

  if command -v nvm >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# Detect the Ruby interpreter Open OnDemand's Passenger uses to boot the app
# (its `passenger_ruby`). The dashboard must be bundled for THIS Ruby's ABI, not
# whatever Ruby is on your shell PATH: the PUN starts with a scrubbed environment
# and never sources your shell rc, so editing rc files cannot change its Ruby.
# Honors overrides (see the "Determine which Ruby to build for" section):
#   PUN_RUBY=/path/to/ruby   force a specific interpreter
# Prints the interpreter path, or nothing if it cannot be determined.
function detect_pun_ruby {
  if [ -n "$PUN_RUBY" ]; then echo "$PUN_RUBY"; return; fi

  # passenger_ruby may live in nginx_stage.yml or any drop-in; last one wins.
  local cfg line found=""
  for cfg in /etc/ood/config/nginx_stage.yml /etc/ood/config/nginx_stage.d/*.yml; do
    [ -f "$cfg" ] || continue
    line=$(grep -E '^[[:space:]]*passenger_ruby[[:space:]]*:' "$cfg" 2>/dev/null | tail -n1)
    [ -n "$line" ] && found=$(echo "$line" | sed -E "s/^[[:space:]]*passenger_ruby[[:space:]]*:[[:space:]]*//; s/^['\"]//; s/['\"][[:space:]]*\$//; s/[[:space:]]*\$//")
  done
  if [ -n "$found" ]; then echo "$found"; return; fi

  # Unset -> Passenger falls back to its default Ruby, which for the OOD-packaged
  # nginx/Passenger is an OOD-bundled Ruby, not the system one. Prefer those, then
  # the system Ruby. Never return an rbenv shim.
  local cand
  for cand in /opt/ood/nginx_stage/bin/ruby \
              /opt/rh/ondemand/root/usr/bin/ruby \
              /opt/ood/ondemand/root/usr/bin/ruby \
              /usr/bin/ruby /bin/ruby; do
    [ -x "$cand" ] && { echo "$cand"; return; }
  done
}

# True when running on the Open OnDemand web node (where the PUN runs). Any one
# of the OnDemand runtime markers is sufficient. Used to confirm that Ruby/
# passenger_ruby detection is reliable — a login or compute node can carry a
# different Ruby than the PUN.
function on_ood_host {
  [ -d /etc/ood/config ]            && return 0
  [ -d /opt/rh/ondemand ]           && return 0
  [ -d /opt/ood ]                   && return 0
  command -v nginx_stage >/dev/null 2>&1 && return 0
  return 1
}

# Upstream repository. Override REPO_SLUG to install from a fork.
REPO_SLUG="${REPO_SLUG:-PurdueRCAC/OOD-Dashboard}"
REPO_HOST="${REPO_HOST:-github.com}"
REPO_URL="https://${REPO_HOST}/${REPO_SLUG}"
REPO_SSH_URL="git@${REPO_HOST}:${REPO_SLUG}.git"

# Hostname used to build the "you can reach it here" URL at the end. Falls back
# to this host's FQDN, which is correct when running on the OOD web node.
OOD_HOST="${OOD_HOST:-$(hostname -f 2>/dev/null || hostname)}"

# Check whether we are already inside a checkout of this repository, in which
# case we install in place rather than cloning again.
USE_CURRENT_DIR=false

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  REMOTE_URL=$(git config --get remote.origin.url)
  case "$REMOTE_URL" in
    *"${REPO_SLUG}"*) USE_CURRENT_DIR=true ;;
  esac
fi

if $USE_CURRENT_DIR; then
  DASHBOARD_DIR=$(pwd)
  FOLDER_NAME=$(basename "$DASHBOARD_DIR")
  info "Detected script is running from a $REPO_SLUG checkout. Using current directory: $DASHBOARD_DIR"
else
  # Define the base directory
  BASE_DIR="$HOME/ondemand/dev"

  # Prompt the user for the folder name within the base directory
  echo "The dashboard will be installed within the $BASE_DIR directory."
  read -p "Enter the folder name where you want to install the dashboard [default: dashboard]: " FOLDER_NAME

  # Use "dashboard" as the default folder name if the user didn't specify one
  FOLDER_NAME=${FOLDER_NAME:-dashboard}

  # Define the full installation directory path
  DASHBOARD_DIR="$BASE_DIR/$FOLDER_NAME"

  # Check if the repository folder already exists
  if [ -d "$DASHBOARD_DIR" ]; then
    read -p "The directory $DASHBOARD_DIR already exists. Do you want to overwrite it? (yes/no) [default: no]: " overwrite
    overwrite=${overwrite:-no}
    if [[ "$overwrite" == "yes" || "$overwrite" == "y" ]]; then
      rm -rf "$DASHBOARD_DIR"
      info "Existing directory $DASHBOARD_DIR removed."
    else
      success "Skipping cloning as the directory $DASHBOARD_DIR already exists."
      exit 0
    fi
  fi

  # Clone the repository
  info "Cloning the repository into $DASHBOARD_DIR..."
  
  # Prompt user to choose between HTTPS or SSH
  read -p "Do you want to clone using SSH? (yes/no): " use_ssh

  if [ "$use_ssh" == "yes" ]; then
    git clone "$REPO_SSH_URL" "$DASHBOARD_DIR" >/dev/null 2>&1
  else
    git clone "$REPO_URL" "$DASHBOARD_DIR" >/dev/null 2>&1
  fi

  if [ $? -eq 0 ]; then
    success "Repository cloned successfully into $DASHBOARD_DIR."
  else
    error "Failed to clone the repository. Please check your network connection or the repository URL."
    exit 1
  fi
fi

# Copy system apps from the other-apps directory
OTHER_APPS_DIR="$DASHBOARD_DIR/other-apps"
if [ -d "$OTHER_APPS_DIR" ]; then
  for APP_DIR in "$OTHER_APPS_DIR"/*; do
    if [ -d "$APP_DIR" ]; then
      APP_NAME=$(basename "$APP_DIR")
      DEST_DIR="$HOME/ondemand/dev/$APP_NAME"
      if [ ! -d "$DEST_DIR" ]; then
        info "Copying system app $APP_NAME to $DEST_DIR..."
        cp -r "$APP_DIR" "$DEST_DIR"
        if [ $? -eq 0 ]; then
          success "System app $APP_NAME copied to $DEST_DIR."
        else
          error "Failed to copy system app $APP_NAME to $DEST_DIR."
        fi
      else
        info "System app $APP_NAME already exists at $DEST_DIR. Skipping copy."
      fi
    fi
  done
else
  info "No other-apps directory found in the repository."
fi

cd "$DASHBOARD_DIR" >/dev/null 2>&1 || { error "Failed to navigate to the directory $DASHBOARD_DIR. Ensure the directory exists and has the correct permissions."; exit 1; }

# 2. Setup the dashboard config environment variables
info "Setting up environment variables..."
if [ -f ".env.local" ]; then
  success ".env.local already exists. Skipping environment setup."
else
  cp .env.local.example .env.local >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    success "Environment variables set up successfully. Please edit the .env.local file with your preferred values."
  else
    error "Failed to create .env.local. Please check if .env.local.example exists and you have the correct permissions."
    exit 1
  fi
fi

# 3. Install Ruby dependencies
info "Checking Ruby dependencies..."

# Confirm this is the Open OnDemand web node before touching Ruby. The app must
# be bundled for the PUN's Ruby, and detection of it (below) is only reliable
# here; a login or compute node can carry a different Ruby than the PUN. Building
# on a node that shares $HOME with the web node still works, but only if you
# target the PUN's Ruby explicitly (PUN_RUBY_ABI / PUN_RUBY).
if on_ood_host; then
  success "Open OnDemand host detected — Ruby detection is reliable here."
elif [ "$SKIP_OOD_HOST_CHECK" = "1" ] || [ -n "$PUN_RUBY" ] || [ -n "$PUN_RUBY_ABI" ]; then
  info "Not on the OOD web node, but an explicit Ruby target/override was given — continuing."
else
  error "This does not look like the Open OnDemand web node"
  error "(no /etc/ood/config, /opt/rh/ondemand, /opt/ood, or nginx_stage found)."
  info  "The dashboard must be bundled for the PUN's Ruby, which is detected reliably"
  info  "only on the OOD host. Recommended: run install.sh on the OOD web node -- \$HOME"
  info  "is shared, so the vendored bundle will be picked up by your PUN."
  info  "Otherwise set PUN_RUBY_ABI=X.Y (and optionally TARGET_PLATFORM=...) to target the"
  info  "PUN explicitly, or SKIP_OOD_HOST_CHECK=1 to bypass this check."
  read -p "Continue anyway with best-effort detection? (yes/no) [default: no]: " proceed_non_ood
  proceed_non_ood=${proceed_non_ood:-no}
  case "$proceed_non_ood" in
    yes|y|Y) info "Proceeding with best-effort detection." ;;
    *) error "Aborting. Run on the OOD host, or set PUN_RUBY_ABI / SKIP_OOD_HOST_CHECK."; exit 1 ;;
  esac
fi

# Install rbenv if not installed. rbenv may already be present but absent from
# PATH when the user's shell rc never initialized it, so look in the default
# install location before concluding it is missing.
if ! command -v rbenv >/dev/null && [ -x "$HOME/.rbenv/bin/rbenv" ]; then
  export PATH="$HOME/.rbenv/bin:$PATH"
fi

if command -v rbenv >/dev/null; then
  success "rbenv is already installed."
else
  info "Installing rbenv... (ETA: 3-5 minutes)"
  curl -fsSL https://github.com/rbenv/rbenv-installer/raw/HEAD/bin/rbenv-installer | bash >/dev/null 2>&1
  [ -x "$HOME/.rbenv/bin/rbenv" ] && export PATH="$HOME/.rbenv/bin:$PATH"
  if command -v rbenv >/dev/null; then
    success "rbenv installed successfully."
  else
    error "Failed to install rbenv. Please ensure curl is installed and you have the necessary permissions."
    exit 1
  fi
fi

# Put rbenv's shims ahead of the system Ruby for the rest of this script, so
# `ruby`, `gem`, and `bundle` below resolve to the rbenv Ruby we select rather
# than the system one.
eval "$(rbenv init - bash)" >/dev/null 2>&1

# --- Determine which Ruby to build for --------------------------------------
# The app must be bundled for the ABI of the PUN's passenger_ruby. We build with
# a matching rbenv Ruby (same MAJOR.MINOR): rbenv Rubies ship their own headers
# so the few source-only gems still compile, while precompiled gems are selected
# by platform (not interpreter) and load fine under the PUN's own Ruby.
#
# Overrides (export before running to skip/redirect detection):
#   PUN_RUBY=/path/to/ruby    the interpreter Passenger uses
#   PUN_RUBY_ABI=X.Y          its MAJOR.MINOR (e.g. 3.3), if detection can't find it
#   RBENV_VERSION=X.Y.Z       exact rbenv Ruby to build with
#   BUNDLER_VERSION=X.Y.Z     bundler to use (default: the lockfile's BUNDLED WITH)
#   TARGET_PLATFORM=...        gem platform for precompiled natives (default: this host's)
PUN_RUBY_BIN=$(detect_pun_ruby)

# Probe the PUN's Ruby the way the PUN itself would: with rbenv neutralized.
# This matters because passenger_ruby is often a wrapper that ends in `exec ruby`
# (OOD ships exactly that at /opt/ood/nginx_stage/bin/ruby). By this point in the
# script rbenv is on PATH, so a naive probe resolves that `ruby` to an rbenv shim
# and reports OUR Ruby back to us -- detection then "confirms" whatever we were
# already going to build, the ABI check downstream compares a value against
# itself, and the mismatch only surfaces as Bundler::GemNotFound inside the PUN.
# The PUN starts with a scrubbed environment and never sees rbenv, so strip it.
function pun_ruby_probe {
  local rb="$1"; shift
  local clean_path
  clean_path=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v "^${HOME}/\.rbenv" | paste -sd: -)
  env -u RBENV_VERSION -u RBENV_DIR -u RBENV_HOOK_PATH -u RUBYOPT -u RUBYLIB \
      -u GEM_HOME -u GEM_PATH -u BUNDLE_GEMFILE -u BUNDLE_PATH \
      PATH="$clean_path" "$rb" "$@" 2>/dev/null
}

if [ -n "$PUN_RUBY_ABI" ]; then
  RUBY_MINOR="$PUN_RUBY_ABI"
elif [ -n "$PUN_RUBY_BIN" ] && [ -x "$PUN_RUBY_BIN" ]; then
  RUBY_MINOR=$(pun_ruby_probe "$PUN_RUBY_BIN" -e 'print RbConfig::CONFIG["ruby_version"].split(".")[0,2].join(".")')
  PUN_RUBY_FULL=$(pun_ruby_probe "$PUN_RUBY_BIN" -e 'print RUBY_VERSION')
fi

if [ -z "$RUBY_MINOR" ]; then
  error "Could not detect the PUN's Ruby. Set PUN_RUBY=/path/to/ruby or PUN_RUBY_ABI=X.Y and re-run."
  error "Find it with: grep -R passenger_ruby /etc/ood/config/  (unset means the system Ruby)."
  exit 1
fi
info "PUN Ruby: ${PUN_RUBY_BIN:-<system default>} -> building for Ruby ${RUBY_MINOR}.x"

# Choose the rbenv Ruby: honor RBENV_VERSION, else prefer the PUN's exact patch,
# else the latest patch in the minor (ABI is identical across patch levels).
RBENV_FALLBACK=$(rbenv install -l 2>/dev/null | tr -d ' ' | grep -E "^${RUBY_MINOR//./\.}\.[0-9]+$" | tail -n1)
RBENV_VERSION="${RBENV_VERSION:-${PUN_RUBY_FULL:-$RBENV_FALLBACK}}"
if [ -z "$RBENV_VERSION" ]; then
  error "No installable Ruby ${RUBY_MINOR}.x found via rbenv. Update ruby-build, or set RBENV_VERSION."
  exit 1
fi

# Install it, falling back to the latest-in-minor if the exact patch is
# unavailable (rbenv install -s can build a patch that `-l` does not list).
# Build output is kept so a failure can be reported instead of swallowed: a
# silent failure here is what lets a wrong-ABI bundle get built later.
RBENV_BUILD_LOG=$(mktemp 2>/dev/null || echo /tmp/rbenv-build.$$)
function ensure_rbenv_ruby {
  local v="$1"
  rbenv versions --bare | grep -qx "$v" && return 0
  info "Installing Ruby $v... (ETA: 1-3 minutes)"
  rbenv install -s "$v" >"$RBENV_BUILD_LOG" 2>&1
  rbenv rehash >/dev/null 2>&1
  rbenv versions --bare | grep -qx "$v"
}
if ensure_rbenv_ruby "$RBENV_VERSION"; then
  :
elif [ -n "$RBENV_FALLBACK" ] && [ "$RBENV_FALLBACK" != "$RBENV_VERSION" ] && ensure_rbenv_ruby "$RBENV_FALLBACK"; then
  info "Ruby $RBENV_VERSION was unavailable; using $RBENV_FALLBACK (same ABI)."
  RBENV_VERSION="$RBENV_FALLBACK"
else
  error "Failed to provide a Ruby ${RUBY_MINOR}.x to build with."
  # The common cause is a ruby-build too old to know the PUN's patch release.
  # Say so explicitly, with the newest patch it does know, because the fix
  # (update ruby-build, or name an older same-ABI patch) is not obvious.
  if [ -z "$RBENV_FALLBACK" ]; then
    error "ruby-build ($(rbenv install --version 2>/dev/null | awk '{print $2}')) lists no ${RUBY_MINOR}.x release at all."
    error "Update it:  git -C \"\$(rbenv root)/plugins/ruby-build\" pull"
  else
    error "ruby-build knows ${RUBY_MINOR}.x only up to $RBENV_FALLBACK, and neither it nor"
    error "$RBENV_VERSION could be built. Any ${RUBY_MINOR}.x patch works -- the ABI is the same."
    error "Update ruby-build, or:  RBENV_VERSION=$RBENV_FALLBACK $0"
  fi
  [ -s "$RBENV_BUILD_LOG" ] && { error "Last lines of the build log:"; tail -15 "$RBENV_BUILD_LOG" | sed 's/^/         /'; }
  exit 1
fi
rm -f "$RBENV_BUILD_LOG"

# The invariant everything below depends on: the Ruby we bundle with must have
# the SAME ABI as the PUN's Ruby, because Bundler resolves a vendored bundle
# under vendor/bundle/ruby/<abi>/. Patch level is irrelevant (3.3.8 and 3.3.10
# are both ABI 3.3.0); the MAJOR.MINOR is not. Assert it rather than trusting
# that the selection logic above got there -- a mismatch is silent at build time
# and only surfaces as Bundler::GemNotFound when the PUN loads the app.
#
# Checked before `rbenv local` below, so aborting here leaves .ruby-version as
# it was rather than repinning the checkout to a Ruby we just rejected.
BUILD_ABI=$("$(rbenv prefix "$RBENV_VERSION" 2>/dev/null)/bin/ruby" -e 'print RbConfig::CONFIG["ruby_version"]' 2>/dev/null)
if [ "$BUILD_ABI" != "${RUBY_MINOR}.0" ]; then
  error "ABI mismatch: building with Ruby $RBENV_VERSION (ABI ${BUILD_ABI:-unknown}), but the"
  error "PUN's Ruby needs ABI ${RUBY_MINOR}.0. The vendored bundle would land in"
  error "vendor/bundle/ruby/${BUILD_ABI:-?}/ where the PUN never looks."
  error "Install a ${RUBY_MINOR}.x Ruby and re-run, or set RBENV_VERSION=${RUBY_MINOR}.<patch>."
  exit 1
fi
success "Ruby $RBENV_VERSION ready."

# Pin this checkout to the selected Ruby (writes .ruby-version, which is gitignored).
rbenv local "$RBENV_VERSION" >/dev/null 2>&1
rbenv rehash >/dev/null 2>&1
RUBY_BIN=$(rbenv which ruby 2>/dev/null)
RUBY_V=$(ruby -v 2>/dev/null)
if [ -z "$RUBY_V" ]; then
  # Present but won't execute -- usually a broken build linking libraries absent
  # from this environment. Common on HPC when Ruby was compiled with modules
  # (MPI/UCX/libfabric) loaded; those libs vanish once the modules unload.
  error "Ruby $RBENV_VERSION is installed but will not run -- likely a broken build."
  ldd "$RUBY_BIN" 2>/dev/null | grep -i 'not found' | sed 's/^/         missing: /'
  error "Rebuild it in a clean environment:"
  error "  module purge && rbenv uninstall -f $RBENV_VERSION && rbenv install $RBENV_VERSION"
  exit 1
elif [ "$(ruby -e 'print RUBY_VERSION' 2>/dev/null)" != "$RBENV_VERSION" ]; then
  # Exact compare, not `grep "$RBENV_VERSION"`: unanchored, and `.` is a regex
  # wildcard there, so a near-miss version could satisfy the check.
  error "Ruby $RBENV_VERSION is not active here (got: $RUBY_V)."
  error "Check that 'rbenv local $RBENV_VERSION' succeeded and that rbenv's shims precede /usr/bin in PATH."
  exit 1
fi
# Even when it runs here, a module-contaminated build links libraries from
# module/spack trees the PUN will not have. Catch that before bundling.
RUBY_BADLIBS=$(ldd "$RUBY_BIN" 2>/dev/null | grep -iE '/apps/|/spack|not found')
if [ -n "$RUBY_BADLIBS" ]; then
  error "Ruby $RBENV_VERSION links libraries from paths the PUN will not have:"
  echo "$RUBY_BADLIBS" | sed 's/^/         /'
  error "Rebuild it in a clean environment (module purge) before deploying."
  exit 1
fi
success "Ruby $RBENV_VERSION activated for this directory."

# The steps above only affect this script. The PUN never reads your shell rc, so
# this note is only about YOUR interactive shells picking up the right Ruby.
if ! grep -qs "rbenv init" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.zshrc" 2>/dev/null; then
  info "Note: your shell startup files do not initialize rbenv, so 'bundle' and"
  info "'rails' will use the system Ruby in new interactive shells. Add these"
  info "lines to your shell rc file (after any lines that overwrite PATH):"
  info '  export PATH="$HOME/.rbenv/bin:$PATH"'
  info '  eval "$(rbenv init - <your-shell>)"'
fi

# Ensure a bundler is available. Prefer the version the lockfile was built with,
# so the PUN's bundler does not have to switch; fall back to the Ruby's default.
LOCK_BUNDLER=$(awk '/^BUNDLED WITH/{getline; gsub(/ /,""); print; exit}' Gemfile.lock 2>/dev/null)
BUNDLER_VERSION="${BUNDLER_VERSION:-$LOCK_BUNDLER}"
if [ -n "$BUNDLER_VERSION" ] && ! gem list bundler -i --version "$BUNDLER_VERSION" >/dev/null 2>&1; then
  info "Installing bundler $BUNDLER_VERSION..."
  gem install bundler -v "$BUNDLER_VERSION" >/dev/null 2>&1 || {
    info "Could not install bundler $BUNDLER_VERSION; falling back to the Ruby's default bundler."
    BUNDLER_VERSION=""
  }
fi
# Run bundle with the pinned version when we have one, else the default.
function bndl { if [ -n "$BUNDLER_VERSION" ]; then bundle "_${BUNDLER_VERSION}_" "$@"; else bundle "$@"; fi; }

# --- Bundle for the target: vendored + precompiled native gems --------------
# Vendoring keeps the gems inside the app so they are found regardless of gem
# home. Adding this host's platform and dropping the generic `ruby` platform
# makes Bundler use precompiled native gems, which are self-contained; a source
# build can link a module/spack library (e.g. libiconv) absent from the PUN.
TARGET_PLATFORM="${TARGET_PLATFORM:-$(ruby -e 'print Gem::Platform.local.to_s' 2>/dev/null)}"
info "Installing Ruby gems into vendor/bundle for platform ${TARGET_PLATFORM}... (ETA: 1-3 minutes)"

bndl config set --local path vendor/bundle  >/dev/null 2>&1
bndl config set --local without doc         >/dev/null 2>&1
bndl lock --add-platform "$TARGET_PLATFORM" >/dev/null 2>&1
bndl lock --remove-platform ruby            >/dev/null 2>&1 || true

if ! bndl install >/dev/null 2>&1; then
  error "bundle install failed. Re-run 'bundle install' in $DASHBOARD_DIR to see the underlying error."
  exit 1
fi

# Verify no compiled extension links a library outside the standard system paths
# (module/spack trees, or anything reported "not found"). Such a gem loads on
# this build node but fails inside the PUN. Self-heal by pulling the offending
# gem's precompiled platform variant, then re-check.
function scan_bad_so {
  find vendor/bundle -name '*.so' 2>/dev/null | while read -r so; do
    if ldd "$so" 2>/dev/null | grep -qE '/apps/|/spack|not found'; then
      echo "$so" | sed -E 's#.*/gems/([^/]+)/.*#\1#'   # -> <gem>-<ver>[-<platform>]
    fi
  done | sort -u
}

attempt=0
while :; do
  bndl clean --force >/dev/null 2>&1     # drop source/stale builds no longer resolved
  bad=$(scan_bad_so)
  [ -z "$bad" ] && break
  attempt=$((attempt + 1))
  if [ "$attempt" -gt 2 ]; then
    error "These gems link a library the PUN may not have (they build here but fail in the PUN):"
    echo "$bad" | while read -r g; do error "  - $g"; done
    error "No precompiled variant exists for $TARGET_PLATFORM. Either install the missing"
    error "library into a PUN-visible path, or pin a gem version that ships a precompiled"
    error "$TARGET_PLATFORM build."
    exit 1
  fi
  gems=$(echo "$bad" | sed -E 's/-[0-9].*$//' | sort -u | tr '\n' ' ')
  info "Fetching precompiled builds for:${gems:+ }${gems}(attempt $attempt)..."
  bndl update $gems >/dev/null 2>&1
done
# Final outcome check, independent of how we got here: the gems must actually be
# under the ABI the PUN resolves against, and that ABI must be loadable by the
# PUN's own interpreter. Checking the result rather than the process catches any
# path that produces a mismatch, including ones the logic above does not foresee.
if [ ! -d "vendor/bundle/ruby/${RUBY_MINOR}.0" ]; then
  error "Bundle was installed, but not for the PUN's ABI (${RUBY_MINOR}.0)."
  error "Found instead: $(ls vendor/bundle/ruby/ 2>/dev/null | tr '\n' ' ')"
  error "The PUN resolves vendor/bundle/ruby/${RUBY_MINOR}.0/ and would fail with"
  error "Bundler::GemNotFound. Remove vendor/bundle and re-run."
  exit 1
fi
if [ -n "$PUN_RUBY_BIN" ] && [ -x "$PUN_RUBY_BIN" ]; then
  if ! "$PUN_RUBY_BIN" -S bundle check >/dev/null 2>&1; then
    error "The PUN's Ruby ($PUN_RUBY_BIN) cannot resolve the bundle:"
    "$PUN_RUBY_BIN" -S bundle check 2>&1 | head -8 | sed 's/^/         /'
    error "The app would fail to boot in the PUN. Remove vendor/bundle and re-run."
    exit 1
  fi
  success "Verified: the PUN's Ruby resolves the vendored bundle."
fi
success "Ruby dependencies installed (vendored, precompiled for $TARGET_PLATFORM)."

# 4. Install NodeJS dependencies
info "Checking NodeJS dependencies..."

# Install nvm if not installed
if check_nvm; then
  success "nvm is already installed."
else
  info "Installing nvm... (ETA: 5-10 seconds)"
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash >/dev/null 2>&1
  [[ "$SHELL" == "bash" ]] && source "$HOME/.bash_profile" >/dev/null 2>&1
  [[ "$SHELL" == "zsh" ]] && source "$HOME/.zshrc" >/dev/null 2>&1
  if check_nvm; then
    success "nvm installed successfully."
  else
    error "Failed to install nvm. Please ensure curl is installed and you have the necessary permissions."
    exit 1
  fi
fi

# Check if NodeJS 18.20.8 is installed and set up
if nvm which 18.20.8 >/dev/null 2>&1; then
  success "NodeJS 18.20.8 is already installed."
else
  info "Installing NodeJS 18.20.8... (ETA: 10-15 seconds)"
  nvm install 18.20.8 >/dev/null 2>&1
  if nvm which 18.20.8 >/dev/null 2>&1; then
    success "NodeJS 18.20.8 installed."
  else
    error "Failed to install NodeJS 18.20.8. Please ensure nvm is functioning properly and you have network access."
    exit 1
  fi
fi

# Activate it whether it was just installed or already present. Skipping this
# when already installed (the old behavior) leaves whatever Node is first on
# PATH active -- often a system Node too old for esbuild -- so `yarn install`
# below fails with an engine-incompatibility error.
nvm use 18.20.8 >/dev/null 2>&1
if ! node -v 2>/dev/null | grep -q "v18.20.8"; then
  error "NodeJS 18.20.8 is installed but not active (got: $(node -v 2>/dev/null))."
  error "Check that 'nvm use 18.20.8' works and that no module or system Node overrides nvm."
  exit 1
fi
success "NodeJS 18.20.8 activated."

# Install yarn if not installed
if command -v yarn >/dev/null; then
  success "yarn is already installed."
else
  info "Installing yarn... (ETA: 3-5 seconds)"
  npm install yarn -g >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    error "Failed to install yarn. Please check your npm setup and network connection."
    exit 1
  fi
fi

# Install required NodeJS dependencies. Use yarn, not npm: this repo ships a
# yarn.lock, which npm ignores, so `npm install` would resolve its own versions
# and write a competing package-lock.json.
info "Installing required NodeJS dependencies... (ETA: 5-10 seconds)"
if yarn install >/dev/null 2>&1; then
  success "NodeJS dependencies installed successfully."
else
  error "Failed to install NodeJS dependencies. Please check the package.json for issues and ensure you have network access."
  exit 1
fi

# 5. Compile the CSS/JS assets
info "Compiling CSS/JS assets... (ETA: 10-20 seconds)"
bin/recompile_js >/dev/null 2>&1

if [ $? -eq 0 ]; then
  success "CSS/JS assets compiled successfully."
else
  error "Failed to compile CSS/JS assets. Please check the script for errors and ensure all dependencies are installed correctly."
  exit 1
fi

# Success message with the access URL
success "Dashboard setup completed successfully!"
info "You can access the development dashboard at https://${OOD_HOST}/pun/dev/$FOLDER_NAME/"
info "If you receive a message saying 'App has not been initialized or does not exist,' please click the 'Initialize App' button."