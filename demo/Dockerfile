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
# NOTE: this Dockerfile has not been executed -- it was written without a
# container runtime available. The demo mode it packages *is* tested; if the
# build needs a fix, the same demo works directly with:
#   OOD_DEMO_MODE=true bundle exec rails server -b 0.0.0.0 -p 3000

FROM ruby:3.1-bullseye

# Node and Yarn are needed to build the CSS/JS bundles.
RUN apt-get update \
 && apt-get install -y --no-install-recommends nodejs npm tzdata \
 && npm install -g yarn@1 \
 && rm -rf /var/lib/apt/lists/*

# The dashboard reads the invoking POSIX user (OodSupport::User), so run as a
# real unprivileged user rather than root.
RUN useradd --create-home --shell /bin/bash demo
WORKDIR /app

# Dependencies first, so edits to application code do not invalidate them.
COPY Gemfile Gemfile.lock ./
RUN bundle config set --local without 'doc' \
 && bundle install --jobs 4 --retry 2

COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile

COPY . .

# Assets are served at the root here, not under a PUN prefix.
ENV RAILS_ENV=development \
    RAILS_RELATIVE_URL_ROOT=/ \
    SECRET_KEY_BASE=demo-only-not-a-secret
RUN yarn build && yarn build:css \
 && bundle exec rails assets:precompile \
 && chown -R demo:demo /app

USER demo
ENV USER=demo \
    HOME=/home/demo \
    OOD_DEMO_MODE=true

EXPOSE 3000
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3000"]
