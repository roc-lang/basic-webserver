#!/usr/bin/env bash

curl 'http://localhost:8000/' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'name=Test User' \
  --data-urlencode 'email=test@example.com' \
  --data-urlencode 'message=This is a test message' \
  > curl_form_output.txt 2>&1