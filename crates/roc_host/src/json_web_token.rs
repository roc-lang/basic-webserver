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

fn jwt_error_to_roc(err: jwt::error::Error) -> RocStr {
    match err {
        jwt::error::Error::AlgorithmMismatch(..) => RocStr::from("AlgorithmMismatch"),
        jwt::error::Error::InvalidSignature => RocStr::from("InvalidSignature"),
        jwt::error::Error::Format => RocStr::from("BadFormat"),
        jwt::error::Error::Json(..) => RocStr::from("BadJson"),
        jwt::error::Error::NoClaimsComponent => RocStr::from("MissingClaims"),
        jwt::error::Error::NoHeaderComponent => RocStr::from("MissingHeader"),
        jwt::error::Error::NoKeyId => RocStr::from("MissingKeyId"),
        _ => RocStr::from(format!("{err}").to_string().as_str()),
    }
}

pub fn jwt_verify(jwt: &JWTFromRoc) -> RocResult<RocList<JWTToRoc>, RocStr> {
    use jwt::VerifyWithKey;

    let token_str = jwt.token.as_str().to_string();

    match jwt.algorithm() {
        AlgorithmType::Hs256 => {
            let maybe_key: Result<Hmac<Sha256>, RocStr> =
                Hmac::new_from_slice(&jwt.secret.as_bytes())
                    .map_err(|err| format!("{err}").as_str().into());

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
            let maybe_key: Result<Hmac<Sha384>, RocStr> =
                Hmac::new_from_slice(&jwt.secret.as_bytes())
                    .map_err(|err| format!("{err}").as_str().into());

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
            let maybe_key: Result<Hmac<Sha512>, RocStr> =
                Hmac::new_from_slice(&jwt.secret.as_bytes())
                    .map_err(|err| format!("{err}").as_str().into());

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
