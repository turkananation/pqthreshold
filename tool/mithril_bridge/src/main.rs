//! JSON stdin/stdout bridge for pqthreshold M2/M3 (threshold ML-DSA-44 / Mithril).

use base64::{engine::general_purpose::STANDARD as B64, Engine};
use rand::{rngs::StdRng, RngCore, SeedableRng};
use serde::{Deserialize, Serialize};
use sha3::digest::{ExtendableOutput, Update, XofReader};
use sha3::Shake256;
use threshold_ml_dsa::coordinator;
use threshold_ml_dsa::params::{L, POLYZ_PACKEDBYTES};
use threshold_ml_dsa::poly::{PolyVecK, PolyVecL};
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
    let mut h = Shake256::default();
    h.update(b"th-ml-dsa-session-v1");
    h.update(&session_entropy);
    h.update(pk);
    h.update(&[act]);
    h.update(msg);
    let mut session_id = [0u8; 32];
    h.finalize_xof().read(&mut session_id);
    session_id
}

fn validate_active(active: &[u8], n: u8) -> Result<u8, String> {
    if active.len() < 2 {
        return Err("need at least 2 active signers".into());
    }
    let mut act: u8 = 0;
    let mut prev: Option<u8> = None;
    for &id in active {
        if id >= n {
            return Err(format!("party id {id} >= n {n}"));
        }
        if let Some(p) = prev {
            if id <= p {
                return Err("active must be strictly sorted unique".into());
            }
        }
        act |= 1 << id;
        prev = Some(id);
    }
    Ok(act)
}

fn pack_z_response(zs: &[PolyVecL]) -> Vec<u8> {
    let slot_size = L * POLYZ_PACKEDBYTES;
    let mut buf = vec![0u8; zs.len() * slot_size];
    for (i, z) in zs.iter().enumerate() {
        let base = i * slot_size;
        for (j, poly) in z.polys.iter().enumerate() {
            let start = base + j * POLYZ_PACKEDBYTES;
            poly.pack_z(&mut buf[start..start + POLYZ_PACKEDBYTES]);
        }
    }
    buf
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
        let (hash, st1) = sign::round1(sk, params, act, msg, &session_id, rng)
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
    let packed_size = sign::pack_w_single_size();
    let mut all_reveals: Vec<Vec<PolyVecK>> = Vec::new();
    for reveal in &rd2_reveals {
        let mut party_ws = Vec::with_capacity(k_reps);
        for k in 0..k_reps {
            let start = k * packed_size;
            let end = start + packed_size;
            if end <= reveal.len() {
                party_ws.push(sign::unpack_w_single(&reveal[start..end]));
            }
        }
        all_reveals.push(party_ws);
    }
    let wfinals = coordinator::aggregate_commitments(&all_reveals, k_reps)
        .map_err(|e| format!("aggregate_commitments: {e:?}"))?;

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
            let seed = hex32(&seed_hex)?;
            let sdk = ThresholdMlDsa44Sdk::from_seed(&seed, t, n, 32)
                .map_err(|e| format!("keygen: {e:?}"))?;
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
            let seed = hex32(&seed_hex)?;
            let sdk = ThresholdMlDsa44Sdk::from_seed(&seed, t, n, 32)
                .map_err(|e| format!("keygen: {e:?}"))?;
            let msg = B64.decode(message_b64.trim()).map_err(|e| e.to_string())?;
            let mut rng = make_rng(rng_seed_hex);
            let resp = run_wire_sign(&sdk, &active, &msg, &mut rng)?;
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
