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
# NOTE: this image has never been built -- no container runtime was available
# where it was written, whereas the Apptainer recipe was built and run. What IS
# verified is everything it configures: the same demo mode, layout and
# environment are exercised on every change. If the build itself needs a fix,
# the demo runs identically with:
#   OOD_DEMO_MODE=true bundle exec rails server -b 0.0.0.0 -p 3000

FROM ruby:3.1-bullseye

# Node and Yarn build the CSS/JS bundles.
#
# Fetched as an official tarball rather than installed with apt, matching the
# Apptainer recipe. Not a stylistic choice: bullseye's `nodejs` package is
# 12.22, and sass 1.70 requires >= 14, so `yarn install` fails outright on the
# distro version. Bump NODE_VERSION here and in demo/apptainer.def together.
ENV NODE_VERSION=18.20.4
RUN curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
      | tar -xJ --no-same-owner -C /opt \
 && mv "/opt/node-v${NODE_VERSION}-linux-x64" /opt/node \
 && /opt/node/bin/npm install -g yarn@1
ENV PATH=/opt/node/bin:$PATH

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
RUN for a in files activejobs projects file-editor; do \
        mkdir -p "/app/$a" && \
        cp "/app/dashboard/other-apps/$a/manifest.yml" "/app/$a/manifest.yml"; \
    done \
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
