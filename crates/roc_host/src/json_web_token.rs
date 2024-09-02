use hmac::{Hmac, Mac};
use jwt::algorithm::AlgorithmType;
use roc_std::{RocList, RocResult, RocStr};
use sha2::{Sha256, Sha384, Sha512};
use std::collections::BTreeMap;

#[derive(Clone, Copy, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(u8)]
#[allow(dead_code)]
pub enum Algo {
    Hs256 = 0,
    Hs384 = 1,
    Hs512 = 2,
}

impl core::fmt::Debug for Algo {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            Self::Hs256 => f.write_str("Algo::Hs256"),
            Self::Hs384 => f.write_str("Algo::Hs384"),
            Self::Hs512 => f.write_str("Algo::Hs512"),
        }
    }
}

#[derive(Clone, Debug, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(C)]
pub struct JWTFromRoc {
    secret: RocStr,
    token: RocStr,
    algo: Algo,
}

impl JWTFromRoc {
    fn algorithm(&self) -> AlgorithmType {
        match self.algo {
            Algo::Hs256 => AlgorithmType::Hs256,
            Algo::Hs384 => AlgorithmType::Hs384,
            Algo::Hs512 => AlgorithmType::Hs512,
        }
    }
}

impl roc_std::RocRefcounted for JWTFromRoc {
    fn inc(&mut self) {
        self.secret.inc();
        self.token.inc();
    }
    fn dec(&mut self) {
        self.secret.dec();
        self.token.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}

#[derive(Clone, Default, Debug, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(C)]
pub struct JWTToRoc {
    name: RocStr,
    value: RocStr,
}

impl roc_std::RocRefcounted for JWTToRoc {
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

fn jwt_claims_to_roc(claims: BTreeMap<String, serde_json::Value>) -> RocList<JWTToRoc> {
    let mut roc_claims = RocList::with_capacity(claims.len());

    for (name, json_value) in claims {
        roc_claims.push(JWTToRoc {
            name: name.as_str().into(),
            value: format!("{}", json_value).as_str().into(),
        });
    }

    roc_claims
}

fn jwt_error_to_roc(err: jwt::error::Error) -> JwtErr {
    match err {
        jwt::error::Error::AlgorithmMismatch(..) => JwtErr::algorithm_mismatch(),
        jwt::error::Error::InvalidSignature => JwtErr::invalid_signature(),
        jwt::error::Error::Format => JwtErr::bad_format(),
        jwt::error::Error::Json(..) => JwtErr::bad_json(),
        jwt::error::Error::NoClaimsComponent => JwtErr::missing_claims(),
        jwt::error::Error::NoHeaderComponent => JwtErr::missing_header(),
        jwt::error::Error::NoSignatureComponent => JwtErr::missing_signature(),
        jwt::error::Error::NoKeyId => JwtErr::missing_key_id(),
        _ => JwtErr::other(err.to_string().as_str().into()),
    }
}

pub fn jwt_verify(jwt: &JWTFromRoc) -> RocResult<RocList<JWTToRoc>, JwtErr> {
    use jwt::VerifyWithKey;

    let token_str = jwt.token.as_str().to_string();

    match jwt.algorithm() {
        AlgorithmType::Hs256 => {
            let maybe_key: Result<Hmac<Sha256>, JwtErr> =
                Hmac::new_from_slice(&jwt.secret.as_bytes()).map_err(|_| JwtErr::bad_format());

            match maybe_key {
                Ok(key) => {
                    let claims: Result<BTreeMap<String, serde_json::Value>, jwt::error::Error> =
                        token_str.verify_with_key(&key);

                    match claims {
                        Ok(claims) => RocResult::ok(jwt_claims_to_roc(claims)),
                        Err(err) => RocResult::err(jwt_error_to_roc(err)),
                    }
                }
                Err(err) => return RocResult::err(err),
            }
        }
        AlgorithmType::Hs384 => {
            let maybe_key: Result<Hmac<Sha384>, JwtErr> =
                Hmac::new_from_slice(&jwt.secret.as_bytes()).map_err(|_| JwtErr::bad_format());

            match maybe_key {
                Ok(key) => {
                    let claims: Result<BTreeMap<String, serde_json::Value>, jwt::error::Error> =
                        token_str.verify_with_key(&key);

                    match claims {
                        Ok(claims) => RocResult::ok(jwt_claims_to_roc(claims)),
                        Err(err) => RocResult::err(jwt_error_to_roc(err)),
                    }
                }
                Err(err) => return RocResult::err(err),
            }
        }
        AlgorithmType::Hs512 => {
            let maybe_key: Result<Hmac<Sha512>, JwtErr> =
                Hmac::new_from_slice(&jwt.secret.as_bytes()).map_err(|_| JwtErr::bad_format());

            match maybe_key {
                Ok(key) => {
                    let claims: Result<BTreeMap<String, serde_json::Value>, jwt::error::Error> =
                        token_str.verify_with_key(&key);

                    match claims {
                        Ok(claims) => RocResult::ok(jwt_claims_to_roc(claims)),
                        Err(err) => RocResult::err(jwt_error_to_roc(err)),
                    }
                }
                Err(err) => return RocResult::err(err),
            }
        }
        // TODO: implement the rest of the algorithms
        // Rs256,
        // Rs384,
        // Rs512,
        // Es256,
        // Es384,
        // Es512,
        // Ps256,
        // Ps384,
        // Ps512,
        // None,
        _ => todo!(),
    }
}

#[derive(Clone, Copy, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(u8)]
pub enum JwtErrDiscriminant {
    AlgorithmMismatch = 0,
    BadFormat = 1,
    BadJson = 2,
    InvalidSignature = 3,
    MissingClaims = 4,
    MissingHeader = 5,
    MissingKeyId = 6,
    MissingSignature = 7,
    Other = 8,
}

#[repr(C, align(8))]
pub union JwtErrUnion {
    algorithm_mismatch: (),
    bad_format: (),
    bad_json: (),
    invalid_signature: (),
    missing_claims: (),
    missing_header: (),
    missing_key_id: (),
    missing_signature: (),
    other: core::mem::ManuallyDrop<roc_std::RocStr>,
}

#[repr(C)]
pub struct JwtErr {
    payload: JwtErrUnion,
    discriminant: JwtErrDiscriminant,
}

impl JwtErr {
    /// Returns which variant this tag union holds. Note that this never includes a payload!
    pub fn discriminant(&self) -> JwtErrDiscriminant {
        unsafe {
            let bytes = core::mem::transmute::<&Self, &[u8; core::mem::size_of::<Self>()]>(self);

            core::mem::transmute::<u8, JwtErrDiscriminant>(*bytes.as_ptr().add(24))
        }
    }

    pub fn algorithm_mismatch() -> Self {
        Self {
            discriminant: JwtErrDiscriminant::AlgorithmMismatch,
            payload: JwtErrUnion {
                algorithm_mismatch: (),
            },
        }
    }

    pub fn bad_format() -> Self {
        Self {
            discriminant: JwtErrDiscriminant::BadFormat,
            payload: JwtErrUnion { bad_format: () },
        }
    }

    pub fn bad_json() -> Self {
        Self {
            discriminant: JwtErrDiscriminant::BadJson,
            payload: JwtErrUnion { bad_json: () },
        }
    }

    pub fn invalid_signature() -> Self {
        Self {
            discriminant: JwtErrDiscriminant::InvalidSignature,
            payload: JwtErrUnion {
                invalid_signature: (),
            },
        }
    }

    pub fn missing_claims() -> Self {
        Self {
            discriminant: JwtErrDiscriminant::MissingClaims,
            payload: JwtErrUnion { missing_claims: () },
        }
    }

    pub fn missing_header() -> Self {
        Self {
            discriminant: JwtErrDiscriminant::MissingHeader,
            payload: JwtErrUnion { missing_header: () },
        }
    }

    pub fn missing_key_id() -> Self {
        Self {
            discriminant: JwtErrDiscriminant::MissingKeyId,
            payload: JwtErrUnion { missing_key_id: () },
        }
    }

    pub fn missing_signature() -> Self {
        Self {
            discriminant: JwtErrDiscriminant::MissingSignature,
            payload: JwtErrUnion {
                missing_signature: (),
            },
        }
    }

    pub fn other(payload: roc_std::RocStr) -> Self {
        Self {
            discriminant: JwtErrDiscriminant::Other,
            payload: JwtErrUnion {
                other: core::mem::ManuallyDrop::new(payload),
            },
        }
    }
}

impl Drop for JwtErr {
    fn drop(&mut self) {
        // Drop the payloads
        match self.discriminant() {
            JwtErrDiscriminant::AlgorithmMismatch => {}
            JwtErrDiscriminant::BadFormat => {}
            JwtErrDiscriminant::BadJson => {}
            JwtErrDiscriminant::InvalidSignature => {}
            JwtErrDiscriminant::MissingClaims => {}
            JwtErrDiscriminant::MissingHeader => {}
            JwtErrDiscriminant::MissingKeyId => {}
            JwtErrDiscriminant::MissingSignature => {}
            JwtErrDiscriminant::Other => unsafe {
                core::mem::ManuallyDrop::drop(&mut self.payload.other)
            },
        }
    }
}

impl roc_std::RocRefcounted for JwtErr {
    fn inc(&mut self) {
        match self.discriminant() {
            JwtErrDiscriminant::AlgorithmMismatch => {}
            JwtErrDiscriminant::BadFormat => {}
            JwtErrDiscriminant::BadJson => {}
            JwtErrDiscriminant::InvalidSignature => {}
            JwtErrDiscriminant::MissingClaims => {}
            JwtErrDiscriminant::MissingHeader => {}
            JwtErrDiscriminant::MissingKeyId => {}
            JwtErrDiscriminant::MissingSignature => {}
            JwtErrDiscriminant::Other => unsafe {
                (*self.payload.other).inc();
            },
        }
    }
    fn dec(&mut self) {
        match self.discriminant() {
            JwtErrDiscriminant::AlgorithmMismatch => {}
            JwtErrDiscriminant::BadFormat => {}
            JwtErrDiscriminant::BadJson => {}
            JwtErrDiscriminant::InvalidSignature => {}
            JwtErrDiscriminant::MissingClaims => {}
            JwtErrDiscriminant::MissingHeader => {}
            JwtErrDiscriminant::MissingKeyId => {}
            JwtErrDiscriminant::MissingSignature => {}
            JwtErrDiscriminant::Other => unsafe {
                (*self.payload.other).dec();
            },
        }
    }
    fn is_refcounted() -> bool {
        true
    }
}
