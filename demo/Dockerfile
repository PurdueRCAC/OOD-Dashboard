# Demo container: the dashboard with an invented cluster behind it.
#
#   docker build -f demo/Dockerfile -t ood-hpc-dashboard:demo .
#   docker run --rm -p 3000:3000 ood-hpc-dashboard:demo
#   open http://localhost:3000
#
# There is no scheduler, no Open OnDemand portal and no authentication here.
# The stub tools in demo/bin stand in for Slurm, so every number is invented.
# See demo/README.md.
#
# On HPC, prefer demo/apptainer.def -- it needs no daemon and no root. This
# file mirrors it; the two are kept deliberately in step.
#
# NOTE: this file is maintained without a Docker daemon to hand, so build fixes
# arrive one real build at a time. Two failures found and fixed so far: the
# distro Node being too old for sass, and PATH being set after the step that
# needed it. What is continuously verified is everything it *configures* -- the
# same demo mode, layout and runtime environment are exercised on every change.
# If a build step still needs a fix, the demo runs identically with:
#   OOD_DEMO_MODE=true bundle exec rails server -b 0.0.0.0 -p 3000

FROM ruby:3.1-bullseye

# Node and Yarn build the CSS/JS bundles.
#
# Fetched as an official tarball rather than installed with apt, matching the
# Apptainer recipe. Not a stylistic choice: bullseye's `nodejs` package is
# 12.22, and sass 1.70 requires >= 14, so `yarn install` fails outright on the
# distro version. Bump NODE_VERSION here and in demo/apptainer.def together.
ENV NODE_VERSION=18.20.4
# PATH must be set *before* the install step, not after: npm is a
# `#!/usr/bin/env node` script, so invoking it by absolute path still fails with
# "env: 'node': No such file or directory" unless node is already resolvable.
ENV PATH=/opt/node/bin:$PATH
# The tarball must match the image's architecture. Hardcoding x64 breaks on
# arm64 hosts -- on an Apple Silicon Mac, Docker pulls the arm64 base image and
# an x86-64 Node binary dies in Rosetta with "failed to open elf at
# /lib64/ld-linux-x86-64.so.2". Derived from uname so it is correct on whatever
# the builder actually is, rather than depending on a BuildKit-only ARG.
RUN set -eux; \
    case "$(uname -m)" in \
      x86_64)          node_arch=x64 ;; \
      aarch64 | arm64) node_arch=arm64 ;; \
      *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${node_arch}.tar.xz" \
      | tar -xJ --no-same-owner -C /opt; \
    mv "/opt/node-v${NODE_VERSION}-linux-${node_arch}" /opt/node; \
    npm install -g yarn@1; \
    node --version; yarn --version

# The dashboard identifies the user from the process uid (OodSupport::User, and
# the demo dataset), so run as a real user that exists in /etc/passwd.
RUN useradd --create-home --shell /bin/bash demo

# The dashboard lives beside the core OOD apps, as it does under
# /var/www/ood/apps/sys -- that adjacency is what enables the Files, Active Jobs
# and Projects routes.
WORKDIR /app/dashboard

# Dependencies first, so edits to application code do not invalidate them.
COPY Gemfile Gemfile.lock ./
# Install every group. Excluding `doc` here would have to stay excluded at
# runtime too, and a mismatch makes bundler refuse to boot claiming every gem
# is missing; the few extra gems are cheaper than that failure mode.
RUN bundle install --jobs 4 --retry 2

COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile

COPY . .

# Assets are served from the root here, not from a PUN sub-path.
ENV RAILS_ENV=development \
    RAILS_RELATIVE_URL_ROOT=/
# .dockerignore keeps the committed build output out of the context, so create
# the directory the bundlers write into before invoking them.
#
# SECRET_KEY_BASE is scoped to this one command rather than set as an ENV: it is
# only needed while precompiling, and a persistent ENV both bakes it into the
# image and trips Docker's SecretsUsedInArgOrEnv check. In development Rails
# generates its own key at boot, so nothing needs it at runtime.
RUN mkdir -p app/assets/builds \
 && yarn build \
 && yarn build:css \
 && SECRET_KEY_BASE=build-time-only bundle exec rails assets:precompile

# Sibling core apps, so Configuration#can_access_files? and friends are true.
#
# tmp/ and log/ are created explicitly because .dockerignore keeps the host's
# copies out of the context, and the container runs as an unprivileged user that
# could not create them under a root-owned /app. Rails does make them on demand,
# but only if the parent is writable -- so create them here and let the chown
# below cover them.
RUN for a in files activejobs projects file-editor; do \
        mkdir -p "/app/$a" && \
        cp "/app/dashboard/other-apps/$a/manifest.yml" "/app/$a/manifest.yml"; \
    done \
 && mkdir -p /app/dashboard/tmp/cache /app/dashboard/tmp/pids /app/dashboard/log \
 && chown -R demo:demo /app

USER demo
ENV USER=demo \
    HOME=/home/demo \
    OOD_DEMO_MODE=true \
    OOD_DATAROOT=/tmp/ood-dashboard/data

# Outside a real portal there is no /etc/ood describing the sibling OOD apps,
# and OodAppkit then hands the views nil URLs. Point them at this app's own
# routes so the links resolve.
ENV OOD_DASHBOARD_TITLE="HPC Dashboard (demo)" \
    OOD_DASHBOARD_URL=/ \
    OOD_FILES_URL=/files \
    OOD_EDITOR_URL=/files/edit \
    OOD_PUBLIC_URL=/public \
    OOD_SHELL_URL=/shell

EXPOSE 3000
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3000"]
