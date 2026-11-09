//! E4: the git-backed index — `index/<escaped-segments>/<leaf>.json`
//! files holding one JSONL entry per published version
//! (`{version,commit,h1,tag}`). `oxl get` consults the index named by
//! OXLMODINDEX (a local dir or a git URL) before direct git; a found
//! entry pins the fetch to `commit` and its `h1` is verified against
//! the fetched tree. `oxl publish` appends entries after pushing the
//! module tag. Protocol contract:
//! docs/specs/2026-11-08-monorepo-oxl-extra/items/index-protocol.md

use crate::{modcache, semver};
use std::path::{Path, PathBuf};
use std::process::Command;

pub struct Entry {
    pub version: String,
    pub commit: String,
    pub h1: String,
    pub tag: String,
}

fn alpha_ok(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '.' || c == '_' || c == '-'
}

/// index eligibility + key derivation, or None when the module path
/// cannot live in an index (such paths keep the direct-git fallback —
/// and can never derive a key that selects another module's entry).
/// Rules per index-protocol.md: per-segment alphabet +
/// check_component + no `.git` (any case) + non-leaf `.json` reject +
/// 200-byte escaped segment + 240-byte total path.
pub fn key(mp: &str) -> Option<String> {
    let segs: Vec<&str> = mp.split('/').collect();
    if segs.len() < 2 {
        return None;
    }
    let last = segs.len() - 1;
    let mut out = String::from("index/");
    for (i, s) in segs.iter().enumerate() {
        if s.is_empty() || !s.chars().all(alpha_ok) || modcache::check_component(s).is_err() {
            return None;
        }
        if s.eq_ignore_ascii_case(".git") {
            return None;
        }
        if i != last && s.to_ascii_lowercase().ends_with(".json") {
            return None; // a non-leaf `x.json` must be a dir beside a `x`-derived file
        }
        let esc = modcache::escape_path(s);
        if esc.len() > 200 {
            return None;
        }
        out.push_str(&esc);
        out.push('/');
    }
    out.pop(); // trailing '/' of the leaf
    out.push_str(".json");
    if out.len() > 240 {
        return None;
    }
    Some(out)
}

fn jget<'a>(line: &'a str, k: &str) -> Option<&'a str> {
    // "k":"<v>" — values we emit contain no escapes; a lenient scan is
    // enough for entries we wrote (foreign lines fail field checks)
    let pat = format!("\"{k}\":\"");
    let i = line.find(&pat)? + pat.len();
    Some(&line[i..line[i..].find('"')? + i])
}

/// one JSONL entry; malformed lines are an error, not a skip — a
/// corrupt index must not silently redirect fetches
fn parse_entry(line: &str) -> Result<Entry, String> {
    let t = line.trim();
    if !(t.starts_with('{') && t.ends_with('}')) {
        return Err(format!("malformed index entry {t:?}"));
    }
    let grab = |k: &str| -> Result<String, String> {
        jget(t, k)
            .map(|s| s.to_string())
            .ok_or_else(|| format!("index entry missing {k:?}: {t:?}"))
    };
    let e = Entry {
        version: grab("version")?,
        commit: grab("commit")?,
        h1: grab("h1")?,
        tag: grab("tag")?,
    };
    if semver::parse(&e.version).is_none() || e.commit.is_empty() || e.h1.is_empty() {
        return Err(format!("malformed index entry {t:?}"));
    }
    Ok(e)
}

fn entry_line(e: &Entry) -> String {
    format!(
        "{{\"version\":\"{}\",\"commit\":\"{}\",\"h1\":\"{}\",\"tag\":\"{}\"}}",
        e.version, e.commit, e.h1, e.tag
    )
}

/// OXLMODINDEX → where the index tree is read from. A local path is
/// used in place; a git URL is shallow-cloned to a temp dir (the
/// caller keeps it alive for the read).
pub enum Root {
    Local(PathBuf),
    Cloned(PathBuf), // temp dir to clean up after use
}

impl Root {
    pub fn path(&self) -> &Path {
        match self {
            Root::Local(p) | Root::Cloned(p) => p,
        }
    }
}

pub fn root() -> Result<Option<Root>, String> {
    let v = match std::env::var("OXLMODINDEX") {
        Ok(v) if !v.is_empty() => v,
        _ => return Ok(None),
    };
    if v.contains("://") || v.starts_with("git@") {
        let tmp = std::env::temp_dir().join(format!("oxl-idx-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&tmp);
        let out = Command::new("git")
            .args(["clone", "--depth", "1", &v])
            .arg(&tmp)
            .env("GIT_TERMINAL_PROMPT", "0")
            .output()
            .map_err(|e| format!("git clone: {e}"))?;
        if !out.status.success() {
            let err = String::from_utf8_lossy(&out.stderr).trim().to_string();
            return Err(format!("cloning OXLMODINDEX {v}: {err}"));
        }
        return Ok(Some(Root::Cloned(tmp)));
    }
    Ok(Some(Root::Local(PathBuf::from(v))))
}

/// every entry under `key`; a missing file is an empty list (the
/// module simply isn't indexed — the caller falls back to git)
pub fn load(root: &Root, key: &str) -> Result<Vec<Entry>, String> {
    let p = root.path().join(key);
    let text = match std::fs::read_to_string(&p) {
        Ok(t) => t,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(e) => return Err(format!("{}: {e}", p.display())),
    };
    text.lines()
        .filter(|l| !l.trim().is_empty())
        .map(parse_entry)
        .collect()
}

/// the entry answering `query`: `latest` resolves the max semver, an
/// exact `vX.Y.Z` names it; anything else (branches, shas, pseudo-
/// versions) can't be index-served and returns None → git fallback.
pub fn select(ents: &[Entry], query: &str) -> Option<Entry> {
    let pick = if query.is_empty() || query == "latest" {
        ents.iter()
            .filter_map(|e| semver::parse(&e.version).map(|v| (v, e)))
            .max_by(|a, b| semver::compare(&a.0, &b.0))
            .map(|(_, e)| e)
    } else {
        ents.iter().find(|e| e.version == query)
    }?;
    Some(Entry {
        version: pick.version.clone(),
        commit: pick.commit.clone(),
        h1: pick.h1.clone(),
        tag: pick.tag.clone(),
    })
}

/// `tag` back to the repo-relative module root: `extra/v1.2.3` →
/// `extra`, `a/b/v1` → `a/b`, `v1.2.3` → "" (a root-module tag is the
/// bare version)
pub fn tag_subdir(tag: &str, ver: &str) -> Option<String> {
    if tag == ver {
        return Some(String::new());
    }
    tag.strip_suffix(ver)
        .and_then(|p| p.strip_suffix('/'))
        .map(|s| s.to_string())
}

/// what `publish` appends — idempotent: the same line is already-
/// published success, a conflicting same-version entry is rejected.
pub enum Append {
    Added,
    Already,
}

pub fn append(dir: &Path, key: &str, e: &Entry) -> Result<Append, String> {
    let p = dir.join(key);
    let old = std::fs::read_to_string(&p).unwrap_or_default();
    for line in old.lines() {
        if line.trim().is_empty() {
            continue;
        }
        let x = parse_entry(line)?;
        if x.version == e.version {
            if x.commit == e.commit && x.h1 == e.h1 && x.tag == e.tag {
                return Ok(Append::Already);
            }
            return Err(format!(
                "index already has {} with different content ({}@{}); refusing to publish a divergent entry",
                e.version, x.commit, x.h1
            ));
        }
    }
    if let Some(par) = p.parent() {
        std::fs::create_dir_all(par).map_err(|e| format!("{}: {e}", par.display()))?;
    }
    use std::io::Write;
    let mut f = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&p)
        .map_err(|e| format!("{}: {e}", p.display()))?;
    // a file that lacks a trailing newline needs a separator before
    // the entry, or this append would glue onto the last line
    if !old.is_empty() && !old.ends_with('\n') {
        writeln!(f).map_err(|x| format!("{}: {x}", p.display()))?;
    }
    writeln!(f, "{}", entry_line(e)).map_err(|x| format!("{}: {x}", p.display()))?;
    Ok(Append::Added)
}
