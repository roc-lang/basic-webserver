use roc_std::{RocList, RocStr};
use std::{iter::FromIterator, time::Duration};

use crate::roc_http;

pub fn send_req(roc_request: &roc_http::RequestToAndFromHost) -> roc_http::ResponseFromHost {
    let mut builder = reqwest::blocking::ClientBuilder::new();

    if let Some(ms) = roc_request.has_timeout() {
        builder = builder.timeout(Duration::from_millis(ms));
    }

    let client = match builder.build() {
        Ok(c) => c,
        Err(_) => {
            return roc_http::ResponseFromHost::bad_status(
                roc_http::Metadata::from_status_code(500),
                "TLS backend cannot be initialized".as_bytes().into(),
            )
        }
    };

    let method = roc_request.to_reqwest_method();
    let mut req_builder = client.request(method, roc_request.url.as_str());

    for header in roc_request.headers.iter() {
        req_builder = req_builder.header(header.key.as_str(), header.value.as_bytes());
    }

    req_builder = req_builder.header("Content-Type", roc_request.mime_type.as_str());
    req_builder = req_builder.body(roc_request.body.as_slice().to_vec());

    let request = match req_builder.build() {
        Ok(req) => req,
        Err(err) => return roc_http::ResponseFromHost::bad_request(err.to_string().as_str()),
    };

    match client.execute(request) {
        Ok(response) => {
            let headers_iter = response.headers().iter().map(|(key, value)| {
                roc_http::Header::new(
                    key.as_str().into(),
                    value
                        .to_str()
                        .expect("valid header value from response")
                        .into(),
                )
            });

            let headers = RocList::from_iter(headers_iter);

            let status = response.status().as_u16();
            let bytes = response.bytes().unwrap_or_default();
            let body: RocList<u8> = RocList::from_iter(bytes);

            let metadata = roc_http::Metadata {
                headers,
                url: roc_request.url.clone(),
                status_code: status,
                status_text: RocStr::empty(),
            };

            roc_http::ResponseFromHost::good_status(metadata, body)
        }

        Err(err) => {
            if err.is_timeout() {
                roc_http::ResponseFromHost::timeout()
            } else if err.is_request() {
                roc_http::ResponseFromHost::bad_request(err.to_string().as_str())
            } else if err.is_connect() {
                roc_http::ResponseFromHost::network_error()
            } else {
                roc_http::ResponseFromHost::bad_status(
                    roc_http::Metadata::from_status_code(404),
                    RocList::from_slice(err.to_string().as_bytes()),
                )
            }
        }
    }
}
