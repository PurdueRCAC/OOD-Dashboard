# Development

Notes for working on the dashboard itself. For deploying it, see
[Installation](INSTALLATION.md).

## Enabling developer mode

OOD's sandbox app support looks for per-user directories under
`/var/www/ood/apps/dev/<username>`. Each entry is normally a symlink to a
directory in the user's home:

```bash
# As root on the OOD web node
user="alice"
mkdir -p "/var/www/ood/apps/dev/$user"
ln -s "/home/$user/ondemand/dev" "/var/www/ood/apps/dev/$user/gateway"
```

Once that exists, *Develop → My Sandbox Apps (Development)* appears in the
portal for that user, listing every app under `~/ondemand/dev`.

> **If your OOD host is managed by configuration management, make the change
> there rather than on the host**, or it will be reverted on the next run. At
> Purdue this means adding the directory and symlink under
> `puppet/modules/ondemand/files/var/www/ood/apps/dev` in the cluster's
> configuration repository, then waiting for (or triggering) a Puppet run on the
> admin node. Substitute your own site's equivalent.

> **Note:** this path is world-visible in the portal and affects the OOD web
> node. Coordinate with whoever administers the portal before changing it.

## Installing a development checkout

```bash
ssh <user>@<login-node>
git clone https://github.com/PurdueRCAC/OOD-Dashboard.git \
  "$HOME/ondemand/dev/dashboard"
cd "$HOME/ondemand/dev/dashboard"
./install.sh
```

`install.sh` detects the PUN's Ruby, builds a same-ABI rbenv Ruby, vendors the
gems (with precompiled native gems) into `vendor/bundle`, installs Node packages,
and compiles assets. It expects to run on the OOD web node; on a login node it
can't read the PUN's config, so either run it from the portal's shell on the web
node, or — if your login node shares `$HOME` and runs the same OS as the web node
— pass the PUN's Ruby explicitly, e.g. `PUN_RUBY_ABI=3.3 ./install.sh`. To
install from a fork, set `REPO_SLUG` (and `REPO_HOST` for GitHub Enterprise)
first:

```bash
REPO_SLUG=myorg/OOD-Dashboard ./install.sh
```

## Opening the dashboard

![How to open the dashboard](dashboard-setup.png)

1. Click **Develop** in the top right.
2. Click **My Sandbox Apps (Development)**.
3. Click **Launch HPC Dashboard** next to **HPC Dashboard \[main\]**.

If you see *App has not been initialized or does not exist*, click
**Initialize App**.

## Running locally

You can also run the app directly, which is faster to iterate against than the
PUN:

```bash
bundle exec rails server -b 0.0.0.0 -p 8080
```

Under VS Code Remote SSH the port is forwarded automatically, so the app is
reachable at <http://localhost:8080/>.

Copy `.env.local.example` to `.env.local` and fill in your site's values first —
see the [Configuration reference](CONFIGURATION.md) for what each key does. `.env.local` is gitignored; keep real credentials out of
commits.

## Rebuilding assets

After changing anything under `app/javascript` or the stylesheets:

```bash
bin/recompile_js
```

Running esbuild on its own is not sufficient — the browser loads the
Sprockets-served bundle, which this script also rebuilds.

## Tests

There is no automated test suite — the upstream dashboard's tests were not
carried over into this fork, so `bin/rails test` runs zero tests. Verify changes
manually against a sandbox deployment. Restoring upstream's tests would be a
welcome contribution.

## Adding site-specific values

Do not hardcode cluster names, paths, or URLs in views and controllers. Instead:

1. Add the key to `site_string_configs` in
   `config/configuration_singleton.rb`, with a comment and a `nil` default.
2. If it needs post-processing (a list, a fallback), add a method next to
   `site_name` / `excluded_partitions` rather than putting it in the hash —
   entries in the hash generate singleton methods that would shadow yours.
3. Expose it to views via a helper in `app/helpers/application_helper.rb` if
   templates need it.
4. Document it in `.env.local.example` and in
   [docs/CONFIGURATION.md](CONFIGURATION.md).
5. Make the feature degrade gracefully when the key is unset.
