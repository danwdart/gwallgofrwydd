FROM ubuntu as build
ENV DEBIAN_FRONTEND noninteractive
RUN apt update && \
	apt -y install git build-essential cmake zlib1g-dev gettext gawk libncursesw5-dev python && \
	apt clean

COPY . /build/

WORKDIR /build/

RUN git submodule update --init --recursive --depth=1

RUN make apps_install

FROM scratch

COPY --from=build /build/root /

CMD ["/bin/sh"]
