//! V2: the `oxl get` fetch path — a thin git veneer (clone --bare into
//! a temp dir, rev-parse/describe/archive in it), semver query
//! resolution, and pseudo-version derivation. `git` is a documented
//! toolchain dependency for `get` only; private repos work through
//! git's own auth (ssh agent, credential helpers).

use crate::semver;
use std::path::Path;
use std::process::Command;

fn git(repo: &Path, args: &[&str]) -> Result<String, String> {
    let out = Command::new("git")
        .args(args)
        .current_dir(repo)
        .env("TZ", "UTC")
        .env("GIT_TERMINAL_PROMPT", "0") // never block on a tty — auth failures must error
        .output()
        .map_err(|e| format!("git {}: {e}", args.join(" ")))?;
    if !out.status.success() {
        let err = String::from_utf8_lossy(&out.stderr).trim().to_string();
        return Err(format!("git {}: {err}", args.join(" ")));
    }
    Ok(String::from_utf8_lossy(&out.stdout).into_owned())
}

/// module path -> repo URL: an explicit scheme or scp-style `git@`
/// passes through; a bare host/path gets https://
pub fn repo_url(path: &str) -> String {
    if path.contains("://") || path.starts_with("git@") {
        path.to_string()
    } else {
        format!("https://{path}")
    }
}

pub struct Fetched {
    pub ver: String,
    pub tar: Vec<u8>,
    pub manifest: Vec<u8>,
    /// repo-relative module root — "" for a module at the repo root,
    /// "extra" / "a/b" for a subdirectory module
    pub subdir: String,
}

/// resolve `query` against `url` and return the selected version plus
/// the canonical `git archive` of its subtree. One bare clone serves
/// both. `subdir` is the repo-relative module root ("" or "extra" /
/// "a/b") — it selects the `<subdir>/v*` tag series and slices the
/// archive + manifest to that subtree.
pub fn fetch(url: &str, path: &str, query: &str, subdir: &str) -> Result<Fetched, String> {
    let tmp = std::env::temp_dir().join(format!("oxl-get-{}-{}", std::process::id(), sanitize(path)));
    let _ = std::fs::remove_dir_all(&tmp);
    std::fs::create_dir_all(&tmp).map_err(|e| e.to_string())?;
    let res = (|| {
        Command::new("git")
            .args(["clone", "--bare", "--quiet", url])
            .arg(&tmp)
            .env("GIT_TERMINAL_PROMPT", "0")
            .output()
            .map_err(|e| format!("git clone {url}: {e}"))
            .and_then(|o| {
                if o.status.success() {
                    Ok(())
                } else {
                    Err(format!(
                        "git clone {url}: {}",
                        String::from_utf8_lossy(&o.stderr).trim()
                    ))
                }
            })?;
        let pfx = if subdir.is_empty() {
            String::new()
        } else {
            format!("{subdir}/")
        };
        let (sha, ver) = resolve(&tmp, query, &pfx)?;
        // archive only the module subtree — entries keep the subdir
        // prefix, so extraction roots the module at <dest>/<subdir>
        let mut args = vec!["archive", "--format=tar", sha.as_str()];
        if !subdir.is_empty() {
            args.push(subdir);
        }
        let out = Command::new("git")
            .args(&args)
            .current_dir(&tmp)
            .output()
            .map_err(|e| format!("git archive {sha}: {e}"))?;
        if !out.status.success() {
            return Err(format!(
                "git archive {sha}: {}",
                String::from_utf8_lossy(&out.stderr).trim()
            ));
        }
        // the manifest bytes come from the archived tree, not a
        // checkout — same bytes the sum will verify later
        let manifest = Command::new("git")
            .args(["show", &format!("{sha}:{pfx}oxl.mod")])
            .current_dir(&tmp)
            .output()
            .map_err(|e| e.to_string())?;
        let manifest = if manifest.status.success() {
            manifest.stdout
        } else if subdir.is_empty() {
            return Err(format!("{path}@{ver}: no oxl.mod at repo root"));
        } else {
            return Err(format!("{path}@{ver}: no oxl.mod at {subdir}/"));
        };
        Ok(Fetched { ver, tar: out.stdout, manifest, subdir: subdir.to_string() })
    })();
    let _ = std::fs::remove_dir_all(&tmp);
    res
}

fn sanitize(s: &str) -> String {
    s.chars().map(|c| if c.is_ascii_alphanumeric() { c } else { '_' }).collect()
}

/// every `<pfx>v*` tag, as (semver, tag-text) pairs — the prefix is
/// stripped before the semver parse while the tag text is kept whole
/// for rev-parse; versions name the module, tags name the repo ref
fn tags(repo: &Path, pfx: &str) -> Result<Vec<(semver::Ver, String)>, String> {
    let out = git(repo, &["tag", "--list", &format!("{pfx}v*")])?;
    Ok(out
        .lines()
        .filter_map(|l| {
            let t = l.trim();
            t.strip_prefix(pfx)
                .and_then(semver::parse)
                .map(|v| (v, t.to_string()))
        })
        .collect())
}

fn rev_parse(repo: &Path, r: &str) -> Result<String, String> {
    git(repo, &["rev-parse", "--verify", &format!("{r}^{{commit}}")]).map(|s| s.trim().to_string())
}

/// Pseudo-version shape: the commit's nearest semver tag ancestor bumps
/// its patch and gains `-0.<yyyymmddhhmmss>-<sha12>`; no ancestor tag
/// at all starts from v0.0.0
/// `pfx` selects the tag series (`extra/v*` for a subdirectory
/// module); the recorded version is the module's — the prefix is
/// stripped before the semver bump
fn pseudo(repo: &Path, sha: &str, pfx: &str) -> Result<String, String> {
    let base = git(repo, &["describe", "--tags", "--abbrev=0", "--match", &format!("{pfx}v*"), sha]).ok();
    let ts = git(repo, &["show", "-s", "--format=%cd", "--date=format:%Y%m%d%H%M%S", sha])?;
    let ts = ts.trim();
    let short = &sha[..12.min(sha.len())];
    let v = base
        .and_then(|b| semver::parse(b.trim().strip_prefix(pfx).unwrap_or(b.trim())))
        .map(|mut v| {
            v.pat += 1;
            v
        })
        .unwrap_or(semver::Ver { maj: 0, min: 0, pat: 0, pre: vec![], build: String::new() });
    Ok(format!("v{}.{}.{}-0.{ts}-{short}", v.maj, v.min, v.pat))
}

fn resolve(repo: &Path, query: &str, pfx: &str) -> Result<(String, String), String> {
    match query {
        "latest" | "" => {
            let ts = tags(repo, pfx)?;
            match ts.iter().max_by(|a, b| semver::compare(&a.0, &b.0)) {
                Some((v, tag)) => Ok((rev_parse(repo, tag)?, fmt_ver(v))),
                None => {
                    let sha = rev_parse(repo, "HEAD")?;
                    Ok((sha.clone(), pseudo(repo, &sha, pfx)?))
                }
            }
        }
        q if q.starts_with('v') && semver::parse(q).is_some() => {
            let sha = rev_parse(repo, &format!("refs/tags/{pfx}{q}"))
                .map_err(|_| format!("unknown revision {q}"))?;
            Ok((sha, q.to_string()))
        }
        q => {
            // branch name first, then a raw commit-ish
            if let Ok(sha) = rev_parse(repo, &format!("refs/heads/{q}")) {
                let v = pseudo(repo, &sha, pfx)?;
                return Ok((sha, v));
            }
            let sha = rev_parse(repo, q).map_err(|_| format!("unknown revision {q}"))?;
            let v = pseudo(repo, &sha, pfx)?;
            Ok((sha, v))
        }
    }
}

fn fmt_ver(v: &semver::Ver) -> String {
    let mut s = format!("v{}.{}.{}", v.maj, v.min, v.pat);
    if !v.pre.is_empty() {
        s.push('-');
        s.push_str(&v.pre.join("."));
    }
    if !v.build.is_empty() {
        s.push('+');
        s.push_str(&v.build);
    }
    s
}
