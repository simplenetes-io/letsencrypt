#!/usr/bin/env sh

tag="letsencrypt-renewer:0.0.84"

podman build -t "${tag}" .
