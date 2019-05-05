FROM ruby:2.6

ARG GEM_VERSION

COPY pkg/brown-$GEM_VERSION.gem /tmp/brown.gem

RUN gem install /tmp/brown.gem \
	&& rm -f /tmp/brown.gem

ENTRYPOINT ["/usr/local/bundle/bin/brown"]
