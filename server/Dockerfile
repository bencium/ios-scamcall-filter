# PIRService: Apple's open-source Live Caller ID Lookup server (Apache-2.0).
# Built from source at a pinned commit plus three local patches (see patches/): load database
# shards from disk on demand, keep the token-signing key and the phones' keys on disk across
# restarts, and log lookups for the password-protected dashboard. The database lives on the
# Fly volume.
FROM swift:6.1-noble AS build
ARG PIR_REF=87e080a9262c8c9d728c6a20de5baf708fbae1fa
RUN git clone https://github.com/apple/live-caller-id-lookup-example.git /src \
 && cd /src && git checkout "$PIR_REF"
COPY patches /patches
WORKDIR /src
RUN git apply /patches/*.patch
RUN swift build -c release --product PIRService --static-swift-stdlib

FROM ubuntu:noble
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libcurl4t64 libxml2 tzdata \
 && rm -rf /var/lib/apt/lists/*
COPY --from=build /src/.build/release/PIRService /usr/local/bin/PIRService
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY dashboard/index.html /usr/local/share/scamblocker/dashboard.html
RUN chmod +x /usr/local/bin/entrypoint.sh
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
