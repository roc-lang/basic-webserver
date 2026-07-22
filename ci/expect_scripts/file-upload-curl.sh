#!/usr/bin/env bash

curl 'http://localhost:8000/' \
  -H 'Content-Type: multipart/form-data; boundary=----WebKitFormBoundarykIHm2BDPibpfMOPG' \
  --data-raw $'------WebKitFormBoundarykIHm2BDPibpfMOPG\r\nContent-Disposition: form-data; name="fileToUpload"; filename="red_test_image.png"\r\nContent-Type: image/png\r\n\r\n\r\n------WebKitFormBoundarykIHm2BDPibpfMOPG\r\nContent-Disposition: form-data; name="submit"\r\n\r\nUpload .png Image\r\n------WebKitFormBoundarykIHm2BDPibpfMOPG--\r\n' \
  > curl_file_output.txt 2>&1