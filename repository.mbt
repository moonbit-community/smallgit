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
async fn ensure_dir(path : String) -> Unit {
  if @fs.exists(path) {
    let kind = @fs.kind(path, follow_symlink=true)
    guard kind is @fs.FileKind::Directory else {
      fail("\{path} exists and is not a directory")
    }
  } else {
    @fs.mkdir(path, permission=0o755, recursive=true)
  }
}

///|
async fn ensure_file(path : String, data : String) -> Unit {
  if @fs.exists(path) {
    let kind = @fs.kind(path, follow_symlink=true)
    guard kind is @fs.FileKind::Regular else {
      fail("\{path} exists and is not a file")
    }
  } else {
    @fs.write_file(path, data, create=0o644, truncate=true)
  }
}

///|
/// auto create:
/// - `.git/objects/`
/// - `.git/refs/`
/// - `.git/HEAD`
/// - `.git/config`
pub async fn Repository::init(self : Repository) -> Unit {
  ensure_dir(self.worktree)
  ensure_dir(self.git_dir)
  let objects_path = make_repo_path(self, ["objects"])
  ensure_dir(objects_path)
  let refs_path = make_repo_path(self, ["refs"])
  ensure_dir(refs_path)
  let heads_path = "\{refs_path}/heads"
  ensure_dir(heads_path)
  let tags_path = "\{refs_path}/tags"
  ensure_dir(tags_path)
  let default_branch = match self.config.get(section="init", "defaultBranch") {
    Some(branch) => branch
    None => "master"
  }
  let head_path = make_repo_path(self, ["HEAD"])
  let head_contents = "ref: refs/heads/\{default_branch}\n"
  ensure_file(head_path, head_contents)
  let config_path = make_repo_path(self, ["config"])
  let config_contents = self.config.to_string()
  ensure_file(config_path, config_contents)
}
