FROM ruby:4.0-alpine
RUN apk add --no-cache build-base postgresql-dev
WORKDIR /app
COPY Gemfile ./
RUN bundle install
COPY app.rb ./
COPY order_actions.rb ./
COPY views ./views
COPY public ./public
EXPOSE 3000
CMD ["ruby", "app.rb"]
