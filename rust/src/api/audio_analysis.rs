//! Audio analysis bridge: single-pass decode → waveform peaks + BS.1770
//! loudness + true peak + DR + LRA + clipping. No PCM retained — everything
//! is computed in one streaming pass and returned as small summaries.

use std::collections::VecDeque;
use std::fs::File;
use std::path::Path;

use symphonia::core::codecs::audio::{AudioDecoderOptions, CODEC_ID_NULL_AUDIO};
use symphonia::core::codecs::CodecParameters;
use symphonia::core::formats::probe::Hint;
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;

pub struct AudioAnalysisResult {
    pub peaks: Vec<f32>,
    pub lufs: Option<f64>,
    pub true_peak_db: Option<f64>,
    pub dr: Option<f64>,
    pub lra: Option<f64>,
    pub clipping: bool,
}

// ---------------------------------------------------------------------------
// Biquad filter
// ---------------------------------------------------------------------------

struct Biquad {
    b0: f64,
    b1: f64,
    b2: f64,
    a1: f64,
    a2: f64,
    z1: f64,
    z2: f64,
}

impl Biquad {
    fn new(b: [f64; 3], a: [f64; 2]) -> Self {
        Self { b0: b[0], b1: b[1], b2: b[2], a1: a[0], a2: a[1], z1: 0.0, z2: 0.0 }
    }

    #[inline]
    fn process(&mut self, x: f64) -> f64 {
        let y = self.b0 * x + self.z1;
        self.z1 = self.b1 * x - self.a1 * y + self.z2;
        self.z2 = self.b2 * x - self.a2 * y;
        y
    }
}

// BS.1770-4 K-filter coefficients (designed for 48 kHz).
// ponytail: used as-is at all sample rates; error is small at 44.1 kHz and
// increases at 88.2/96/176.4/192 kHz. Add bilinear-transform warping if
// mastering-grade accuracy is needed.
const K_S1_B: [f64; 3] = [1.53512485958697, -2.69169618940638, 1.19839281085285];
const K_S1_A: [f64; 2] = [-1.69065929318241, 0.73248077421585];
const K_S2_B: [f64; 3] = [1.0, -2.0, 1.0];
const K_S2_A: [f64; 2] = [-1.99004745483398, 0.990072250366629];

// ---------------------------------------------------------------------------
// BS.1770 gating (integrated loudness + LRA)
// ---------------------------------------------------------------------------

/// BS.1770-4 integrated loudness with absolute + relative gating.
fn integrated_loudness(block_msqs: &[f64]) -> Option<f64> {
    if block_msqs.is_empty() {
        return None;
    }
    let abs_gate = 10f64.powf((-70.0 + 0.691) / 10.0);
    let gated: Vec<f64> = block_msqs.iter().filter(|&&m| m > abs_gate).copied().collect();
    if gated.is_empty() {
        return None;
    }
    let mean = gated.iter().sum::<f64>() / gated.len() as f64;
    // Relative gate: mean − 10 LU → mean_msq / 10.
    let rel_gate = mean * 0.1;
    let rel_gated: Vec<f64> = gated.iter().filter(|&&m| m > rel_gate).copied().collect();
    if rel_gated.is_empty() {
        return None;
    }
    let final_mean = rel_gated.iter().sum::<f64>() / rel_gated.len() as f64;
    Some(-0.691 + 10.0 * final_mean.log10())
}

/// Loudness range: P95 − P10 of block loudness after absolute + relative (−20 LU) gating.
fn loudness_range(block_msqs: &[f64]) -> Option<f64> {
    if block_msqs.len() < 4 {
        return None;
    }
    let abs_gate = 10f64.powf((-70.0 + 0.691) / 10.0);
    let mut lufs_vals: Vec<f64> = block_msqs
        .iter()
        .filter(|&&m| m > abs_gate)
        .map(|&m| -0.691 + 10.0 * m.log10())
        .collect();
    if lufs_vals.len() < 4 {
        return None;
    }
    let mean = lufs_vals.iter().sum::<f64>() / lufs_vals.len() as f64;
    lufs_vals.retain(|&l| l > mean - 20.0);
    if lufs_vals.len() < 4 {
        return None;
    }
    lufs_vals.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let p10 = lufs_vals[((lufs_vals.len() as f64 - 1.0) * 0.10).round() as usize];
    let p95 = lufs_vals[((lufs_vals.len() as f64 - 1.0) * 0.95).round() as usize];
    Some(p95 - p10)
}

// ---------------------------------------------------------------------------
// Main analysis
// ---------------------------------------------------------------------------

/// Decode `path` once, computing waveform peaks + BS.1770 metrics.
/// Returns `None` for unsupported/unreachable files — callers treat that as a
/// silent skip.
///
/// `peak_buckets` controls the waveform resolution (typ. 240).
pub fn analyze_audio_file(path: String, peak_buckets: u32) -> Option<AudioAnalysisResult> {
    let path_obj = Path::new(&path);

    // DSD and WavPack go through their own decoders (Phase 2.6); skip for now.
    if let Some(ext) = path_obj.extension().and_then(|e| e.to_str()) {
        match ext.to_lowercase().as_str() {
            "dsf" | "dff" | "wv" => return None,
            _ => {}
        }
    }

    let file = File::open(path_obj).ok()?;
    let mss = MediaSourceStream::new(Box::new(file), Default::default());
    let mut hint = Hint::new();
    if let Some(ext) = path_obj.extension().and_then(|e| e.to_str()) {
        hint.with_extension(ext);
    }

    let probed = symphonia::default::get_probe()
        .probe(
            &hint,
            mss,
            FormatOptions::default(),
            MetadataOptions::default(),
        )
        .ok()?;

    let codec_params = {
        let track = probed.tracks().iter().find(|t| {
            matches!(
                &t.codec_params,
                Some(CodecParameters::Audio(p)) if p.codec != CODEC_ID_NULL_AUDIO
            )
        })?;
        let params = match &track.codec_params {
            Some(CodecParameters::Audio(p)) => p.clone(),
            _ => return None,
        };
        params
    };
    let sr = codec_params.sample_rate.unwrap_or(44100) as f64;
    let ch = codec_params
        .channels
        .as_ref()
        .map(|c| c.count())
        .unwrap_or(1)
        .min(2);

    let mut decoder = symphonia::default::get_codecs()
        .make_audio_decoder(&codec_params, &AudioDecoderOptions::default())
        .ok()?;

    let mut format_ctx = probed;

    // K-filter biquads per channel.
    let mut kfilters: Vec<[Biquad; 2]> = (0..ch)
        .map(|_| [Biquad::new(K_S1_B, K_S1_A), Biquad::new(K_S2_B, K_S2_A)])
        .collect();

    // LUFS block state: 400 ms blocks, 100 ms hop (75 % overlap).
    let block_size = (0.4 * sr) as usize;
    let hop = (0.1 * sr) as usize;
    let mut ring: VecDeque<f64> = VecDeque::with_capacity(block_size + 1);
    let mut ring_sum: f64 = 0.0;
    let mut since_hop: usize = 0;
    let mut block_msqs: Vec<f64> = Vec::new();

    // DR state: 3 s blocks, channel 0.
    let dr_block = (3.0 * sr) as usize;
    let mut dr_peak: f64 = 0.0;
    let mut dr_sq: f64 = 0.0;
    let mut dr_n: usize = 0;
    let mut dr_vals: Vec<f64> = Vec::new();

    // True peak & clipping.
    let mut tp: f64 = 0.0;
    let mut prev = vec![0.0f64; ch];
    let mut clips: u64 = 0;

    // Peaks.
    let mut waveform = super::waveform_peaks::WaveformPeaks::new();

    let mut interleaved: Vec<f32> = Vec::new();
    loop {
        let packet = match format_ctx.next_packet() {
            Ok(Some(p)) => p,
            Ok(None) => break,
            Err(_) => break,
        };

        let decoded = match decoder.decode(&packet) {
            Ok(d) => d,
            Err(_) => continue,
        };

        let buf_ch = decoded.spec().channels().count().max(1);
        decoded.copy_to_vec_interleaved::<f32>(&mut interleaved);
        let nf = decoded.frames();

        for f in 0..nf {
            let s0 = interleaved[f * buf_ch] as f64;
            let abs0 = s0.abs();

            let mut wss = 0.0;
            for c in 0..ch {
                let s = if c == 0 {
                    s0
                } else {
                    interleaved[f * buf_ch + c] as f64
                };
                let a = s.abs();

                // K-filter.
                let [ref mut s1, ref mut s2] = kfilters[c];
                let filt = s2.process(s1.process(s));
                wss += filt * filt;

                // True peak (ponytail: ×4 linear-interp approximation).
                if a > tp {
                    tp = a;
                }
                for &fr in &[0.25f64, 0.5, 0.75] {
                    let v = (prev[c] + (s - prev[c]) * fr).abs();
                    if v > tp {
                        tp = v;
                    }
                }
                prev[c] = s;

                // Clipping.
                if a >= 0.9999 {
                    clips += 1;
                }
            }

            // Describe every channel, independently of the playback mix or
            // gain. A recording with a silent left channel still has audio.
            waveform.push(interleaved[f * buf_ch..(f + 1) * buf_ch]
                .iter().map(|sample| sample.abs()).fold(0.0f32, f32::max));

            // LUFS ring.
            ring_sum += wss;
            ring.push_back(wss);
            if ring.len() > block_size {
                ring_sum -= ring.pop_front().unwrap();
            }
            since_hop += 1;
            if since_hop >= hop && ring.len() >= block_size {
                block_msqs.push(ring_sum / block_size as f64);
                since_hop = 0;
            }

            // DR (channel 0).
            if abs0 > dr_peak {
                dr_peak = abs0;
            }
            dr_sq += s0 * s0;
            dr_n += 1;
            if dr_n >= dr_block {
                let rms = (dr_sq / dr_n as f64).sqrt();
                if rms > 0.0 && dr_peak > 0.0 {
                    dr_vals.push(20.0 * (dr_peak / rms).log10());
                }
                dr_peak = 0.0;
                dr_sq = 0.0;
                dr_n = 0;
            }

        }
    }

    // -- Finalize peaks --
    let peaks = waveform.finish(peak_buckets.max(1) as usize);

    // -- Finalize DR: flush partial block, then top-20 % average --
    if dr_n > 0 {
        let rms = (dr_sq / dr_n as f64).sqrt();
        if rms > 0.0 && dr_peak > 0.0 {
            dr_vals.push(20.0 * (dr_peak / rms).log10());
        }
    }
    let dr = if dr_vals.is_empty() {
        None
    } else {
        dr_vals.sort_by(|a, b| b.partial_cmp(a).unwrap());
        let top = (dr_vals.len() / 5).max(1);
        Some(dr_vals[..top].iter().sum::<f64>() / top as f64)
    };

    let true_peak_db = if tp > 0.0 { Some(20.0 * tp.log10()) } else { None };
    let lufs = integrated_loudness(&block_msqs);
    let lra = loudness_range(&block_msqs);

    Some(AudioAnalysisResult {
        peaks,
        lufs,
        true_peak_db,
        dr,
        lra,
        clipping: clips > 10,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::f64::consts::PI;

    /// Generate a 48 kHz stereo WAV with a sine at known amplitude.
    fn write_sine_wav(dir: &std::path::Path, name: &str, freq: f64, amp: f64, secs: f64) -> String {
        let sr: u32 = 48000;
        let n = (secs * sr as f64) as usize;
        let path = dir.join(name);

        let mut wtr = hound::WavWriter::create(&path, hound::WavSpec {
            channels: 2,
            sample_rate: sr,
            bits_per_sample: 16,
            sample_format: hound::SampleFormat::Int,
        })
        .unwrap();

        for i in 0..n {
            let t = i as f64 / sr as f64;
            let s = (t * freq * 2.0 * PI).sin() * amp;
            let s16 = (s * 32767.0) as i16;
            wtr.write_sample(s16).unwrap();
            wtr.write_sample(s16).unwrap();
        }
        wtr.finalize().unwrap();

        path.to_string_lossy().into_owned()
    }

    fn write_square_wav(dir: &std::path::Path, name: &str, amp: f64, secs: f64) -> String {
        let sr: u32 = 48000;
        let n = (secs * sr as f64) as usize;
        let path = dir.join(name);

        let mut wtr = hound::WavWriter::create(&path, hound::WavSpec {
            channels: 2,
            sample_rate: sr,
            bits_per_sample: 16,
            sample_format: hound::SampleFormat::Int,
        })
        .unwrap();

        let period = sr as usize / 1000; // 1 kHz square
        for i in 0..n {
            let s = if (i / period) % 2 == 0 { amp } else { -amp };
            let s16 = (s * 32767.0) as i16;
            wtr.write_sample(s16).unwrap();
            wtr.write_sample(s16).unwrap();
        }
        wtr.finalize().unwrap();

        path.to_string_lossy().into_owned()
    }

    #[test]
    fn sine_peaks_and_lufs() {
        let dir = std::env::temp_dir().join("flick_test_analysis");
        std::fs::create_dir_all(&dir).unwrap();
        let path = write_sine_wav(&dir, "sine.wav", 1000.0, 0.5, 3.0);

        let result = analyze_audio_file(path, 240).expect("analysis should succeed");

        // Peaks: 240 buckets, all normalised 0..1, at least one non-zero.
        assert_eq!(result.peaks.len(), 240);
        assert!(result.peaks.iter().any(|&p| p > 0.5));
        assert!(result.peaks.iter().all(|&p| p >= 0.0 && p <= 1.0));

        // LUFS: a 1 kHz sine at -6.02 dBFS RMS ≈ -6.71 LUFS (mono weighting
        // on stereo with identical channels ≈ -6.71 LUFS). Allow ±2 LU.
        let lufs = result.lufs.expect("lufs should be present");
        assert!(
            (lufs - (-6.7)).abs() < 2.0,
            "lufs={lufs}, expected ≈ -6.7"
        );

        // True peak should be near -6.02 dB (sine at 0.5 amplitude).
        let tp = result.true_peak_db.expect("true peak should be present");
        assert!(
            (tp - (-6.02)).abs() < 1.0,
            "true_peak_db={tp}, expected ≈ -6.02"
        );

        // Not clipping.
        assert!(!result.clipping);
    }

    #[test]
    fn square_clipping() {
        let dir = std::env::temp_dir().join("flick_test_analysis");
        std::fs::create_dir_all(&dir).unwrap();
        let path = write_square_wav(&dir, "square.wav", 1.0, 2.0);

        let result = analyze_audio_file(path, 240).expect("analysis should succeed");

        // Full-scale square: clipping detected.
        assert!(result.clipping);

        // True peak ≈ 0 dB.
        let tp = result.true_peak_db.expect("true peak should be present");
        assert!(tp.abs() < 0.5, "true_peak_db={tp}, expected ≈ 0.0");
    }

    #[test]
    fn right_channel_and_final_audio_reach_the_waveform() {
        let dir = std::env::temp_dir().join("flick_test_analysis");
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("right-channel-waveform.wav");
        let mut writer = hound::WavWriter::create(&path, hound::WavSpec {
            channels: 2, sample_rate: 48_000, bits_per_sample: 16,
            sample_format: hound::SampleFormat::Int,
        }).unwrap();
        for frame in 0..144_000 {
            let sample = if (48_000..96_000).contains(&frame) { 0i16 } else { 16000i16 };
            writer.write_sample(0i16).unwrap();
            writer.write_sample(sample).unwrap();
        }
        writer.finalize().unwrap();
        let result = analyze_audio_file(path.to_string_lossy().into_owned(), 240).unwrap();
        assert!(result.peaks[..70].iter().all(|&peak| peak > 0.9));
        assert!(result.peaks[90..150].iter().all(|&peak| peak == 0.0));
        assert!(result.peaks[170..].iter().all(|&peak| peak > 0.9));
    }

    #[test]
    fn unsupported_format_returns_none() {
        let result = analyze_audio_file("/tmp/nonexistent.dsf".into(), 240);
        assert!(result.is_none());
    }
}
