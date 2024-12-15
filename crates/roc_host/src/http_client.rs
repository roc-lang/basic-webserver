use roc_std::RocList;
use std::{iter::FromIterator, time::Duration};

use crate::roc_http::{Header, RequestToAndFromHost, ResponseToAndFromHost};

pub fn send_req(roc_request: &RequestToAndFromHost) -> ResponseToAndFromHost {
    let mut builder = reqwest::blocking::ClientBuilder::new();

    if let Some(ms) = roc_request.has_timeout() {
        builder = builder.timeout(Duration::from_millis(ms));
    }

    let client = match builder.build() {
        Ok(c) => c,
        Err(_) => {
            return ResponseToAndFromHost {
                status: 500,
                headers: RocList::empty(),
                body: "TLS backend cannot be initialized".as_bytes().into(),
            }
        }
    };

    let method = roc_request.to_reqwest_method();
    let mut req_builder = client.request(method, roc_request.url.as_str());

    for header in roc_request.headers.iter() {
        req_builder = req_builder.header(header.name.as_str(), header.value.as_bytes());
    }

    req_builder = req_builder.header("Content-Type", roc_request.mime_type.as_str());
    req_builder = req_builder.body(roc_request.body.as_slice().to_vec());

    let request = match req_builder.build() {
        Ok(req) => req,
        Err(err) => {
            return ResponseToAndFromHost {
                status: 400,
                headers: RocList::empty(),
                body: err.to_string().as_bytes().into(),
            }
        }
    };

    match client.execute(request) {
        Ok(response) => {
            let status = response.status().as_u16();
            let headers_iter = response.headers().iter().map(|(key, value)| {
                Header::new(
                    key.as_str().into(),
                    value
                        .to_str()
                        .expect("valid header value from response")
                        .into(),
                )
            });
            let headers = RocList::from_iter(headers_iter);
            let bytes = response.bytes().unwrap_or_default();
            let body: RocList<u8> = RocList::from_iter(bytes);

            ResponseToAndFromHost {
                status,
                headers,
                body,
            }
        }

        Err(err) => {
            if err.is_timeout() {
                ResponseToAndFromHost {
                    status: 408,
                    headers: RocList::empty(),
                    body: "Request Timeout".as_bytes().into(),
                }
            } else if err.is_request() {
                ResponseToAndFromHost {
                    status: 400,
                    headers: RocList::empty(),
                    body: "Bad Request".as_bytes().into(),
                }
            } else if err.is_connect() {
                ResponseToAndFromHost {
                    status: 599,
                    headers: RocList::empty(),
                    body: "Network Connect Timeout Error".as_bytes().into(),
                }
            } else {
                ResponseToAndFromHost {
                    status: 400,
                    headers: RocList::empty(),
                    body: err.to_string().as_bytes().into(),
                }
            }
        }
    }
}
