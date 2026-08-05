# Troubleshooting

## `bundle install` fails building native gems

```
mkmf.rb can't find header files for ruby at /usr/share/include/ruby.h
An error occurred while installing nokogiri (1.15.5), and Bundler cannot continue.
```

You are compiling native gems against the system Ruby, which usually has no
`ruby-devel` headers — so gems with C extensions (`byebug`, `ffi`, `nio4r`,
`racc`, `websocket-driver`) fail to build from source. (Rails 6.1 itself runs
fine on Ruby 3.3; the deployed dashboard proves it. The problem is missing
headers and building from source, not the Ruby version.)

The fix is what `install.sh` does automatically: build with an rbenv Ruby, which
ships its own headers, and pull **precompiled** native gems so most never
compile. Bundling by hand, do the same:

```bash
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init - zsh)"            # or: bash
rbenv local 3.3.10                    # match the PUN Ruby's ABI; writes .ruby-version (gitignored)
bundle config set --local path vendor/bundle
bundle lock --add-platform "$(ruby -e 'print Gem::Platform.local')"
bundle lock --remove-platform ruby    # prefer precompiled gems over source builds
bundle install
```

Do **not** install `ruby-devel`; it needs root and only moves the failure later.
Add the first two lines to your shell rc so rbenv survives new shells, **after**
any line that overwrites `PATH` wholesale — a later `export PATH=...` will
otherwise drop the shims. (That is for your interactive shells only; the PUN
does not read your rc — see the next entry.)

If a failed run already left a broken gem tree, remove it before retrying:

```bash
rm -rf ~/.local/share/gem/ruby vendor/bundle
```

Because `install.sh` builds the gems before running `yarn install`, a Bundler
failure also means `yarn install` never ran and `node_modules/` is empty.

## `Bundler::GemNotFound` when the page loads (but the CLI is fine)

```
Could not find rails-6.1.7.6, jbuilder-2.11.5, ... in locally installed gems (Bundler::GemNotFound)
    .../.local/share/gem/ruby/gems/bundler-2.5.16/lib/bundler/definition.rb:600:in `materialize'
```

Your gems are installed, but for a **different Ruby** than the one Passenger
boots the app with. Passenger uses the site's `passenger_ruby` (often unset, so
the system Ruby — 3.3.x on RHEL 9). It does **not** use the Ruby from your login
shell: the PUN starts with a scrubbed environment (empty `PATH`), so rbenv is
never initialized and no shell rc file (`~/.zshrc`, `~/.bash_profile`) can
change which Ruby it picks. The give-away is the gem-home path in the error —
`~/.local/share/gem/ruby/<abi>` is the system Ruby's user gem dir, not rbenv's
`~/.rbenv/versions/...`.

Installing gems into a global gem home (or under a Ruby whose ABI differs from
the PUN's) therefore leaves them where Passenger's Ruby never looks. This is what
happens if the gems were built for the wrong Ruby, or not vendored. Fix it by
bundling for the PUN's Ruby and **vendoring into the app** so the gems are found
regardless of gem home:

```bash
# .bundle/config
BUNDLE_PATH: "vendor/bundle"
```
```bash
rbenv local 3.3.10        # match the PUN Ruby's ABI (3.3.0); Rails 6.1 runs on 3.3
bundle install            # populates vendor/bundle/ruby/3.3.0
touch tmp/restart.txt
```

`install.sh` does exactly this — it detects the PUN's Ruby, builds a same-ABI
rbenv Ruby, and vendors the bundle — which is also how the deployed
`sys/dashboard` is packaged. See the next entry: a source-built native gem may
still fail to load even after this.

## `libiconv.so.2: cannot open shared object file` (nokogiri) at boot

```
libiconv.so.2: cannot open shared object file: No such file or directory
    - .../gems/nokogiri-1.15.5/lib/nokogiri/nokogiri.so (LoadError)
```

`bundle install` compiled nokogiri **from source**, and the build linked a
`libiconv` from a module/spack path (e.g.
`/apps/spack/.../libiconv/.../lib/libiconv.so.2`) that exists on your build node
but is not in the PUN's library path. Confirm with `ldd`:

```bash
ldd vendor/bundle/ruby/3.3.0/gems/nokogiri-*/lib/nokogiri/nokogiri.so | grep -i iconv
```

Use nokogiri's **precompiled** platform gem instead — it statically bundles
libxml2/libxslt/libiconv and has no external dependency. Get the lock to prefer
it and re-resolve:

```bash
bundle lock --add-platform x86_64-linux
bundle lock --remove-platform ruby     # so the source gem is not chosen
bundle update nokogiri                 # installs nokogiri-<ver>-x86_64-linux[-gnu]
bundle clean --force                   # remove the stale source build
touch tmp/restart.txt
```

Then confirm no native extension links a non-standard library the PUN lacks:

```bash
find vendor/bundle -name '*.so' -exec sh -c \
  'ldd "$1" 2>/dev/null | grep -qE "/apps/spack|not found" && echo "LINKS MISSING LIB: $1"' _ {} \;
```

No output means every compiled gem is self-contained.

## Widgets show "Failed to load"

The dashboard's monitoring endpoints shell out to Slurm. Confirm the commands
work **as the web user** on the OOD host:

```bash
sinfo -h -o '%R|%a|%F|%C'
scontrol show node --oneliner | head -1
sacct -X -u "$USER" -S now-1week -P -n | head
```

An empty `PATH` inside the PUN is the usual cause. Check
`~/ondemand/data/sys/dashboard/` and the Rails log under `log/` for the
underlying error.

## Efficiency metrics columns are missing

Expected when `OOD_JOBSTATS_PYTHON`/`OOD_JOBSTATS_SCRIPT` are unset. If they are
set, run the exact command the dashboard runs:

```bash
"$OOD_JOBSTATS_PYTHON" "$OOD_JOBSTATS_SCRIPT" -j <jobid>
```

A `ModuleNotFoundError: requests` means the interpreter you named lacks
jobstats' dependencies. Failures are logged at `info` level and the metrics are
skipped rather than surfaced as errors.

## Announcements widget is empty

Confirm `OOD_NEWS_FEED_URL` returns JSON from the OOD host, and that
`OOD_NEWS_FEED_RESOURCE_FILTER` matches a `resources[].name` in the response — a
filter that matches nothing yields an empty widget. The response is cached for
30 minutes; the cache key includes the URL and filter, so config changes take
effect immediately.

## Storage widget is absent

Expected unless `OOD_QUOTA_COMMAND` is set. If it is, run it by hand as the web
user with a username as its only argument and compare the output against the
column format in
[Configuration → Storage widget](CONFIGURATION.md#storage-widget).

## GPU hours all show "N/A"

Expected unless `OOD_GPU_HOURS_PARTITIONS` names the job's partition and the job
id is above `OOD_GPU_HOURS_MIN_JOB_ID`.

## Balances look wrong for GPU allocations

`OOD_GPU_ACCOUNT_PATTERN` is probably not matching your GPU account names, so
they are being read as CPU-denominated. Note that unquoted `\z` is parsed as a
literal `z` — prefer `"-gpu$"`. An invalid regex is logged and treated as no
pattern.

## JS changes do not appear

Run `bin/recompile_js`. Running esbuild alone leaves the Sprockets-served bundle
stale.

## The demo container will not start

On an HPC login node, `LD_PRELOAD` (XALT) leaks into the container and kills
every binary before its own code runs, giving
`libc.so.6: version 'GLIBC_2.34' not found`. Use `--cleanenv`, and pass your own
variables through as `APPTAINERENV_*`. See [demo/README.md](../demo/README.md).

## Checking everything at once

```bash
demo/smoke.sh https://ondemand.example.edu/pun/dev/dashboard
```

Requests every page and JSON endpoint, follows a real job id and node name out
of the running instance, and exits non-zero if anything fails. Against a real
deployment, an empty Storage or Accounts result means the site configuration is
not wired up.
