#!/bin/sh
# Build the server's lookup database for a set of UK prefixes.
#
#   scripts/lookup/build_db.sh OUTDIR SHARDS PREFIX [PREFIX ...]
#   e.g. scripts/lookup/build_db.sh /tmp/lookup-db 8192 0843 0844 0870 0871 0872 0873
#
# Keep shards around 7,000 numbers each (60M numbers -> 8192 shards): each loads in a few
# milliseconds on demand. SHARDS must be a power of two (iOS 27.3 rule).
# BUCKETS fixes every shard's table size so all shards share one parameter set, which keeps
# the config the phone downloads small. Raise it if processing reports a cuckoo table failure.
#
# trialsPerShard is 0: the tool's built-in self-test is ~99% of processing time. Correctness is
# checked afterwards by real encrypted queries (scripts/lookup/check_db.sh).
# Steps: generate every number per prefix -> shard each prefix by keyword hash ->
# merge shard i of every prefix -> process each shard for PIR (in parallel) ->
# write the PIRService config. Output ready to upload lives in OUTDIR/db.
# Needs ConstructDatabase, PIRShardDatabase, PIRProcessDatabase on PATH (~/.swiftpm/bin).
set -eu
OUTDIR=$1; SHARDS=$2; shift 2; PREFIXES=$*
HERE=$(cd "$(dirname "$0")" && pwd)
JOBS=${JOBS:-$(( $(sysctl -n hw.ncpu) - 2 ))}
BUCKETS=${BUCKETS:-96}
START=$(date +%s)
mkdir -p "$OUTDIR/raw" "$OUTDIR/shards" "$OUTDIR/merged" "$OUTDIR/configs" "$OUTDIR/db"

echo "== 1/5 generate"
python3 "$HERE/generate_block_db.py" "$OUTDIR/raw" $PREFIXES

echo "== 2/5 shard each prefix into $SHARDS"
for p in $PREFIXES; do
  PIRShardDatabase --input-database "$OUTDIR/raw/$p.binpb" \
    --output-database "$OUTDIR/shards/$p-SHARD_ID.binpb" \
    --sharding shardCount --sharding-count "$SHARDS" > /dev/null
  echo "   $p sharded"
done

echo "== 3/5 merge shard i across prefixes (concatenated protobufs merge their rows)"
i=0
while [ "$i" -lt "$SHARDS" ]; do
  parts=""; for p in $PREFIXES; do parts="$parts $OUTDIR/shards/$p-$i.binpb"; done
  cat $parts > "$OUTDIR/merged/block-shard-$i.binpb"
  cat > "$OUTDIR/configs/$i.json" <<EOF
{
  "inputDatabase": "$OUTDIR/merged/block-shard-$i.binpb",
  "outputDatabase": "$OUTDIR/db/block-$i.bin",
  "outputPirParameters": "$OUTDIR/db/block-$i.params.txtpb",
  "rlweParameters": "n_4096_logq_27_28_28_logt_5",
  "sharding": { "shardCount": 1 },
  "cuckooTableArguments": { "hashFunctionCount": 2, "maxEvictionCount": 100, "maxSerializedBucketSize": 1024,
                            "bucketCount": { "fixedSize": { "bucketCount": $BUCKETS } } },
  "trialsPerShard": 0,
  "databaseType": "keyword"
}
EOF
  i=$((i + 1))
done
rm -rf "$OUTDIR/shards"

echo "== 4/5 process $SHARDS shards with $JOBS parallel jobs"
ls "$OUTDIR/configs" | xargs -P "$JOBS" -I{} sh -c 'PIRProcessDatabase "$1" > /dev/null 2>&1 || echo "FAILED $1"' _ "$OUTDIR/configs/{}"
PROCESSED=$(ls "$OUTDIR/db"/block-*.bin | wc -l | tr -d ' ')
[ "$PROCESSED" -eq "$SHARDS" ] || { echo "only $PROCESSED of $SHARDS shards processed"; exit 1; }

echo "== 5/5 identity dataset (one harmless test identity so the second lookup has a dataset) and service config"
cat > "$OUTDIR/identity-input.txtpb" <<EOF
identities {
  key: "+14085551212"
  value { name: "Johnny Appleseed" cache_expiry_minutes: 60 category: IDENTITY_CATEGORY_PERSON }
}
EOF
mkdir -p "$OUTDIR/icons"
ConstructDatabase --icon-directory "$OUTDIR/icons" "$OUTDIR/identity-input.txtpb" "$OUTDIR/unused-block.binpb" "$OUTDIR/identity.binpb" > /dev/null
cat > "$OUTDIR/configs/identity.json" <<EOF
{
  "inputDatabase": "$OUTDIR/identity.binpb",
  "outputDatabase": "$OUTDIR/db/identity-SHARD_ID.bin",
  "outputPirParameters": "$OUTDIR/db/identity-SHARD_ID.params.txtpb",
  "rlweParameters": "n_4096_logq_27_28_28_logt_5",
  "sharding": { "shardCount": 1 },
  "trialsPerShard": 1,
  "databaseType": "keyword"
}
EOF
PIRProcessDatabase "$OUTDIR/configs/identity.json" > /dev/null 2>&1
cat > "$OUTDIR/db/service-config.json" <<EOF
{
  "tokens": ["${LOOKUP_TOKEN:-REPLACE_WITH_LOOKUP_TOKEN}"],
  "usecases": [
    { "fileStem": "block", "shardCount": $SHARDS, "name": "uk.co.bencium.ScamBlocker.Lookup.block" },
    { "fileStem": "identity", "shardCount": 1, "name": "uk.co.bencium.ScamBlocker.Lookup.identity" }
  ]
}
EOF
UNIQUE=$(for f in "$OUTDIR"/db/block-*.params.txtpb; do shasum < "$f"; done | sort -u | wc -l | tr -d ' ')
echo "distinct shard parameter sets: $UNIQUE (1 means the phone gets the compact config)"
echo "prefixes: $PREFIXES  shards: $SHARDS  db size: $(du -sh "$OUTDIR/db" | cut -f1)  took $(( $(date +%s) - START ))s"
