FROM ruby:4.0-alpine
WORKDIR /app
COPY Gemfile ./
RUN bundle install
COPY app.rb ./
COPY views ./views
COPY public ./public
EXPOSE 4000
CMD ["ruby", "app.rb"]
