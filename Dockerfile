FROM ruby:2.3.1-slim
RUN apt-get update -y && apt-get install -y --fix-missing build-essential \
    git-core pkg-config sqlite3 libsqlite3-dev
RUN gem install bundler
ENV APP_DIR=/code
ENV LANG=C.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=C.UTF-8
WORKDIR $APP_DIR
Add Gemfile $APP_DIR/
Add Gemfile.lock $APP_DIR/
RUN bundle install --jobs 4
ADD . $APP_DIR
CMD puma -C puma.rb rackup.ru
