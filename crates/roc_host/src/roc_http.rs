use roc_std::{roc_refcounted_noop_impl, RocList, RocRefcounted, RocStr};

#[derive(Clone, Debug, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(C)]
pub struct RequestToAndFromHost {
    pub body: RocList<u8>,
    pub headers: RocList<Header>,
    pub method_ext: RocStr,
    pub mime_type: RocStr,
    pub timeout_ms: u64,
    pub url: RocStr,
    pub method: MethodTag,
}

impl RocRefcounted for RequestToAndFromHost {
    fn inc(&mut self) {
        self.body.inc();
        self.headers.inc();
        self.method_ext.inc();
        self.mime_type.inc();
        self.url.inc();
    }
    fn dec(&mut self) {
        self.body.dec();
        self.headers.dec();
        self.method_ext.dec();
        self.mime_type.dec();
        self.url.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}

impl RequestToAndFromHost {
    pub fn from_reqwest(
        body_bytes: bytes::Bytes,
        headers: RocList<Header>,
        reqwest_method: reqwest::Method,
        url: RocStr,
        mime_type: RocStr,
    ) -> RequestToAndFromHost {
        let method = (&reqwest_method).into();
        let method_ext = {
            if method == MethodTag::Extension {
                RocStr::from(reqwest_method.as_str())
            } else {
                RocStr::empty()
            }
        };

        RequestToAndFromHost {
            body: body_bytes.to_vec().as_slice().into(),
            headers,
            method,
            method_ext,
            mime_type,
            timeout_ms: 0, // request is from server... roc hasn't got a timeout
            url,
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
        match self.method {
            MethodTag::Connect => reqwest::Method::CONNECT,
            MethodTag::Delete => reqwest::Method::DELETE,
            MethodTag::Get => reqwest::Method::GET,
            MethodTag::Head => reqwest::Method::HEAD,
            MethodTag::Options => reqwest::Method::OPTIONS,
            MethodTag::Patch => reqwest::Method::PATCH,
            MethodTag::Post => reqwest::Method::POST,
            MethodTag::Put => reqwest::Method::PUT,
            MethodTag::Trace => reqwest::Method::TRACE,
            MethodTag::Extension => {
                reqwest::Method::from_bytes(self.method_ext.as_bytes()).unwrap()
            }
        }
    }
}

#[derive(Clone, Default, Debug, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(C)]
pub struct Header {
    pub name: RocStr,
    pub value: RocStr,
}

impl Header {
    pub fn new(name: RocStr, value: RocStr) -> Header {
        Header { name, value }
    }
}

impl roc_std::RocRefcounted for Header {
    fn inc(&mut self) {
        self.name.inc();
        self.value.inc();
    }
    fn dec(&mut self) {
        self.name.dec();
        self.value.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}

#[derive(Clone, Copy, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(u8)]
pub enum MethodTag {
    Connect = 0,
    Delete = 1,
    Extension = 2,
    Get = 3,
    Head = 4,
    Options = 5,
    Patch = 6,
    Post = 7,
    Put = 8,
    Trace = 9,
}

impl From<&reqwest::Method> for MethodTag {
    fn from(method: &reqwest::Method) -> Self {
        if method == reqwest::Method::CONNECT {
            Self::Connect
        } else if method == reqwest::Method::DELETE {
            Self::Delete
        } else if method == reqwest::Method::GET {
            Self::Get
        } else if method == reqwest::Method::HEAD {
            Self::Head
        } else if method == reqwest::Method::OPTIONS {
            Self::Options
        } else if method == reqwest::Method::PATCH {
            Self::Patch
        } else if method == reqwest::Method::POST {
            Self::Post
        } else if method == reqwest::Method::PUT {
            Self::Put
        } else if method == reqwest::Method::TRACE {
            Self::Trace
        } else {
            Self::Extension
        }
    }
}

impl core::fmt::Debug for MethodTag {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            Self::Connect => f.write_str("MethodTag::Connect"),
            Self::Delete => f.write_str("MethodTag::Delete"),
            Self::Extension => f.write_str("MethodTag::Extension"),
            Self::Get => f.write_str("MethodTag::Get"),
            Self::Head => f.write_str("MethodTag::Head"),
            Self::Options => f.write_str("MethodTag::Options"),
            Self::Patch => f.write_str("MethodTag::Patch"),
            Self::Post => f.write_str("MethodTag::Post"),
            Self::Put => f.write_str("MethodTag::Put"),
            Self::Trace => f.write_str("MethodTag::Trace"),
        }
    }
}

roc_refcounted_noop_impl!(MethodTag);

#[derive(Clone, Default, Debug, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(C)]
pub struct ResponseToAndFromHost {
    pub body: RocList<u8>,
    pub headers: RocList<Header>,
    pub status: u16,
}

impl RocRefcounted for ResponseToAndFromHost {
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

impl ResponseToAndFromHost {
    pub fn hyper_status(&self) -> Result<hyper::StatusCode, ()> {
        match hyper::StatusCode::from_u16(self.status) {
            Ok(status) => Ok(status),
            Err(..) => Err(()),
        }
    }
}
