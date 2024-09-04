// use hmac::{Hmac, Mac};
// use jsonwebtoken::{decode, jwk::Jwk, Algorithm, DecodingKey, TokenData, Validation};
// // use jwt::PKeyWithDigest;
// // use jwt::VerifyWithKey;
// // use sha2::{Sha384, Sha512};
// use std::collections::HashMap;

// pub fn jwt_header(token: &str) -> Result<jwt::Header, serde_json::Error> {
//     // let header_str = match token.split(".").next() {
//     //     None => "".into(),
//     //     Some(header_str) => header_str,
//     // };

//     // let header_json = base64::decode_block(header_str).unwrap();

//     // serde_json::from_slice(header_json.as_slice())
//     todo!()
// }

// pub fn jwt_verify_hs256(
//     token: &str,
//     secret: &str,
// ) -> Result<TokenData<HashMap<String, serde_json::Value>>, jsonwebtoken::errors::Error> {
//     let mut validation = Validation::default();
//     validation.validate_exp = false;
//     decode::<HashMap<String, serde_json::Value>>(
//         &token,
//         &DecodingKey::from_rsa_pem(secret.as_bytes()).unwrap(),
//         &validation,
//     )
// }

// pub fn jwt_verify_hs384(
//     token: &str,
//     secret: &str,
// ) -> Result<HashMap<String, serde_json::Value>, jwt::Error> {
//     let key: Hmac<Sha384> = Hmac::new_from_slice(secret.as_bytes())?;
//     let claims: HashMap<String, serde_json::Value> = token.verify_with_key(&key)?;
//     Ok(claims)
// }

// pub fn jwt_verify_hs512(
//     token: &str,
//     secret: &str,
// ) -> Result<HashMap<String, serde_json::Value>, jwt::Error> {
//     let key: Hmac<Sha512> = Hmac::new_from_slice(secret.as_bytes())?;
//     let claims: HashMap<String, serde_json::Value> = token.verify_with_key(&key)?;
//     Ok(claims)
// }

// /// secret is the public key in PEM format
// pub fn jwt_verify_rs256(
//     token: &str,
//     secret: &str,
// ) -> Result<HashMap<String, serde_json::Value>, jwt::Error> {
//     // let key = PKeyWithDigest {
//     //     digest: MessageDigest::sha256(),
//     //     key: PKey::public_key_from_pem(secret.as_bytes()).unwrap(),
//     // };
//     // let claims: HashMap<String, serde_json::Value> = token.verify_with_key(&key)?;
//     // Ok(claims)
//     todo!()
// }

// /// secret is the public key in PEM format
// pub fn jwt_verify_rs384(
//     token: &str,
//     secret: &str,
// ) -> Result<HashMap<String, serde_json::Value>, jwt::Error> {
//     // let key = PKeyWithDigest {
//     //     digest: MessageDigest::sha384(),
//     //     key: PKey::public_key_from_pem(secret.as_bytes()).unwrap(),
//     // };
//     // let claims: HashMap<String, serde_json::Value> = token.verify_with_key(&key)?;
//     // Ok(claims)
//     todo!()
// }

// /// secret is the public key in PEM format
// pub fn jwt_verify_rs512(
//     token: &str,
//     secret: &str,
// ) -> Result<HashMap<String, serde_json::Value>, jwt::Error> {
//     // let key = PKeyWithDigest {
//     //     digest: MessageDigest::sha512(),
//     //     key: PKey::public_key_from_pem(secret.as_bytes()).unwrap(),
//     // };
//     // let claims: HashMap<String, serde_json::Value> = token.verify_with_key(&key)?;
//     // Ok(claims)
//     todo!()
// }

#[cfg(test)]
mod tests {
    use jsonwebtoken::{Algorithm, DecodingKey, Validation};
    use std::collections::HashMap;

    const TEST_PEM: &str = indoc::indoc!(
        r#"-----BEGIN PUBLIC KEY-----
        MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAu1SU1LfVLPHCozMxH2Mo
        4lgOEePzNm0tRgeLezV6ffAt0gunVTLw7onLRnrq0/IzW7yWR7QkrmBL7jTKEn5u
        +qKhbwKfBstIs+bMY2Zkp18gnTxKLxoS2tFczGkPLPgizskuemMghRniWaoLcyeh
        kd3qqGElvW/VDL5AaWTg0nLVkjRo9z+40RQzuVaE8AkAFmxZzow3x+VJYKdjykkJ
        0iT9wCS0DRTXu269V264Vf/3jvredZiKRkgwlL9xNAwxXFg0x/XFw005UWVRIkdg
        cKWTjpBP2dPwVZ4WWC+9aGVd+Gyn1o0CLelf4rEjGoXbAAEgAqeGUxrcIlbjXfbc
        mwIDAQAB
        -----END PUBLIC KEY-----"#
    );

    fn assert_test_claims(claims: HashMap<String, serde_json::Value>) {
        assert_eq!(claims.get("sub"), Some(&serde_json::json!("1234567890")));
        assert_eq!(claims.get("name"), Some(&serde_json::json!("John Doe")));
        assert_eq!(claims.get("iat"), Some(&serde_json::json!(1516239022u64)));
    }

    #[test]
    fn verify_hs256() {
        let token = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiYWRtaW4iOnRydWUsImlhdCI6MTUxNjIzOTAyMiwiZXhwIjoyMzIzNDIzNDIyfQ.EjA3bLXxf0h_PixFJUrrcCcAHdg_QPAjlw3Gm-Q8ZEDvpjLr6CAQ9iCkUSrl6GUJVxL2oGrSOA_hucHxhPmhwOAbVYWoqHa8ikvN4NovzDeeqOqBywkwSEjWBhrq8HgsyByel5brJtqjfSJY9_YCYOEfBPOBpbbgbiEaKQ0Zobw9qf-M2owXOmogdDNPtwztv-iALLEsQakO_IIGe4O8YvWwQS8Whs0QKX7X9iCybHdyApQmAgr6QWSsU86xtogQQmG9_kBf0efdqn13zxbBds5KyL8mHw0ljHgMQxY5mTfekRgM8AFd8tGDd_izMBPu4v3gmw3PBjtetV4WKiI6ag";
        let secret = "-----BEGIN PUBLIC KEY-----
        MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAu1SU1LfVLPHCozMxH2Mo
        4lgOEePzNm0tRgeLezV6ffAt0gunVTLw7onLRnrq0/IzW7yWR7QkrmBL7jTKEn5u
        +qKhbwKfBstIs+bMY2Zkp18gnTxKLxoS2tFczGkPLPgizskuemMghRniWaoLcyeh
        kd3qqGElvW/VDL5AaWTg0nLVkjRo9z+40RQzuVaE8AkAFmxZzow3x+VJYKdjykkJ
        0iT9wCS0DRTXu269V264Vf/3jvredZiKRkgwlL9xNAwxXFg0x/XFw005UWVRIkdg
        cKWTjpBP2dPwVZ4WWC+9aGVd+Gyn1o0CLelf4rEjGoXbAAEgAqeGUxrcIlbjXfbc
        mwIDAQAB
        -----END PUBLIC KEY-----";
        let secret = DecodingKey::from_rsa_pem(secret.as_bytes()).unwrap();
        let validation = Validation::new(Algorithm::RS256);

        let decoded_token = jsonwebtoken::decode::<HashMap<String, serde_json::Value>>(
            &token,
            &secret,
            &validation,
        )
        .unwrap();

        assert_test_claims(decoded_token.claims);
    }

    // #[test]
    // fn verify_hs384() {
    //     let token = "eyJhbGciOiJIUzM4NCIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.i4IWr5r6Q597a6yCTJsvlkhHlt_AB1FP72Pd29hoelY32rfX0xT7KnVPf_UNaugJ";
    //     let secret = "shhh_very_secret";
    //     let claims = jwt_verify_hs384(token, secret).unwrap();
    //     assert_test_claims(claims);

    //     let header = jwt_header(token).unwrap();
    //     assert_eq!(header.algorithm, AlgorithmType::Hs384);
    // }

    // #[test]
    // fn verify_hs512() {
    //     let token = "eyJhbGciOiJIUzUxMiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.4ZkXv8eVAJZI2BzlEp0RBHPOPoDp-wLoJEj-hSHZvaBpnDIlIcK_XsUBf9hJ3MFikbqBgtAwMA1aq_k15IcVlg";
    //     let secret = "shhh_very_secret";
    //     let claims = jwt_verify_hs512(token, secret).unwrap();
    //     assert_test_claims(claims);

    //     let header = jwt_header(token).unwrap();
    //     assert_eq!(header.algorithm, AlgorithmType::Hs512);
    // }

    // #[test]
    // fn verify_rs256() {
    //     let token = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.Eci61G6w4zh_u9oOCk_v1M_sKcgk0svOmW4ZsL-rt4ojGUH2QY110bQTYNwbEVlowW7phCg7vluX_MCKVwJkxJT6tMk2Ij3Plad96Jf2G2mMsKbxkC-prvjvQkBFYWrYnKWClPBRCyIcG0dVfBvqZ8Mro3t5bX59IKwQ3WZ7AtGBYz5BSiBlrKkp6J1UmP_bFV3eEzIHEFgzRa3pbr4ol4TK6SnAoF88rLr2NhEz9vpdHglUMlOBQiqcZwqrI-Z4XDyDzvnrpujIToiepq9bCimPgVkP54VoZzy-mMSGbthYpLqsL_4MQXaI1Uf_wKFAUuAtzVn4-ebgsKOpvKNzVA";
    //     let secret = TEST_PEM;
    //     let claims = jwt_verify_rs256(token, secret).unwrap();
    //     assert_test_claims(claims);

    //     let header = jwt_header(token).unwrap();
    //     assert_eq!(header.algorithm, AlgorithmType::Rs256);
    // }

    // #[test]
    // fn verify_rs384() {
    //     let token = "eyJhbGciOiJSUzM4NCIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.oPvWzaCp8xUpt5mHhPSn0qLsZfCFj0NVmb4mz4dFQPCCMj-F5zVn9e3zZoj0lIXWM8rxB69QHC3Er47mtDt3BKgysTL3BvvV89kD6UjLoUcAI3lwj0mi7acLoE27i1_TnIBqWNRPAsdvTDawNE0_4lvI5bxEWQCqisJwxCoMDIeJsmDzfyApgU_SAFSVULxXwU2VewaxdQB-41OZdWwUEAxh81iB6DFWrqd2CaJkUYoWjgYpeWsyeC2m_-ECGrHGEz1nKTm9c7BaPxurz7fHD7RJd9Wpx-mKDVsfspO9quWb_OLeGGbxTtAomMvjQjut56kx2fqTleDnNDh_0GE88w";
    //     let secret = TEST_PEM;
    //     let claims = jwt_verify_rs384(token, secret).unwrap();
    //     assert_test_claims(claims);

    //     let header = jwt_header(token).unwrap();
    //     assert_eq!(header.algorithm, AlgorithmType::Rs384);
    // }

    // #[test]
    // fn verify_rs512() {
    //     let token = "eyJhbGciOiJSUzUxMiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.kEZmDAnHHU_0bcGXMd5LA7vF87yQgXNaioPHP4lU4O3JJYuZ54fJdv3HT58xk-MFEDuWro_5fvNIp2VM-PlkZvYWrhQkJ-c-seoSa3ANq_PciC3bGfzYHEdjAE71GrAMI4FlcAGsq3ChkOnCTFqjWDmVwaRYCgMsFQ-U5cjvFhndFMizrkRljTF4v5oFdWytV_J-UafPtNdQXcGND1M74DqObnTHhZHg8aDfNzZcvnIeKcDVGUlUEL5ia1kPMrVhCtOAOJmEU8ivCdWWzt-jMQBf7cZeoCzDKHG72ysTTCfRoBVc1_SrQTHcHDiiBeW9nCazMLkltyP5NeawR_RNlg";
    //     let secret = TEST_PEM;
    //     let claims = jwt_verify_rs512(token, secret).unwrap();
    //     assert_test_claims(claims);

    //     let header = jwt_header(token).unwrap();
    //     assert_eq!(header.algorithm, AlgorithmType::Rs512);
    // }
}
