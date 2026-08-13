//! JSON stdin/stdout bridge for pqthreshold M2/M3 (threshold ML-DSA-44 / Mithril).

mod distributed;

use base64::{engine::general_purpose::STANDARD as B64, Engine};
use distributed::{
    aggregate_wfinals_from_reveals, binding_from_b64, combine_wire, decode_blobs_b64,
    decode_hashes_b64, pack_wfinals, round1_party, round2_party, round3_party,
    session_id_from_b64, session_id_from_binding, unpack_wfinals, validate_active,
};
use rand::{rngs::StdRng, RngCore, SeedableRng};
use serde::{Deserialize, Serialize};
use threshold_ml_dsa::coordinator;
use threshold_ml_dsa::params::PK_BYTES;
use threshold_ml_dsa::poly::PolyVecL;
use threshold_ml_dsa::sdk::ThresholdMlDsa44Sdk;
use threshold_ml_dsa::sign;
use threshold_ml_dsa::verify;

#[derive(Deserialize)]
#[serde(tag = "op")]
enum Request {
    #[serde(rename = "keygen")]
    Keygen { t: u8, n: u8, seed_hex: String },
    #[serde(rename = "threshold_sign")]
    ThresholdSign {
        t: u8,
        n: u8,
        seed_hex: String,
        active: Vec<u8>,
        message_b64: String,
        rng_seed_hex: Option<String>,
    },
    #[serde(rename = "wire_sign")]
    WireSign {
        t: u8,
        n: u8,
        seed_hex: String,
        active: Vec<u8>,
        message_b64: String,
        rng_seed_hex: Option<String>,
    },
    #[serde(rename = "derive_session_id")]
    DeriveSessionId {
        t: u8,
        n: u8,
        public_key_b64: String,
        active: Vec<u8>,
        message_b64: String,
        binding_b64: String,
    },
    #[serde(rename = "round1_party")]
    Round1Party {
        t: u8,
        n: u8,
        seed_hex: String,
        party_id: u8,
        active: Vec<u8>,
        message_b64: String,
        session_id_b64: String,
    },
    #[serde(rename = "round2_party")]
    Round2Party {
        t: u8,
        n: u8,
        seed_hex: String,
        party_id: u8,
        active: Vec<u8>,
        message_b64: String,
        session_id_b64: String,
        round1_hashes_b64: Vec<String>,
    },
    #[serde(rename = "aggregate_wfinals")]
    AggregateWfinals {
        t: u8,
        n: u8,
        reveals_b64: Vec<String>,
    },
    #[serde(rename = "round3_party")]
    Round3Party {
        t: u8,
        n: u8,
        seed_hex: String,
        party_id: u8,
        active: Vec<u8>,
        message_b64: String,
        session_id_b64: String,
        round1_hashes_b64: Vec<String>,
        round2_reveals_b64: Vec<String>,
        wfinals_b64: String,
    },
    #[serde(rename = "combine_wire")]
    CombineWire {
        t: u8,
        n: u8,
        public_key_b64: String,
        message_b64: String,
        wfinals_b64: String,
        round3_responses_b64: Vec<String>,
    },
    #[serde(rename = "verify")]
    Verify {
        public_key_b64: String,
        message_b64: String,
        signature_b64: String,
    },
}

#[derive(Serialize, Deserialize)]
struct WireRound1 {
    sender_index: u8,
    hash_b64: String,
}

#[derive(Serialize, Deserialize)]
struct WireRound2 {
    sender_index: u8,
    reveal_b64: String,
}

#[derive(Serialize, Deserialize)]
struct WireRound3 {
    sender_index: u8,
    response_b64: String,
}

#[derive(Serialize)]
struct KeygenResponse {
    public_key_b64: String,
    seed_hex: String,
    t: u8,
    n: u8,
}

#[derive(Serialize)]
struct SignResponse {
    signature_b64: String,
}

#[derive(Serialize)]
struct WireSignResponse {
    session_id_b64: String,
    round1: Vec<WireRound1>,
    round2: Vec<WireRound2>,
    round3: Vec<WireRound3>,
    signature_b64: String,
}

#[derive(Serialize)]
struct SessionIdResponse {
    session_id_b64: String,
}

#[derive(Serialize)]
struct Round1PartyResponse {
    hash_b64: String,
}

#[derive(Serialize)]
struct Round2PartyResponse {
    reveal_b64: String,
}

#[derive(Serialize)]
struct AggregateWfinalsResponse {
    wfinals_b64: String,
}

#[derive(Serialize)]
struct Round3PartyResponse {
    response_b64: String,
}

#[derive(Serialize)]
struct VerifyResponse {
    valid: bool,
}

#[derive(Serialize)]
struct ErrorResponse {
    error: String,
}

fn hex32(s: &str) -> Result<[u8; 32], String> {
    let bytes = hex::decode(s.trim()).map_err(|e| e.to_string())?;
    if bytes.len() != 32 {
        return Err(format!("expected 32-byte hex, got {} bytes", bytes.len()));
    }
    let mut out = [0u8; 32];
    out.copy_from_slice(&bytes);
    Ok(out)
}

fn make_rng(rng_seed_hex: Option<String>) -> StdRng {
    if let Some(rng_hex) = rng_seed_hex {
        let seed64 = hex::decode(rng_hex.trim()).unwrap_or_default();
        let mut arr = [0u8; 8];
        arr.copy_from_slice(&seed64[..8.min(seed64.len())]);
        StdRng::seed_from_u64(u64::from_le_bytes(arr))
    } else {
        let mut s = [0u8; 32];
        rand::thread_rng().fill_bytes(&mut s);
        StdRng::seed_from_u64(u64::from_le_bytes(s[..8].try_into().unwrap()))
    }
}

fn session_id_for(pk: &[u8], act: u8, msg: &[u8], rng: &mut StdRng) -> [u8; 32] {
    let mut session_entropy = [0u8; 32];
    rng.fill_bytes(&mut session_entropy);
    session_id_from_binding(pk, act, msg, &session_entropy)
}

fn load_sdk(seed_hex: &str, t: u8, n: u8) -> Result<ThresholdMlDsa44Sdk, String> {
    let seed = hex32(seed_hex)?;
    ThresholdMlDsa44Sdk::from_seed(&seed, t, n, 32).map_err(|e| format!("keygen: {e:?}"))
}

fn pack_z_response(zs: &[PolyVecL]) -> Vec<u8> {
    distributed::pack_z_response(zs)
}

fn run_wire_sign(
    sdk: &ThresholdMlDsa44Sdk,
    active: &[u8],
    msg: &[u8],
    rng: &mut StdRng,
) -> Result<WireSignResponse, String> {
    let params = sdk.params();
    let act = validate_active(active, params.n)?;
    let session_id = session_id_for(sdk.pk(), act, msg, rng);
    let k_reps = params.k_reps as usize;

    let mut rd1_out = Vec::new();
    let mut rd1_hashes: Vec<[u8; 32]> = Vec::new();
    let mut rd1_states: Vec<sign::StRound1> = Vec::new();

    for &party_id in active {
        let sk = sdk.party_key(party_id as usize).ok_or("missing party key")?;
        let mut party_rng = distributed::party_rng(&session_id, party_id);
        let (hash, st1) = sign::round1(sk, params, act, msg, &session_id, &mut party_rng)
            .map_err(|e| format!("round1: {e:?}"))?;
        rd1_out.push(WireRound1 {
            sender_index: party_id,
            hash_b64: B64.encode(hash),
        });
        rd1_hashes.push(hash);
        rd1_states.push(st1);
    }

    let mut rd2_out = Vec::new();
    let mut rd2_reveals: Vec<Vec<u8>> = Vec::new();
    let mut rd2_states: Vec<sign::StRound2> = Vec::new();

    for (idx, &party_id) in active.iter().enumerate() {
        let sk = sdk.party_key(party_id as usize).ok_or("missing party key")?;
        let (reveal, st2) = sign::round2(
            sk,
            act,
            msg,
            &session_id,
            &rd1_hashes,
            &rd1_hashes[idx],
            &rd1_states[idx],
            params,
        )
        .map_err(|e| format!("round2: {e:?}"))?;
        rd2_out.push(WireRound2 {
            sender_index: party_id,
            reveal_b64: B64.encode(&reveal),
        });
        rd2_reveals.push(reveal);
        rd2_states.push(st2);
    }

    let active_ids: Vec<u8> = active.to_vec();
    let wfinals = aggregate_wfinals_from_reveals(&rd2_reveals, k_reps)?;

    let mut rd3_out = Vec::new();
    let mut all_responses: Vec<Vec<PolyVecL>> = Vec::new();

    for (st1, (&party_id, st2)) in rd1_states
        .into_iter()
        .zip(active.iter().zip(rd2_states.iter()))
    {
        let sk = sdk.party_key(party_id as usize).ok_or("missing party key")?;
        let verified = sign::verify_all_round2_reveals(
            sk.tr(),
            &active_ids,
            act,
            msg,
            &session_id,
            &rd2_reveals,
            &rd1_hashes,
            k_reps,
        )
        .map_err(|e| format!("verify reveals: {e:?}"))?;
        let zs = sign::round3(sk, &wfinals, st1, st2, params, verified)
            .map_err(|e| format!("round3: {e:?}"))?;
        let packed = pack_z_response(&zs);
        rd3_out.push(WireRound3 {
            sender_index: party_id,
            response_b64: B64.encode(packed),
        });
        all_responses.push(zs);
    }

    let zfinals = coordinator::aggregate_responses(&all_responses, k_reps)
        .map_err(|e| format!("aggregate_responses: {e:?}"))?;
    let sig = coordinator::combine(sdk.pk(), msg, &wfinals, &zfinals, params)
        .map_err(|e| format!("combine: {e:?}"))?;
    if !verify::verify(&sig, msg, sdk.pk()) {
        return Err("combined signature failed verify".into());
    }

    Ok(WireSignResponse {
        session_id_b64: B64.encode(session_id),
        round1: rd1_out,
        round2: rd2_out,
        round3: rd3_out,
        signature_b64: B64.encode(sig),
    })
}

fn main() {
    if let Err(msg) = run() {
        let err = ErrorResponse { error: msg };
        println!("{}", serde_json::to_string(&err).unwrap());
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let mut input = String::new();
    std::io::Read::read_to_string(&mut std::io::stdin(), &mut input)
        .map_err(|e| e.to_string())?;
    let req: Request = serde_json::from_str(&input).map_err(|e| e.to_string())?;

    match req {
        Request::Keygen { t, n, seed_hex } => {
            let seed = hex32(&seed_hex)?;
            let sdk = ThresholdMlDsa44Sdk::from_seed(&seed, t, n, 32)
                .map_err(|e| format!("keygen: {e:?}"))?;
            let resp = KeygenResponse {
                public_key_b64: B64.encode(sdk.pk()),
                seed_hex: hex::encode(seed),
                t,
                n,
            };
            println!("{}", serde_json::to_string(&resp).unwrap());
        }
        Request::ThresholdSign {
            t,
            n,
            seed_hex,
            active,
            message_b64,
            rng_seed_hex,
        } => {
            let sdk = load_sdk(&seed_hex, t, n)?;
            let msg = B64.decode(message_b64.trim()).map_err(|e| e.to_string())?;
            let mut rng = make_rng(rng_seed_hex);
            let sig = sdk
                .threshold_sign(&active, &msg, &mut rng)
                .map_err(|e| format!("threshold_sign: {e:?}"))?;
            let resp = SignResponse {
                signature_b64: B64.encode(sig),
            };
            println!("{}", serde_json::to_string(&resp).unwrap());
        }
        Request::WireSign {
            t,
            n,
            seed_hex,
            active,
            message_b64,
            rng_seed_hex,
        } => {
            let sdk = load_sdk(&seed_hex, t, n)?;
            let msg = B64.decode(message_b64.trim()).map_err(|e| e.to_string())?;
            let mut rng = make_rng(rng_seed_hex);
            let resp = run_wire_sign(&sdk, &active, &msg, &mut rng)?;
            println!("{}", serde_json::to_string(&resp).unwrap());
        }
        Request::DeriveSessionId {
            t: _,
            n,
            public_key_b64,
            active,
            message_b64,
            binding_b64,
        } => {
            let pk = B64.decode(public_key_b64.trim()).map_err(|e| e.to_string())?;
            if pk.len() != PK_BYTES {
                return Err(format!("public key length {} != {PK_BYTES}", pk.len()));
            }
            let msg = B64.decode(message_b64.trim()).map_err(|e| e.to_string())?;
            let binding = binding_from_b64(&binding_b64)?;
            let act = validate_active(&active, n)?;
            let mut pk_arr = [0u8; PK_BYTES];
            pk_arr.copy_from_slice(&pk);
            let session_id = session_id_from_binding(&pk_arr, act, &msg, &binding);
            let resp = SessionIdResponse {
                session_id_b64: B64.encode(session_id),
            };
            println!("{}", serde_json::to_string(&resp).unwrap());
        }
        Request::Round1Party {
            t,
            n,
            seed_hex,
            party_id,
            active,
            message_b64,
            session_id_b64,
        } => {
            let sdk = load_sdk(&seed_hex, t, n)?;
            let msg = B64.decode(message_b64.trim()).map_err(|e| e.to_string())?;
            let session_id = session_id_from_b64(&session_id_b64)?;
            let act = validate_active(&active, n)?;
            let hash = round1_party(&sdk, party_id, act, &msg, &session_id)?;
            let resp = Round1PartyResponse {
                hash_b64: B64.encode(hash),
            };
            println!("{}", serde_json::to_string(&resp).unwrap());
        }
        Request::Round2Party {
            t,
            n,
            seed_hex,
            party_id,
            active,
            message_b64,
            session_id_b64,
            round1_hashes_b64,
        } => {
            let sdk = load_sdk(&seed_hex, t, n)?;
            let msg = B64.decode(message_b64.trim()).map_err(|e| e.to_string())?;
            let session_id = session_id_from_b64(&session_id_b64)?;
            let act = validate_active(&active, n)?;
            let hashes = decode_hashes_b64(&round1_hashes_b64)?;
            let reveal = round2_party(
                &sdk,
                party_id,
                act,
                &msg,
                &session_id,
                &active,
                &hashes,
            )?;
            let resp = Round2PartyResponse {
                reveal_b64: B64.encode(reveal),
            };
            println!("{}", serde_json::to_string(&resp).unwrap());
        }
        Request::AggregateWfinals {
            t,
            n,
            reveals_b64,
        } => {
            let params = threshold_ml_dsa::params::get_threshold_params(t, n)
                .ok_or_else(|| "invalid t/n".to_string())?;
            let reveals = decode_blobs_b64(&reveals_b64)?;
            let wfinals = aggregate_wfinals_from_reveals(&reveals, params.k_reps as usize)?;
            let resp = AggregateWfinalsResponse {
                wfinals_b64: B64.encode(pack_wfinals(&wfinals)),
            };
            println!("{}", serde_json::to_string(&resp).unwrap());
        }
        Request::Round3Party {
            t,
            n,
            seed_hex,
            party_id,
            active,
            message_b64,
            session_id_b64,
            round1_hashes_b64,
            round2_reveals_b64,
            wfinals_b64,
        } => {
            let sdk = load_sdk(&seed_hex, t, n)?;
            let msg = B64.decode(message_b64.trim()).map_err(|e| e.to_string())?;
            let session_id = session_id_from_b64(&session_id_b64)?;
            let act = validate_active(&active, n)?;
            let hashes = decode_hashes_b64(&round1_hashes_b64)?;
            let reveals = decode_blobs_b64(&round2_reveals_b64)?;
            let wfinals_bytes = B64.decode(wfinals_b64.trim()).map_err(|e| e.to_string())?;
            let wfinals = unpack_wfinals(&wfinals_bytes, sdk.params().k_reps as usize)?;
            let response = round3_party(
                &sdk,
                party_id,
                act,
                &msg,
                &session_id,
                &active,
                &hashes,
                &reveals,
                &wfinals,
            )?;
            let resp = Round3PartyResponse {
                response_b64: B64.encode(response),
            };
            println!("{}", serde_json::to_string(&resp).unwrap());
        }
        Request::CombineWire {
            t,
            n,
            public_key_b64,
            message_b64,
            wfinals_b64,
            round3_responses_b64,
        } => {
            let pk = B64.decode(public_key_b64.trim()).map_err(|e| e.to_string())?;
            if pk.len() != PK_BYTES {
                return Err(format!("public key length {} != {PK_BYTES}", pk.len()));
            }
            let msg = B64.decode(message_b64.trim()).map_err(|e| e.to_string())?;
            let wfinals_bytes = B64.decode(wfinals_b64.trim()).map_err(|e| e.to_string())?;
            let params = threshold_ml_dsa::params::get_threshold_params(t, n)
                .ok_or_else(|| "invalid t/n".to_string())?;
            let wfinals = unpack_wfinals(&wfinals_bytes, params.k_reps as usize)?;
            let responses = decode_blobs_b64(&round3_responses_b64)?;
            let mut pk_arr = [0u8; PK_BYTES];
            pk_arr.copy_from_slice(&pk);
            let sig = combine_wire(&pk_arr, &msg, t, n, &wfinals, &responses)?;
            let resp = SignResponse {
                signature_b64: B64.encode(sig),
            };
            println!("{}", serde_json::to_string(&resp).unwrap());
        }
        Request::Verify {
            public_key_b64,
            message_b64,
            signature_b64,
        } => {
            let pk = B64.decode(public_key_b64.trim()).map_err(|e| e.to_string())?;
            let msg = B64.decode(message_b64.trim()).map_err(|e| e.to_string())?;
            let sig = B64.decode(signature_b64.trim()).map_err(|e| e.to_string())?;
            let valid = verify::verify(&sig, &msg, pk.as_slice());
            let resp = VerifyResponse { valid };
            println!("{}", serde_json::to_string(&resp).unwrap());
        }
    }
    Ok(())
}
