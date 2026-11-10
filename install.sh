#!/bin/bash
# Builds Floater.app and installs it to /Applications.
exec "$(dirname "$0")/build.sh" --install
