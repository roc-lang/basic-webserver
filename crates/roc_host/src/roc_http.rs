use roc_std::{RocList, RocStr};

#[derive(Debug)]
#[repr(C)]
pub struct RequestToAndFromHost {
    pub body: RocList<u8>,
    pub headers: RocList<Header>,
    pub method: RocStr,
    pub mime_type: RocStr,
    pub timeout_ms: u64,
    pub url: RocStr,
}

impl RequestToAndFromHost {
    pub fn from_reqwest(
        body_bytes: bytes::Bytes,
        headers: RocList<Header>,
        reqwest_method: reqwest::Method,
        url: hyper::Uri,
    ) -> RequestToAndFromHost {
        let method = match reqwest_method {
            reqwest::Method::OPTIONS => "Options".into(),
            reqwest::Method::GET => "Get".into(),
            reqwest::Method::POST => "Post".into(),
            reqwest::Method::PUT => "Put".into(),
            reqwest::Method::DELETE => "Delete".into(),
            reqwest::Method::HEAD => "Head".into(),
            reqwest::Method::TRACE => "Trace".into(),
            reqwest::Method::CONNECT => "Connect".into(),
            reqwest::Method::PATCH => "Patch".into(),
            _ => panic!("reqwest method not supported"),
        };

        RequestToAndFromHost {
            body: body_bytes.to_vec().as_slice().into(),
            headers,
            method,
            mime_type: RocStr::from("text/plain"),
            timeout_ms: 1_000,
            url: url.to_string().as_str().into(),
        }
    }

    pub fn has_timeout(&self) -> Option<u64> {
        if self.timeout_ms > 0 {
            Some(self.timeout_ms)
        } else {
            None
        }
    }

    pub fn to_reqwest_method(&self) -> reqwest::Method {
        match self.method.as_str() {
            "Options" => reqwest::Method::OPTIONS,
            "Get" => reqwest::Method::GET,
            "Post" => reqwest::Method::POST,
            "Put" => reqwest::Method::PUT,
            "Delete" => reqwest::Method::DELETE,
            "Head" => reqwest::Method::HEAD,
            "Trace" => reqwest::Method::TRACE,
            "Connect" => reqwest::Method::CONNECT,
            "Patch" => reqwest::Method::PATCH,
            other => panic!(
                "The platform reveived an unknown HTTP method Str from Roc: {}.",
                other
            ),
        }
    }
}

#[derive(Debug)]
#[repr(C)]
pub struct Header {
    pub key: RocStr,
    pub value: RocStr,
}

impl Header {
    pub fn new(key: RocStr, value: RocStr) -> Header {
        Header { key, value }
    }
}

impl roc_std::RocRefcounted for Header {
    fn inc(&mut self) {
        self.key.inc();
        self.value.inc();
    }
    fn dec(&mut self) {
        self.key.dec();
        self.value.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}

#[repr(C)]
pub struct Metadata {
    pub headers: RocList<Header>,
    pub url: RocStr,
    pub status_code: u16,
    pub status_text: RocStr,
}

impl Metadata {
    fn empty() -> Metadata {
        Metadata {
            headers: RocList::empty(),
            status_text: RocStr::empty(),
            url: RocStr::empty(),
            status_code: 0,
        }
    }

    pub fn from_status_code(status_code: u16) -> Metadata {
        Metadata {
            headers: RocList::empty(),
            status_text: RocStr::empty(),
            url: RocStr::empty(),
            status_code,
        }
    }
}

#[repr(C)]
pub struct ResponseFromHost {
    pub body: RocList<u8>,
    pub metadata: Metadata,
    pub variant: RocStr,
}

impl ResponseFromHost {
    pub fn bad_request(error: &str) -> ResponseFromHost {
        ResponseFromHost {
            variant: "BadRequest".into(),
            metadata: Metadata {
                status_text: RocStr::from(error),
                ..Metadata::empty()
            },
            body: RocList::empty(),
        }
    }

    pub fn good_status(metadata: Metadata, body: RocList<u8>) -> ResponseFromHost {
        ResponseFromHost {
            variant: "GoodStatus".into(),
            metadata,
            body,
        }
    }

    pub fn bad_status(metadata: Metadata, body: RocList<u8>) -> ResponseFromHost {
        ResponseFromHost {
            variant: "BadStatus".into(),
            metadata,
            body,
        }
    }

    pub fn timeout() -> ResponseFromHost {
        ResponseFromHost {
            variant: "Timeout".into(),
            metadata: Metadata::empty(),
            body: RocList::empty(),
        }
    }

    pub fn network_error() -> ResponseFromHost {
        ResponseFromHost {
            variant: "NetworkError".into(),
            metadata: Metadata::empty(),
            body: RocList::empty(),
        }
    }
}

#[derive(Debug)]
#[repr(C)]
pub struct ResponseToHost {
    pub body: roc_std::RocList<u8>,
    pub headers: roc_std::RocList<Header>,
    pub status: u16,
}

impl ResponseToHost {
    pub fn hyper_status(&self) -> Result<hyper::StatusCode, ()> {
        match hyper::StatusCode::from_u16(self.status) {
            Ok(status) => Ok(status),
            Err(..) => Err(()),
        }
    }
}

impl roc_std::RocRefcounted for ResponseToHost {
    fn inc(&mut self) {
        self.body.inc();
        self.headers.inc();
    }
    fn dec(&mut self) {
        self.body.dec();
        self.headers.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}
