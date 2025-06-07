FROM docker:stable

RUN apk add --no-cache bash curl jq

COPY run-search-engine.sh /run-search-engine.sh
RUN chmod +x /run-search-engine.sh

ENTRYPOINT ["/run-search-engine.sh"]