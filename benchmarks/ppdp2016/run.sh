#!/bin/bash

set -e
set -o xtrace

LINKSROOT="../../"

function drop_tables {
    psql -v ON_ERROR_STOP=1 -q -U postgres -d links -f "droptables.sql"
}

function recreate_tables {
    psql -v ON_ERROR_STOP=1 -q -U postgres -d links -f "organisation.sql"
}

function populate {
    "$LINKSROOT/links" --config=nodebug.config setup.links
}

function noprov {
    "$LINKSROOT/links" --config=db.config noprov.links
}

function allprov {
    "$LINKSROOT/links" --config=db.config allprov.links
}

# Dump
# pg_dump links -t departments -t employees -t tasks -t contacts > filename.sql

function loadDump {
    drop_tables
    psql -U postgres links < "$1.sql"
}

# Restore from dump
# psql -U postgres links < filename.sql

# drop_tables
# recreate_tables
# time populate
# time noprov

function prepareCSV {
    # echo '"prov";"N";"query";"mean";"timems"' > data.csv
    echo '"prov";"N";"query";"meanms"' > data.csv
}

function sanitizeCSV {
    sed -i '/() : ()/d' data.csv
}

sizes=(16 32 64 128)
# sizes=(16 32 64 128 256 512 1024 2048 4096)

prepareCSV
for n in "${sizes[@]}"
do
    loadDump $n
    noprov >> data.csv
    allprov >> data.csv
done
sanitizeCSV