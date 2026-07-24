ARG RUBY_IMAGE=ruby:4.0-slim@sha256:abd7528c4df35d151e2643d5efb845e442a26e36a4babc6459bee508619137a2

FROM ${RUBY_IMAGE} AS build

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


FROM ${RUBY_IMAGE} AS runtime

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

# Ruby 4.0.6 bundles vulnerable json 2.18.0 as a default gem. Mammoth installs
# its patched dependency first, then removes only the obsolete default spec.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    build-essential \
    libpq-dev \
    libsqlite3-dev \
    libyaml-dev \
 && gem install /tmp/mammoth-*.gem --no-document \
 && ruby -e 'floor = Gem::Version.new("2.19.2"); Gem::Specification.find_all_by_name("json").select { |spec| spec.default_gem? && spec.version < floor }.each { |spec| File.delete(spec.loaded_from) }' \
 && ruby -e 'gem "json", ">= 2.19.2"; require "json"; abort "patched json gem is not active" if Gem::Version.new(JSON::VERSION) < Gem::Version.new("2.19.2")' \
 && apt-get purge -y --auto-remove \
    build-essential \
    libpq-dev \
    libsqlite3-dev \
    libyaml-dev \
 && rm -f /tmp/mammoth-*.gem \
 && rm -rf /var/lib/apt/lists/*

COPY docker/entrypoint.sh /app/docker/entrypoint.sh

RUN chmod +x /app/docker/entrypoint.sh \
 && chown mammoth:mammoth /app/docker/entrypoint.sh

USER mammoth

ENTRYPOINT ["/app/docker/entrypoint.sh"]
CMD ["start"]
