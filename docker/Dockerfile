FROM ruby:4.0-slim AS base

ENV BUNDLE_WITHOUT="development:test" \
    BUNDLE_PATH="/bundle" \
    HARBINGER_CONFIG="/app/config/mammoth.config.yaml"

WORKDIR /app

FROM base AS build

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git libpq-dev libsqlite3-dev \
  && rm -rf /var/lib/apt/lists/*

COPY mammoth.gemspec Gemfile Gemfile.lock ./
COPY lib ./lib
RUN bundle install

FROM base

RUN apt-get update \
  && apt-get install -y --no-install-recommends libpq5 libsqlite3-0 ca-certificates \
  && rm -rf /var/lib/apt/lists/*

COPY --from=build /bundle /bundle
COPY . /app

ENTRYPOINT ["/app/docker/entrypoint.sh"]
CMD ["start", "/app/config/mammoth.config.yaml"]
