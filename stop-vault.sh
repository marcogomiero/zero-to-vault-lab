#!/bin/bash

# Stop all Vault processes (there might be another instance listening)
echo "Stopping all Vault processes listening on port 8200..."
lsof -ti:8200 | xargs -r kill >/dev/null 2>&1
sleep 5
echo "All Done."