FROM alpine:latest

RUN apk --no-cache add wireguard-tools iptables ip6tables inotify-tools

WORKDIR /scripts
ENV PATH="/scripts:${PATH}"

ENV IPTABLES_MASQ=1

ENV WATCH_CHANGES=0

COPY run /scripts
COPY genkeys /scripts
RUN chmod 755 /scripts/*

VOLUME /etc/wireguard

CMD ["run"]
