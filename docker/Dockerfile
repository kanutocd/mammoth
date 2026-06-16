FROM ruby:4.0-slim AS build

WORKDIR /src

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    libpq-dev \
    libsqlite3-dev \
    libyaml-dev \
 && rm -rf /var/lib/apt/lists/*

COPY . .

RUN bundle install \
 && bundle exec rake build


FROM ruby:4.0-slim AS runtime

ENV MAMMOTH_CONFIG="/app/config/mammoth.config.yaml"

WORKDIR /app

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    libpq5 \
    libsqlite3-0 \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd --gid 10001 mammoth \
 && useradd --uid 10001 --gid mammoth --create-home --shell /usr/sbin/nologin mammoth \
 && mkdir -p /app/config /app/.sqlite3 /app/docker \
 && chown -R mammoth:mammoth /app

COPY --from=build /src/pkg/mammoth-*.gem /tmp/

RUN gem install /tmp/mammoth-*.gem --no-document \
 && rm -f /tmp/mammoth-*.gem

COPY docker/entrypoint.sh /app/docker/entrypoint.sh

RUN chmod +x /app/docker/entrypoint.sh \
 && chown mammoth:mammoth /app/docker/entrypoint.sh

USER mammoth

ENTRYPOINT ["/app/docker/entrypoint.sh"]
CMD ["start"]