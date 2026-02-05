///|
pub struct Repository {
  worktree : String
  git_dir : String
  config : @ini.IniFile
}

///|
fn Repository::default_config() -> @ini.IniFile {
  let conf = @ini.IniFile::new()
  conf.set(section="core", "repositoryformatversion", "0")
  conf.set(section="core", "filemode", "false")
  conf.set(section="core", "bare", "false")
  conf
}

///|
pub async fn Repository::new(worktree : String) -> Repository {
  let git_dir = "\{worktree}/.git"
  let config_path = "\{git_dir}/config"
  if !(@fs.exists(git_dir) || @fs.exists(config_path)) {
    return Repository::{
      worktree,
      git_dir,
      config: Repository::default_config(),
    }
  }
  let config = @fs.read_file(config_path.to_string()).text() |> @ini.parse
  guard config.get(section="core", "repositoryformatversion")
    is Some(repo_format_version) else {
    fail("core.repositoryformatversion not found in \{config_path}")
  }
  guard repo_format_version is "0" else {
    fail("incorrect core.repositoryformatversion \{repo_format_version}")
  }
  Repository::{ worktree, git_dir, config }
}

///|
fn make_repo_path(repo : Repository, path : ArrayView[StringView]) -> String {
  let buf = StringBuilder::new()
  buf.write_string(repo.git_dir)
  for s in path {
    buf.write_char('/')
    buf.write_stringview(s)
  }
  buf.to_string()
}

///|
/// auto create:
/// - `.git/objects/`
/// - `.git/refs/`
/// - `.git/HEAD`
/// - `.git/config`
pub async fn Repository::init(self : Repository) -> Unit {
  ...
}
