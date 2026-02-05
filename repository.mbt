///|
pub struct Repository {
  worktree : String
  git_dir : String
  config : @ini.IniFile
}

///|
pub async fn Repository::new(worktree : String) -> Repository {
  let git_dir = "\{worktree}/.git"
  if !@fs.exists(git_dir) {
    fail("\{git_dir} not exist")
  }
  let config_path = "\{git_dir}/config"
  let config = @fs.read_file(config_path.to_string()).text() |> @ini.parse
  Repository::{ worktree, git_dir, config }
}

///|
pub async fn Repository::init(self : Repository) -> Unit {
  ...
}
