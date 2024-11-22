// use roc_std::{RocList, RocStr};
// use std::collections::HashMap;

// #[repr(C)]
// pub struct FromRocJwt {
//     secret: RocStr,
//     token: RocStr,
// }

// impl roc_std::RocRefcounted for FromRocJwt {
//     fn inc(&mut self) {
//         self.secret.inc();
//         self.token.inc();
//     }
//     fn dec(&mut self) {
//         self.secret.dec();
//         self.token.dec();
//     }
//     fn is_refcounted() -> bool {
//         true
//     }
// }

// #[repr(C)]
// pub struct ToRocJwtClaims {
//     name: RocStr,
//     value: RocStr,
// }

// impl roc_std::RocRefcounted for ToRocJwtClaims {
//     fn inc(&mut self) {
//         self.name.inc();
//         self.value.inc();
//     }
//     fn dec(&mut self) {
//         self.name.dec();
//         self.value.dec();
//     }
//     fn is_refcounted() -> bool {
//         true
//     }
// }

// /// Represent the claims as an equivalent RocStr json value
// fn jwt_claims_to_roc(claims: HashMap<String, serde_json::Value>) -> RocList<ToRocJwtClaims> {
//     let mut roc_claims = RocList::with_capacity(claims.len());
//     let json_to_str = |json_value: serde_json::Value| -> RocStr {
//         match json_value {
//             serde_json::Value::String(s) => s.as_str().into(),
//             serde_json::Value::Number(n) => format!("{}", n).as_str().into(),
//             serde_json::Value::Bool(b) => {
//                 if b {
//                     "true".into()
//                 } else {
//                     "false".into()
//                 }
//             }
//             serde_json::Value::Null => "null".into(),
//             _ => panic!("unsupported json type"),
//         }
//     };

//     for (name, json_value) in dbg!(claims) {
//         roc_claims.push(ToRocJwtClaims {
//             name: name.as_str().into(),
//             value: json_to_str(json_value),
//         });
//     }

//     roc_claims
// }

// fn jwt_error_to_roc(err: jwt::error::Error) -> ToRocJwtErr {
//     match err {
//         jwt::error::Error::AlgorithmMismatch(..) => ToRocJwtErr::algorithm_mismatch(),
//         jwt::error::Error::InvalidSignature => ToRocJwtErr::invalid_signature(),
//         jwt::error::Error::Format => ToRocJwtErr::bad_format(),
//         jwt::error::Error::Json(..) => ToRocJwtErr::bad_json(),
//         jwt::error::Error::NoClaimsComponent => ToRocJwtErr::missing_claims(),
//         jwt::error::Error::NoHeaderComponent => ToRocJwtErr::missing_header(),
//         jwt::error::Error::NoSignatureComponent => ToRocJwtErr::missing_signature(),
//         jwt::error::Error::NoKeyId => ToRocJwtErr::missing_key_id(),
//         _ => ToRocJwtErr::other(err.to_string().as_str().into()),
//     }
// }

// pub fn jwt_verify(jwt: &FromRocJwt) -> Result<RocList<ToRocJwtClaims>, ToRocJwtErr> {
//     let header = json_web_token::jwt_header(&jwt.token).map_err(|_| ToRocJwtErr::bad_format())?;

//     match header.algorithm {
//         jwt::AlgorithmType::Hs256 => json_web_token::jwt_verify_hs256(&jwt.token, &jwt.secret)
//             .map(jwt_claims_to_roc)
//             .map_err(jwt_error_to_roc),
//         jwt::AlgorithmType::Hs384 => json_web_token::jwt_verify_hs384(&jwt.token, &jwt.secret)
//             .map(jwt_claims_to_roc)
//             .map_err(jwt_error_to_roc),
//         jwt::AlgorithmType::Hs512 => json_web_token::jwt_verify_hs512(&jwt.token, &jwt.secret)
//             .map(jwt_claims_to_roc)
//             .map_err(jwt_error_to_roc),
//         jwt::AlgorithmType::Rs256 => json_web_token::jwt_verify_rs256(&jwt.token, &jwt.secret)
//             .map(jwt_claims_to_roc)
//             .map_err(jwt_error_to_roc),
//         jwt::AlgorithmType::Rs384 => json_web_token::jwt_verify_rs384(&jwt.token, &jwt.secret)
//             .map(jwt_claims_to_roc)
//             .map_err(jwt_error_to_roc),
//         jwt::AlgorithmType::Rs512 => json_web_token::jwt_verify_rs512(&jwt.token, &jwt.secret)
//             .map(jwt_claims_to_roc)
//             .map_err(jwt_error_to_roc),
//         _ => Err(ToRocJwtErr::other("algorithm not implemented".into())),
//     }
// }

// #[derive(Clone, Copy, PartialEq, PartialOrd, Eq, Ord, Hash)]
// #[repr(u8)]
// pub enum JwtErrDiscriminant {
//     AlgorithmMismatch = 0,
//     BadFormat = 1,
//     BadJson = 2,
//     InvalidSignature = 3,
//     MissingClaims = 4,
//     MissingHeader = 5,
//     MissingKeyId = 6,
//     MissingSignature = 7,
//     Other = 8,
// }

// #[repr(C, align(8))]
// pub union JwtErrUnion {
//     algorithm_mismatch: (),
//     bad_format: (),
//     bad_json: (),
//     invalid_signature: (),
//     missing_claims: (),
//     missing_header: (),
//     missing_key_id: (),
//     missing_signature: (),
//     other: core::mem::ManuallyDrop<roc_std::RocStr>,
// }

// #[repr(C)]
// pub struct ToRocJwtErr {
//     payload: JwtErrUnion,
//     discriminant: JwtErrDiscriminant,
// }

// impl ToRocJwtErr {
//     /// Returns which variant this tag union holds. Note that this never includes a payload!
//     pub fn discriminant(&self) -> JwtErrDiscriminant {
//         unsafe {
//             let bytes = core::mem::transmute::<&Self, &[u8; core::mem::size_of::<Self>()]>(self);

//             core::mem::transmute::<u8, JwtErrDiscriminant>(*bytes.as_ptr().add(24))
//         }
//     }

//     pub fn algorithm_mismatch() -> Self {
//         Self {
//             discriminant: JwtErrDiscriminant::AlgorithmMismatch,
//             payload: JwtErrUnion {
//                 algorithm_mismatch: (),
//             },
//         }
//     }

//     pub fn bad_format() -> Self {
//         Self {
//             discriminant: JwtErrDiscriminant::BadFormat,
//             payload: JwtErrUnion { bad_format: () },
//         }
//     }

//     pub fn bad_json() -> Self {
//         Self {
//             discriminant: JwtErrDiscriminant::BadJson,
//             payload: JwtErrUnion { bad_json: () },
//         }
//     }

//     pub fn invalid_signature() -> Self {
//         Self {
//             discriminant: JwtErrDiscriminant::InvalidSignature,
//             payload: JwtErrUnion {
//                 invalid_signature: (),
//             },
//         }
//     }

//     pub fn missing_claims() -> Self {
//         Self {
//             discriminant: JwtErrDiscriminant::MissingClaims,
//             payload: JwtErrUnion { missing_claims: () },
//         }
//     }

//     pub fn missing_header() -> Self {
//         Self {
//             discriminant: JwtErrDiscriminant::MissingHeader,
//             payload: JwtErrUnion { missing_header: () },
//         }
//     }

//     pub fn missing_key_id() -> Self {
//         Self {
//             discriminant: JwtErrDiscriminant::MissingKeyId,
//             payload: JwtErrUnion { missing_key_id: () },
//         }
//     }

//     pub fn missing_signature() -> Self {
//         Self {
//             discriminant: JwtErrDiscriminant::MissingSignature,
//             payload: JwtErrUnion {
//                 missing_signature: (),
//             },
//         }
//     }

//     pub fn other(payload: roc_std::RocStr) -> Self {
//         Self {
//             discriminant: JwtErrDiscriminant::Other,
//             payload: JwtErrUnion {
//                 other: core::mem::ManuallyDrop::new(payload),
//             },
//         }
//     }
// }

// impl Drop for ToRocJwtErr {
//     fn drop(&mut self) {
//         // Drop the payloads
//         match self.discriminant() {
//             JwtErrDiscriminant::AlgorithmMismatch => {}
//             JwtErrDiscriminant::BadFormat => {}
//             JwtErrDiscriminant::BadJson => {}
//             JwtErrDiscriminant::InvalidSignature => {}
//             JwtErrDiscriminant::MissingClaims => {}
//             JwtErrDiscriminant::MissingHeader => {}
//             JwtErrDiscriminant::MissingKeyId => {}
//             JwtErrDiscriminant::MissingSignature => {}
//             JwtErrDiscriminant::Other => unsafe {
//                 core::mem::ManuallyDrop::drop(&mut self.payload.other)
//             },
//         }
//     }
// }

// impl roc_std::RocRefcounted for ToRocJwtErr {
//     fn inc(&mut self) {
//         match self.discriminant() {
//             JwtErrDiscriminant::AlgorithmMismatch => {}
//             JwtErrDiscriminant::BadFormat => {}
//             JwtErrDiscriminant::BadJson => {}
//             JwtErrDiscriminant::InvalidSignature => {}
//             JwtErrDiscriminant::MissingClaims => {}
//             JwtErrDiscriminant::MissingHeader => {}
//             JwtErrDiscriminant::MissingKeyId => {}
//             JwtErrDiscriminant::MissingSignature => {}
//             JwtErrDiscriminant::Other => unsafe {
//                 (*self.payload.other).inc();
//             },
//         }
//     }
//     fn dec(&mut self) {
//         match self.discriminant() {
//             JwtErrDiscriminant::AlgorithmMismatch => {}
//             JwtErrDiscriminant::BadFormat => {}
//             JwtErrDiscriminant::BadJson => {}
//             JwtErrDiscriminant::InvalidSignature => {}
//             JwtErrDiscriminant::MissingClaims => {}
//             JwtErrDiscriminant::MissingHeader => {}
//             JwtErrDiscriminant::MissingKeyId => {}
//             JwtErrDiscriminant::MissingSignature => {}
//             JwtErrDiscriminant::Other => unsafe {
//                 (*self.payload.other).dec();
//             },
//         }
//     }
//     fn is_refcounted() -> bool {
//         true
//     }
// }

// ⚠️ GENERATED CODE ⚠️ - this entire file was generated by the `roc glue` CLI command

#![allow(unused_unsafe)]
#![allow(dead_code)]
#![allow(unused_mut)]
#![allow(non_snake_case)]
#![allow(non_camel_case_types)]
#![allow(non_upper_case_globals)]
#![allow(clippy::undocumented_unsafe_blocks)]
#![allow(clippy::redundant_static_lifetimes)]
#![allow(clippy::unused_unit)]
#![allow(clippy::missing_safety_doc)]
#![allow(clippy::let_and_return)]
#![allow(clippy::missing_safety_doc)]
#![allow(clippy::needless_borrow)]
#![allow(clippy::clone_on_copy)]
#![allow(clippy::non_canonical_partial_ord_impl)]

use roc_std::roc_refcounted_noop_impl;
use roc_std::RocRefcounted;

#[derive(Clone, Copy, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(u8)]
pub enum JwtAlgorithms {
    HS256 = 0,
    RS256 = 1,
}

impl core::fmt::Debug for JwtAlgorithms {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            Self::HS256 => f.write_str("U1::HS256"),
            Self::RS256 => f.write_str("U1::RS256"),
        }
    }
}

roc_refcounted_noop_impl!(JwtAlgorithms);

#[derive(Clone, Debug, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(C)]
pub struct JwtValidation {
    pub algorithms: roc_std::RocList<JwtAlgorithms>,
    pub audience: roc_std::RocStr,
    pub issuer: roc_std::RocStr,
    pub leeway: u64,
    pub rejectExiringLessThan: u64,
    pub requiredClaims: roc_std::RocList<roc_std::RocStr>,
    pub subject: roc_std::RocStr,
    pub validateAud: bool,
    pub validateExp: bool,
    pub validateNbf: bool,
}

impl roc_std::RocRefcounted for JwtValidation {
    fn inc(&mut self) {
        self.algorithms.inc();
        self.audience.inc();
        self.issuer.inc();
        self.requiredClaims.inc();
        self.subject.inc();
    }
    fn dec(&mut self) {
        self.algorithms.dec();
        self.audience.dec();
        self.issuer.dec();
        self.requiredClaims.dec();
        self.subject.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}
