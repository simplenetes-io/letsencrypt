#!/usr/bin/env sh

tag="letsencrypt-server:0.0.1"

podman build -t "${tag}" .
