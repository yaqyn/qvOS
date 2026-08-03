# shellcheck shell=bash

echo "Migrate qvOS source and runtime ownership"

"$OMARCHY_PATH/qvcore/install/migrate-source-root"
"$OMARCHY_PATH/qvcore/config/migrate-runtime-root"
