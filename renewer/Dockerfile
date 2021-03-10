FROM alpine:latest

RUN apk add curl openssl socat

COPY release/renewer /renewer
COPY release/acme.sh /acme.sh

CMD ["/renewer"]
