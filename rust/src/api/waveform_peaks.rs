//! Bounded, duration-independent recording peaks. Kept independent of the
//! decoder so metadata-free files use the same timeline as ordinary files.

pub(crate) struct WaveformPeaks {
    bins: Vec<f32>,
    span: u64,
    partial: f32,
    partial_frames: u64,
    frames: u64,
}

impl WaveformPeaks {
    const CAPACITY: usize = 8192;

    pub(crate) fn new() -> Self {
        Self { bins: Vec::new(), span: 1, partial: 0.0, partial_frames: 0, frames: 0 }
    }

    pub(crate) fn push(&mut self, peak: f32) {
        if peak.is_finite() { self.partial = self.partial.max(peak.abs()); }
        self.partial_frames += 1;
        self.frames += 1;
        if self.partial_frames == self.span {
            self.bins.push(self.partial);
            self.partial = 0.0;
            self.partial_frames = 0;
            if self.bins.len() == Self::CAPACITY {
                for i in 0..Self::CAPACITY / 2 {
                    self.bins[i] = self.bins[i * 2].max(self.bins[i * 2 + 1]);
                }
                self.bins.truncate(Self::CAPACITY / 2);
                self.span *= 2;
            }
        }
    }

    pub(crate) fn finish(mut self, buckets: usize) -> Vec<f32> {
        let buckets = buckets.max(1);
        let mut peaks = vec![0.0f32; buckets];
        if self.frames == 0 { return peaks; }
        if self.partial_frames > 0 { self.bins.push(self.partial); }
        for (i, peak) in self.bins.into_iter().enumerate() {
            let start = i as u64 * self.span;
            let end = (start + self.span).min(self.frames);
            let first = (start as u128 * buckets as u128 / self.frames as u128) as usize;
            let last = (end as u128 * buckets as u128)
                .div_ceil(self.frames as u128).saturating_sub(1) as usize;
            for value in &mut peaks[first.min(buckets - 1)..=last.min(buckets - 1)] {
                *value = value.max(peak);
            }
        }
        let maximum = peaks.iter().copied().fold(0.0f32, f32::max);
        if maximum > 0.0 { for peak in &mut peaks { *peak /= maximum; } }
        peaks
    }
}

#[cfg(test)]
mod tests {
    use super::WaveformPeaks;

    #[test]
    fn unknown_duration_covers_the_full_recording_and_preserves_a_quiet_break() {
        let mut waveform = WaveformPeaks::new();
        for i in 0..48_000 * 7 {
            waveform.push(if (96_000..192_000).contains(&i) { 0.0 } else { 0.5 });
        }
        let peaks = waveform.finish(240);
        assert_eq!(peaks.len(), 240);
        assert!(peaks[0] > 0.9 && peaks[239] > 0.9);
        assert!(peaks[75..130].iter().all(|&peak| peak == 0.0));
    }

    #[test]
    fn compaction_is_bounded_and_retains_an_isolated_final_transient() {
        let mut waveform = WaveformPeaks::new();
        for _ in 0..2_000_013 { waveform.push(0.0); }
        waveform.push(0.75);
        assert!(waveform.bins.len() < WaveformPeaks::CAPACITY);
        let peaks = waveform.finish(240);
        assert_eq!(peaks[239], 1.0);
        assert!(peaks[..230].iter().all(|&peak| peak == 0.0));
    }

    #[test]
    fn silence_short_clips_and_nonfinite_samples_remain_finite() {
        assert_eq!(WaveformPeaks::new().finish(3), vec![0.0; 3]);
        let mut waveform = WaveformPeaks::new();
        for peak in [0.0, f32::NAN, f32::INFINITY, 0.0] { waveform.push(peak); }
        assert!(waveform.finish(240).iter().all(|&peak| peak == 0.0));
        let mut short = WaveformPeaks::new();
        short.push(0.5);
        short.push(0.5);
        assert!(short.finish(240).iter().all(|&peak| peak == 1.0));
    }
}
