///|
async fn get_file_create_time(path : String) -> String {
  let ctime = @fs.ctime(path)
  let create_time = @time.unix(ctime.0)
  let create_date = create_time.to_plain_date().to_string()
  let create_time = create_time.to_plain_time().to_string()
  "\{create_date} \{create_time}"
}

///|
async test {
  inspect(get_file_create_time("./LICENSE"), content="2025-12-16 08:01:38")
}
