#!/bin/bash -e

sudo docker run --rm --volume "./data:/data" skylerspaeth/poseidon autoinstall.yaml

mv data/*.iso .
