#!/bin/bash

#set -x

exec git ls-files | grep -e "\(\.java\|\.h\|\.m\)$" | grep -v examples

