#!/bin/bash

set -u

echo supprimer ancien startu
rm -rf ../startup-srv.sh

sleep 1

echo copier nouveau startup
cp startup-srv.sh ..