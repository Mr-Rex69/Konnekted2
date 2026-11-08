//! Embedded Soulseek client for Android and foreground iPhone sessions. The protocol engine is an unmodified,
//! MIT-licensed soulseek-rs-lib pinned in Cargo.toml. This tiny C ABI avoids
//! regenerating Flutter Rust Bridge bindings for each protocol-library update.
//! Passwords never enter logs, arguments, preferences or returned JSON.
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use soulseek_rs::{Client, ClientSettings, DownloadStatus};
use std::{
    ffi::{c_char, CStr, CString},
    path::{Path, PathBuf},
    sync::{Arc, Mutex, OnceLock, atomic::{AtomicBool, AtomicU64, Ordering}},
    time::Duration,
};

static SESSION: OnceLock<Mutex<Option<Arc<Client>>>> = OnceLock::new();
fn session() -> &'static Mutex<Option<Arc<Client>>> {
    SESSION.get_or_init(|| Mutex::new(None))
}
static SUSPENDED: AtomicBool = AtomicBool::new(false);
static SESSION_EPOCH: AtomicU64 = AtomicU64::new(0);

// Called synchronously by UIKit before suspension, independently of Flutter's
// event loop. Cancellation is immediate; socket/thread teardown stays off UI.
#[no_mangle]
pub extern "C" fn lokal_soulseek_suspend() {
    SUSPENDED.store(true, Ordering::SeqCst);
    retire_session();
}
#[no_mangle]
pub extern "C" fn lokal_soulseek_resume() {
    SUSPENDED.store(false, Ordering::SeqCst);
}
fn retire_session() -> u64 {
    let (old, epoch) = {
        let mut slot = session().lock().unwrap_or_else(|e| e.into_inner());
        let epoch = SESSION_EPOCH.fetch_add(1, Ordering::SeqCst) + 1;
        (slot.take(), epoch)
    };
    if let Some(client) = old {
        client.cancel_handle().cancel();
        std::thread::spawn(move || drop(client));
    }
    epoch
}
fn current() -> Result<Arc<Client>, String> {
    session().lock().map_err(|_| "Soulseek session is unavailable".to_string())?
        .as_ref().cloned().ok_or_else(|| "Sign in to Soulseek first".to_string())
}
fn string<'a>(input: &'a Value, field: &str) -> Result<&'a str, String> {
    input.get(field).and_then(Value::as_str)
        .ok_or_else(|| format!("Missing {field}"))
}
fn safe_basename(path: &str) -> Result<&str, String> {
    let name = path.rsplit(['/', '\\']).next().unwrap_or("");
    if name.is_empty() || name == "." || name == ".."
        || name.chars().any(|c| c.is_control()) {
        return Err("Invalid remote filename".into());
    }
    Ok(name)
}

fn shareable_directory(path: &str) -> Result<String, String> {
    let chosen = Path::new(path);
    // Resolving the selected root first would hide a symlink pointing at an
    // unrelated private folder. Refuse leaf symlinks as well as nested ones.
    if chosen.symlink_metadata().map_err(|e| e.to_string())?
        .file_type().is_symlink() {
        return Err("The selected music folder is a symbolic link. Choose the real folder before sharing.".into());
    }
    let root = chosen.canonicalize().map_err(|e| e.to_string())?;
    if !root.is_dir() { return Err("Shared music folder is not a directory".into()); }
    // Upstream scan_many() currently follows symlinks via DirEntry::metadata,
    // so reject a root with links rather than accidentally share outside it.
    let mut pending = vec![root.clone()];
    let mut inspected = 0usize;
    while let Some(dir) = pending.pop() {
        let entries = std::fs::read_dir(&dir).map_err(|e| e.to_string())?;
        for entry in entries {
            let entry = entry.map_err(|e| e.to_string())?;
            let kind = entry.file_type().map_err(|e| e.to_string())?;
            if kind.is_symlink() {
                return Err("This music folder contains symbolic links. Remove them before sharing, to avoid exposing files outside the folder.".into());
            }
            if kind.is_dir() { pending.push(entry.path()); }
            inspected += 1;
            if inspected > 500_000 {
                return Err("Shared folder contains too many entries. Choose a smaller music folder.".into());
            }
        }
    }
    Ok(root.to_string_lossy().into_owned())
}

fn file_extension(path: &str) -> &str {
    path.rsplit('.').next().unwrap_or("").trim()
}
fn is_audio(path: &str) -> bool {
    matches!(file_extension(path).to_ascii_lowercase().as_str(),
        "flac" | "mp3" | "wav" | "m4a" | "aac" | "ogg" | "opus"
        | "wma" | "alac" | "aif" | "aiff" | "ape" | "wv" | "dsf" | "dff")
}
fn search_score(file: &soulseek_rs::File, slots: u8, speed: u32) -> i64 {
    let extension = file_extension(&file.name).to_ascii_lowercase();
    let quality = match extension.as_str() {
        "flac" | "wav" | "aiff" | "aif" | "ape" | "wv" | "dsf" | "dff" => 100,
        "m4a" | "alac" => 60,
        _ => 10,
    };
    i64::from(quality) + if slots > 0 { 100 } else { 0 }
        + i64::from(speed / 100_000).min(100)
}
fn session_status(username: &str, loss: Option<&str>, folders: u32, files: u32) -> Value {
    // Session loss is data, not a failed FFI invocation. Dart must be able to
    // update its connection flag and allow secure-credential reconnection.
    json!({"loggedIn": loss.is_none(), "username": username, "sessionLoss": loss,
        "sharedFolders": folders, "sharedFiles": files, "engineVersion": "20.0.0"})
}
fn execute(input: Value) -> Result<Value, String> {
    let action = string(&input, "action")?;
    match action {
        "login" => {
            let username = string(&input, "username")?.trim();
            let password = string(&input, "password")?;
            if username.is_empty() || username.len() > 80 || password.is_empty() {
                return Err("Enter a Soulseek username and password".into());
            }
            // Close our previous session before logging in (one network session
            // per username). Other operations hold an Arc until they finish.
            let epoch = retire_session();
            if SUSPENDED.load(Ordering::SeqCst) {
                return Err("Keep Lokal open to use Soulseek on iPhone".into());
            }
            let shared = input.get("share").and_then(Value::as_str).unwrap_or("").trim();
            let shared_directories = if shared.is_empty() { Vec::new() } else {
                let dir = Path::new(shared);
                if !dir.is_absolute() || !dir.is_dir() {
                    return Err("The music folder is not accessible as a filesystem directory. Choose a readable local folder or disable sharing.".into());
                }
                vec![shareable_directory(shared)?]
            };
            let mut settings = ClientSettings::new(username, password);
            // Let the OS allocate an unused port. Peer-connection fallback is
            // handled by the library when NAT/firewall blocks incoming traffic.
            settings.listen_port = 0;
            settings.shared_directories = shared_directories;
            let mut client = Client::with_settings(settings);
            client.connect().map_err(|e| format!("Cannot connect to the Soulseek server: {e}"))?;
            if !client.login().map_err(|e| format!("Soulseek login timed out or failed: {e}"))? {
                return Err("Soulseek rejected this username/password. The username may already be taken.".into());
            }
            let (folders, files) = client.shared_counts();
            let mut slot = session().lock().map_err(|_| "Session lock failed")?;
            if SUSPENDED.load(Ordering::SeqCst) || SESSION_EPOCH.load(Ordering::SeqCst) != epoch {
                client.cancel_handle().cancel();
                return Err("Soulseek connection was retired".into());
            }
            *slot = Some(Arc::new(client));
            Ok(json!({"loggedIn": true, "username": username, "sharedFolders": folders,
                "sharedFiles": files, "engineVersion": "20.0.0"}))
        }
        "logout" => {
            retire_session();
            Ok(json!({"loggedIn": false}))
        }
        "status" => {
            let maybe = session().lock().map_err(|_| "Session lock failed")?.clone();
            let Some(client) = maybe else { return Ok(json!({"loggedIn": false, "engineVersion": "20.0.0"})); };
            let loss = client.session_loss().map(|x| x.to_string());
            let (folders, files) = client.shared_counts();
            Ok(session_status(client.username(), loss.as_deref(), folders, files))
        }
        "search" => {
            let query = string(&input, "query")?.trim();
            if query.chars().count() < 2 || query.chars().count() > 160 {
                return Err("Search for at least two characters (maximum 160)".into());
            }
            let client = current()?;
            if let Some(loss) = client.session_loss() {
                return Err(format!("Soulseek disconnected: {loss}"));
            }
            let responses = client.search(query, Duration::from_secs(9))
                .map_err(|e| format!("Soulseek search failed: {e}"))?;
            let users = responses.len();
            let mut found: Vec<(i64, Value)> = Vec::new();
            for response in responses {
                for file in response.files {
                    if !is_audio(&file.name) || safe_basename(&file.name).is_err() { continue; }
                    let bitrate = file.attribs.get(&0).copied();
                    let duration = file.attribs.get(&1).copied();
                    let sample_rate = file.attribs.get(&4).copied();
                    let bit_depth = file.attribs.get(&5).copied();
                    let score = search_score(&file, response.slots, response.speed);
                    let ext = file_extension(&file.name).to_ascii_uppercase();
                    found.push((score, json!({"username": file.username,
                        "filename": file.name, "size": file.size,
                        "bitrate": bitrate, "duration": duration, "sampleRate": sample_rate,
                        "bitDepth": bit_depth, "extension": ext,
                        "freeSlot": response.slots > 0, "speed": response.speed, "score": score})));
                }
            }
            found.sort_unstable_by(|a,b| b.0.cmp(&a.0));
            found.truncate(700);
            Ok(json!({"users": users, "results": found.into_iter().map(|(_,f)| f).collect::<Vec<_>>()}))
        }
        "download" => {
            let username = string(&input, "username")?;
            let remote = string(&input, "filename")?;
            let name = safe_basename(remote)?;
            if !is_audio(name) { return Err("That file is not a supported audio format".into()); }
            let size = input.get("size").and_then(Value::as_u64)
                .filter(|size| *size > 0).ok_or("Invalid file size")?;
            let staging = Path::new(string(&input, "staging")?);
            if !staging.is_absolute() || !staging.is_dir() {
                return Err("Soulseek download directory is unavailable".into());
            }
            let digest = Sha256::digest(format!("{username}\0{remote}").as_bytes());
            let key: String = digest[..12].iter().map(|b| format!("{b:02x}")).collect();
            let folder = staging.join(key);
            std::fs::create_dir_all(&folder).map_err(|e| e.to_string())?;
            let folder_string = folder.to_string_lossy().into_owned();
            let client = current()?;
            // Retry a failed or cancelled transfer with its same .part staging
            // directory. The protocol engine validates/resumes partial bytes.
            let _ = client.remove_download(username, remote);
            let (download, _) = client.download(remote.to_owned(), username.to_owned(),
                size, folder_string).map_err(|e| e.to_string())?;
            Ok(json!({"id": download.token, "path": folder.join(name).to_string_lossy()}))
        }
        "transfers" => {
            let client = current()?;
            let transfers: Vec<Value> = client.get_all_downloads().iter().map(|d| {
                let (status, error) = match &d.status {
                    DownloadStatus::Queued => ("queued", None),
                    DownloadStatus::InProgress { .. } => ("downloading", None),
                    DownloadStatus::Paused { .. } => ("paused", None),
                    DownloadStatus::Completed => ("completed", None),
                    DownloadStatus::Cancelled => ("cancelled", None),
                    DownloadStatus::Failed(reason) => ("failed", reason.as_deref()),
                    DownloadStatus::TimedOut => ("failed", Some("Peer timed out")),
                };
                let name = safe_basename(&d.filename).unwrap_or("unknown");
                json!({"id": d.token, "username": d.username, "filename": d.filename,
                    "path": PathBuf::from(&d.download_directory).join(name).to_string_lossy(),
                    "status": status, "error": error, "size": d.size,
                    "bytes": d.bytes_downloaded(), "speed": d.speed_bytes_per_sec(),
                    "queuePosition": d.queue_position})
            }).collect();
            Ok(json!({"transfers": transfers}))
        }
        "cancel" | "pause" | "resume" => {
            let client = current()?;
            let username = string(&input, "username")?;
            let filename = string(&input, "filename")?;
            let ok = match action {
                "cancel" => client.cancel_download(username, filename),
                "pause" => client.pause_download(username, filename),
                _ => client.resume_download(username, filename),
            };
            Ok(json!({"ok": ok}))
        }
        "shares" => {
            let client = current()?;
            let folder = input.get("folder").and_then(Value::as_str).unwrap_or("").trim();
            if !folder.is_empty() && (!Path::new(folder).is_absolute() || !Path::new(folder).is_dir()) {
                return Err("Cannot read the selected folder for sharing".into());
            }
            client.set_shared_directories(if folder.is_empty() { vec![] } else {
                vec![shareable_directory(folder)?]
            }).map_err(|e| e.to_string())?;
            let (folders, files) = client.shared_counts();
            Ok(json!({"sharedFolders": folders, "sharedFiles": files}))
        }
        "uploads" => {
            let client = current()?;
            Ok(json!({"uploads": client.uploads().iter().map(|u| json!({
                "username": u.username, "filename": u.filename, "size": u.size,
                "bytes": u.bytes_sent, "speed": u.speed_bytes_per_sec,
                "status": format!("{:?}", u.status)
            })).collect::<Vec<_>>() }))
        }
        _ => Err("Unknown Soulseek action".into()),
    }
}
// Android can stop peer uploads even when Flutter's activity has gone away.
// Invoked by the foreground service on task dismissal / Android timeout.
#[cfg(target_os = "android")]
#[no_mangle]
pub extern "system" fn Java_com_mossapps_flick_SoulseekForegroundService_stopSoulseekNative(
    _env: jni::JNIEnv<'_>,
    _class: jni::objects::JClass<'_>,
) {
    let old = session().lock().ok().and_then(|mut slot| slot.take());
    drop(old);
}

/// Caller owns the returned NUL-terminated JSON. Free with lokal_soulseek_free.
#[no_mangle]
pub unsafe extern "C" fn lokal_soulseek_invoke(request: *const c_char) -> *mut c_char {
    let response = std::panic::catch_unwind(|| {
        if request.is_null() { return json!({"error":"Missing request"}); }
        // SAFETY: Dart owns a live UTF-8 NUL-terminated buffer for this call.
        let text = unsafe { CStr::from_ptr(request) }.to_str();
        let result = text.map_err(|_| "Invalid UTF-8".to_string())
            .and_then(|text| serde_json::from_str::<Value>(text).map_err(|_| "Invalid request JSON".to_string()))
            .and_then(execute);
        match result { Ok(v) => v, Err(e) => json!({"error": e}) }
    }).unwrap_or_else(|_| json!({"error": "Soulseek engine failed"}));
    CString::new(response.to_string()).unwrap_or_default().into_raw()
}
#[no_mangle]
pub unsafe extern "C" fn lokal_soulseek_free(value: *mut c_char) {
    if !value.is_null() { drop(unsafe { CString::from_raw(value) }); }
}

#[cfg(test)]
mod tests {
    use super::{safe_basename, is_audio, shareable_directory, session_status};
    #[test]
    fn suspension_cancels_held_native_client_and_retires_late_login_authority() {
        use super::*;
        lokal_soulseek_resume();
        let client = Arc::new(Client::with_settings(ClientSettings::new("fixture", "not-a-real-password")));
        let held = client.clone();
        *session().lock().unwrap() = Some(client);
        let before = SESSION_EPOCH.load(Ordering::SeqCst);
        lokal_soulseek_suspend();
        assert!(held.cancel_handle().is_cancelled());
        assert!(session().lock().unwrap().is_none());
        assert!(SESSION_EPOCH.load(Ordering::SeqCst) > before);
        assert!(execute(json!({"action":"login","username":"fixture","password":"unused"}))
            .unwrap_err().contains("Keep Lokal open"));
        lokal_soulseek_resume();
        assert_eq!(execute(json!({"action":"status"})).unwrap()["loggedIn"], false);
    }

    #[test]
    fn remote_paths_cannot_traverse_download_directories() {
        assert_eq!(safe_basename(r"C:\album\track.flac").unwrap(), "track.flac");
        assert!(safe_basename("../..").is_err());
        assert!(safe_basename("a/b/\u{0}").is_err());
        assert!(is_audio("recording.FLAC"));
        assert!(!is_audio("executable.apk"));
    }

    #[test]
    fn lost_session_remains_a_status_response_not_an_ffi_error() {
        let report = session_status("tester", Some("server disconnected"), 2, 15);
        assert_eq!(report["loggedIn"], false);
        assert_eq!(report["sessionLoss"], "server disconnected");
        assert_eq!(report["sharedFiles"], 15);
        assert!(report.get("error").is_none());
        assert_eq!(session_status("tester", None, 0, 0)["loggedIn"], true);
    }

    #[cfg(unix)]
    #[test]
    fn symlinks_in_shared_folders_are_rejected() {
        use std::os::unix::fs::symlink;
        let root = std::env::temp_dir().join(format!("lokal-soulseek-symlink-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).unwrap();
        symlink("/etc", root.join("external")).unwrap();
        assert!(shareable_directory(root.to_str().unwrap())
            .unwrap_err().contains("symbolic links"));
        std::fs::remove_file(root.join("external")).unwrap();

        // A symlink selected as the library root must not be canonicalized
        // silently and advertised to the P2P network.
        let alias = root.with_extension("soulseek-link");
        let _ = std::fs::remove_file(&alias);
        symlink(&root, &alias).unwrap();
        assert!(shareable_directory(alias.to_str().unwrap())
            .unwrap_err().contains("symbolic link"));
        std::fs::remove_file(alias).unwrap();
        std::fs::remove_dir_all(root).unwrap();
    }
}
