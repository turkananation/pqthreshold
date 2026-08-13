//! Per-party ML-DSA signing rounds (M3+ distributed).
//!
//! Round state is recomputed from a deterministic party RNG derived from
//! `session_id` and `party_id`, so officers persist only metadata checkpoints.

use base64::{engine::general_purpose::STANDARD as B64, Engine};
use rand::{rngs::StdRng, SeedableRng};
use sha3::digest::{ExtendableOutput, Update, XofReader};
use sha3::Shake256;
use threshold_ml_dsa::coordinator;
use threshold_ml_dsa::params::{get_threshold_params, L, N, PK_BYTES};
use threshold_ml_dsa::poly::{PolyVecK, PolyVecL};
use threshold_ml_dsa::sdk::ThresholdMlDsa44Sdk;
use threshold_ml_dsa::sign;
use threshold_ml_dsa::verify;

pub fn session_id_from_binding(
    pk: &[u8],
    act: u8,
    msg: &[u8],
    binding: &[u8; 32],
) -> [u8; 32] {
    let mut h = Shake256::default();
    h.update(b"th-ml-dsa-session-v1");
    h.update(binding);
    h.update(pk);
    h.update(&[act]);
    h.update(msg);
    let mut session_id = [0u8; 32];
    h.finalize_xof().read(&mut session_id);
    session_id
}

pub fn party_rng(session_id: &[u8; 32], party_id: u8) -> StdRng {
    let mut h = Shake256::default();
    h.update(b"pqth-ml-dsa-party-rng-v1");
    h.update(session_id);
    h.update(&[party_id]);
    let mut seed = [0u8; 32];
    h.finalize_xof().read(&mut seed);
    StdRng::from_seed(seed)
}

pub fn validate_active(active: &[u8], n: u8) -> Result<u8, String> {
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

pub fn pack_z_response(zs: &[PolyVecL]) -> Vec<u8> {
    let mut buf = Vec::with_capacity(zs.len() * L * N * 4);
    for z in zs {
        for poly in &z.polys {
            for &coeff in &poly.coeffs {
                buf.extend_from_slice(&coeff.to_le_bytes());
            }
        }
    }
    buf
}

pub fn unpack_z_response(buf: &[u8], k_reps: usize) -> Result<Vec<PolyVecL>, String> {
    let slot_size = L * N * 4;
    let need = k_reps * slot_size;
    if buf.len() < need {
        return Err(format!("z response too short: {} < {need}", buf.len()));
    }
    let mut out = Vec::with_capacity(k_reps);
    for k in 0..k_reps {
        let base = k * slot_size;
        let mut z = PolyVecL::zero();
        for (j, poly) in z.polys.iter_mut().enumerate() {
            for (c_idx, coeff) in poly.coeffs.iter_mut().enumerate() {
                let off = base + (j * N + c_idx) * 4;
                *coeff = i32::from_le_bytes(
                    buf[off..off + 4]
                        .try_into()
                        .map_err(|_| "truncated z coefficient")?,
                );
            }
        }
        out.push(z);
    }
    Ok(out)
}

pub fn pack_wfinals(wfinals: &[PolyVecK]) -> Vec<u8> {
    let slot = sign::pack_w_single_size();
    let mut buf = vec![0u8; wfinals.len() * slot];
    for (i, w) in wfinals.iter().enumerate() {
        let packed = sign::pack_w_single(w);
        buf[i * slot..(i + 1) * slot].copy_from_slice(&packed);
    }
    buf
}

pub fn unpack_wfinals(buf: &[u8], k_reps: usize) -> Result<Vec<PolyVecK>, String> {
    let slot = sign::pack_w_single_size();
    let need = k_reps * slot;
    if buf.len() < need {
        return Err(format!("wfinals too short: {} < {need}", buf.len()));
    }
    Ok((0..k_reps)
        .map(|i| sign::unpack_w_single(&buf[i * slot..(i + 1) * slot]))
        .collect())
}

fn party_round1(
    sdk: &ThresholdMlDsa44Sdk,
    party_id: u8,
    act: u8,
    msg: &[u8],
    session_id: &[u8; 32],
) -> Result<([u8; 32], sign::StRound1), String> {
    let sk = sdk
        .party_key(party_id as usize)
        .ok_or_else(|| format!("missing party key {party_id}"))?;
    let mut rng = party_rng(session_id, party_id);
    sign::round1(sk, sdk.params(), act, msg, session_id, &mut rng)
        .map_err(|e| format!("round1: {e:?}"))
}

fn party_round2(
    sdk: &ThresholdMlDsa44Sdk,
    party_id: u8,
    act: u8,
    msg: &[u8],
    session_id: &[u8; 32],
    active: &[u8],
    round1_hashes: &[[u8; 32]],
) -> Result<(Vec<u8>, sign::StRound2), String> {
    if active.len() != round1_hashes.len() {
        return Err("active/hashes length mismatch".into());
    }
    let idx = active
        .iter()
        .position(|&id| id == party_id)
        .ok_or_else(|| format!("party {party_id} not in active set"))?;
    let (own_hash, st1) = party_round1(sdk, party_id, act, msg, session_id)?;
    if own_hash != round1_hashes[idx] {
        return Err("round1 hash mismatch on deterministic replay".into());
    }
    let sk = sdk
        .party_key(party_id as usize)
        .ok_or_else(|| format!("missing party key {party_id}"))?;
    sign::round2(
        sk,
        act,
        msg,
        session_id,
        round1_hashes,
        &round1_hashes[idx],
        &st1,
        sdk.params(),
    )
    .map_err(|e| format!("round2: {e:?}"))
}

pub fn aggregate_wfinals_from_reveals(
    reveals: &[Vec<u8>],
    k_reps: usize,
) -> Result<Vec<PolyVecK>, String> {
    let packed_size = sign::pack_w_single_size();
    let mut all_reveals = Vec::with_capacity(reveals.len());
    for reveal in reveals {
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
    coordinator::aggregate_commitments(&all_reveals, k_reps)
        .map_err(|e| format!("aggregate_commitments: {e:?}"))
}

pub fn round1_party(
    sdk: &ThresholdMlDsa44Sdk,
    party_id: u8,
    act: u8,
    msg: &[u8],
    session_id: &[u8; 32],
) -> Result<[u8; 32], String> {
    let (hash, _st1) = party_round1(sdk, party_id, act, msg, session_id)?;
    Ok(hash)
}

pub fn round2_party(
    sdk: &ThresholdMlDsa44Sdk,
    party_id: u8,
    act: u8,
    msg: &[u8],
    session_id: &[u8; 32],
    active: &[u8],
    round1_hashes: &[[u8; 32]],
) -> Result<Vec<u8>, String> {
    let (reveal, _st2) = party_round2(
        sdk,
        party_id,
        act,
        msg,
        session_id,
        active,
        round1_hashes,
    )?;
    Ok(reveal)
}

pub fn round3_party(
    sdk: &ThresholdMlDsa44Sdk,
    party_id: u8,
    act: u8,
    msg: &[u8],
    session_id: &[u8; 32],
    active: &[u8],
    round1_hashes: &[[u8; 32]],
    round2_reveals: &[Vec<u8>],
    wfinals: &[PolyVecK],
) -> Result<Vec<u8>, String> {
    if active.len() != round1_hashes.len() || active.len() != round2_reveals.len() {
        return Err("active/hashes/reveals length mismatch".into());
    }
    let (_, st1) = party_round1(sdk, party_id, act, msg, session_id)?;
    let (_, st2) = party_round2(
        sdk,
        party_id,
        act,
        msg,
        session_id,
        active,
        round1_hashes,
    )?;
    let sk = sdk
        .party_key(party_id as usize)
        .ok_or_else(|| format!("missing party key {party_id}"))?;
    let verified = sign::verify_all_round2_reveals(
        sk.tr(),
        active,
        act,
        msg,
        session_id,
        round2_reveals,
        round1_hashes,
        sdk.params().k_reps as usize,
    )
    .map_err(|e| format!("verify reveals: {e:?}"))?;
    let zs = sign::round3(sk, wfinals, st1, &st2, sdk.params(), verified)
        .map_err(|e| format!("round3: {e:?}"))?;
    Ok(pack_z_response(&zs))
}

pub fn combine_wire(
    pk: &[u8; PK_BYTES],
    msg: &[u8],
    t: u8,
    n: u8,
    wfinals: &[PolyVecK],
    responses: &[Vec<u8>],
) -> Result<Vec<u8>, String> {
    let params = get_threshold_params(t, n).ok_or_else(|| "invalid t/n".to_string())?;
    let k_reps = params.k_reps as usize;
    let mut all_responses = Vec::with_capacity(responses.len());
    for packed in responses {
        all_responses.push(unpack_z_response(packed, k_reps)?);
    }
    let zfinals = coordinator::aggregate_responses(&all_responses, k_reps)
        .map_err(|e| format!("aggregate_responses: {e:?}"))?;
    let sig = coordinator::combine(pk, msg, wfinals, &zfinals, &params)
        .map_err(|e| format!("combine: {e:?}"))?;
    if !verify::verify(&sig, msg, pk) {
        return Err("combined signature failed verify".into());
    }
    Ok(sig.to_vec())
}

pub fn decode_hashes_b64(values: &[String]) -> Result<Vec<[u8; 32]>, String> {
    values
        .iter()
        .map(|s| {
            let bytes = B64.decode(s.trim()).map_err(|e| e.to_string())?;
            if bytes.len() != 32 {
                return Err(format!("expected 32-byte hash, got {}", bytes.len()));
            }
            let mut out = [0u8; 32];
            out.copy_from_slice(&bytes);
            Ok(out)
        })
        .collect()
}

pub fn decode_blobs_b64(values: &[String]) -> Result<Vec<Vec<u8>>, String> {
    values
        .iter()
        .map(|s| B64.decode(s.trim()).map_err(|e| e.to_string()))
        .collect()
}

pub fn session_id_from_b64(s: &str) -> Result<[u8; 32], String> {
    let bytes = B64.decode(s.trim()).map_err(|e| e.to_string())?;
    if bytes.len() != 32 {
        return Err(format!("session_id must be 32 bytes, got {}", bytes.len()));
    }
    let mut out = [0u8; 32];
    out.copy_from_slice(&bytes);
    Ok(out)
}

pub fn binding_from_b64(s: &str) -> Result<[u8; 32], String> {
    session_id_from_b64(s)
}
