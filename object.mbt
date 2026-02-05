///|
/// Raw blob content wrapper.
///
/// The payload is stored as-is. Serialization is the identity function and
/// does not include any header.
pub struct BlobObject(BytesView)

///|
/// Serialize a blob by returning its raw bytes unchanged.
pub fn BlobObject::serialize(self : BlobObject) -> BytesView {
  self.0
}

///|
/// Deserialize a blob by wrapping the provided raw bytes.
pub fn BlobObject::deserialize(bytes : BytesView) -> BlobObject {
  BlobObject(bytes)
}

///|
/// A single tree entry in the Git tree object format.
///
/// - `mode` is stored as the textual mode (e.g. "100644", "100755", "120000",
///   "40000") exactly as it appears in the tree body.
/// - `name` is the entry name and must not contain NUL in valid Git objects.
/// - `oid` is the raw 20-byte object id (not hex-encoded).
pub struct TreeEntry {
  mode : String
  name : String
  oid : Bytes
}

///|
/// Git tree object payload (ordered list of entries).
///
/// Serialization keeps the given order unchanged and does not sort or validate
/// entries. Deserialization is tolerant: it stops at the first malformed or
/// truncated entry and returns the entries parsed so far.
pub struct TreeObject {
  entries : Array[TreeEntry]
}

///|
/// Git annotated tag object payload.
///
/// Known headers (`object`, `type`, `tag`, `tagger`) are stored as fields.
/// Unknown headers are preserved in `extra_headers` in their original order.
/// The `message` is the text after the first blank line.
///
/// Serialization emits headers in a fixed order
/// (`object`, `type`, `tag`, `tagger`, then `extra_headers`), followed by a
/// blank line and the message (if non-empty). This means header ordering from
/// the original input is not preserved.
pub struct TagObject {
  object : String
  object_type : String
  tag : String
  tagger : String
  message : String
  extra_headers : Array[(String, String)]
}

///|
/// Git commit object payload.
///
/// - `tree` is the tree oid (hex string).
/// - `parents` records all `parent` headers in order.
/// - `author` and `committer` are stored verbatim.
/// - `extra_headers` preserves unrecognized headers in order.
/// - `message` is the text after the first blank line.
///
/// Serialization emits `tree`, then each `parent`, then `author`, `committer`,
/// followed by `extra_headers`, a blank line, and the message (if non-empty).
/// Header ordering from the original input is not preserved.
pub struct CommitObject {
  tree : String
  parents : Array[String]
  author : String
  committer : String
  message : String
  extra_headers : Array[(String, String)]
}

///|
/// Split a raw tag/commit payload into header text and message.
///
/// The split happens at the first "\n\n". UTF-8 decoding is lossy to avoid
/// raising errors on invalid byte sequences.
fn split_headers_message(bytes : BytesView) -> (String, String) {
  match bytes.find(b"\n\n") {
    Some(idx) =>
      (@utf8.decode_lossy(bytes[:idx]), @utf8.decode_lossy(bytes[idx + 2:]))
    None => (@utf8.decode_lossy(bytes[:]), "")
  }
}

///|
/// Split a header line into key and value at the first space.
///
/// If no space exists, the value is returned as an empty string.
fn split_header_line(line : StringView) -> (String, String) {
  match line.find(" ") {
    None => (line.to_string(), "")
    Some(idx) =>
      (
        line.view(end_offset=idx).to_string(),
        line.view(start_offset=idx + 1).to_string(),
      )
  }
}

///|
/// Parse header lines into key/value pairs.
///
/// Empty lines are ignored. Values preserve any spaces after the first one.
fn parse_headers(text : String) -> Array[(String, String)] {
  let headers : Array[(String, String)] = []
  for line in text.split("\n") {
    if line.is_empty() {
      continue
    }
    let (key, value) = split_header_line(line)
    headers.push((key, value))
  }
  headers
}

///|
/// Write a single header line as "key value\n".
fn write_header(buf : @buffer.Buffer, key : String, value : String) -> Unit {
  buf.write_string_utf8(key.to_string_view())
  buf.write_byte(b' ')
  buf.write_string_utf8(value.to_string_view())
  buf.write_byte(b'\n')
}

///|
/// Serialize a tree object using the Git tree entry format:
/// "<mode> <name>\\0<20-byte-oid>" repeated for each entry.
pub fn TreeObject::serialize(self : TreeObject) -> BytesView {
  let buf = @buffer.new()
  for entry in self.entries {
    buf.write_string_utf8(entry.mode.to_string_view())
    buf.write_byte(b' ')
    buf.write_string_utf8(entry.name.to_string_view())
    buf.write_byte(0)
    buf.write_bytes(entry.oid)
  }
  buf.to_bytes()
}

///|
/// Deserialize a tree object payload into entries.
///
/// Parsing is tolerant: if the input ends mid-entry or is malformed, the
/// entries parsed so far are returned without raising an error.
pub fn TreeObject::deserialize(bytes : BytesView) -> TreeObject {
  let entries : Array[TreeEntry] = []
  let len = bytes.length()
  let mut i = 0
  while i < len {
    let mode_start = i
    while i < len && bytes[i] != b' ' {
      i = i + 1
    }
    if i >= len {
      return TreeObject::{ entries, }
    }
    let mode = @utf8.decode_lossy(bytes.sub(start=mode_start, end=i))
    i = i + 1
    let name_start = i
    while i < len && bytes[i] != 0 {
      i = i + 1
    }
    if i >= len {
      return TreeObject::{ entries, }
    }
    let name = @utf8.decode_lossy(bytes.sub(start=name_start, end=i))
    i = i + 1
    if i + 20 > len {
      return TreeObject::{ entries, }
    }
    let oid = bytes.sub(start=i, end=i + 20).to_bytes()
    i = i + 20
    entries.push(TreeEntry::{ mode, name, oid })
  }
  TreeObject::{ entries, }
}

///|
/// Serialize a tag object payload.
///
/// Headers with empty string values are omitted. Unknown headers are emitted
/// in the stored order after the standard headers.
pub fn TagObject::serialize(self : TagObject) -> BytesView {
  let buf = @buffer.new()
  if self.object != "" {
    write_header(buf, "object", self.object)
  }
  if self.object_type != "" {
    write_header(buf, "type", self.object_type)
  }
  if self.tag != "" {
    write_header(buf, "tag", self.tag)
  }
  if self.tagger != "" {
    write_header(buf, "tagger", self.tagger)
  }
  for header in self.extra_headers {
    let (key, value) = header
    write_header(buf, key, value)
  }
  buf.write_byte(b'\n')
  if self.message != "" {
    buf.write_string_utf8(self.message.to_string_view())
  }
  buf.to_bytes()
}

///|
/// Deserialize a tag object payload from raw bytes.
///
/// Known headers overwrite earlier values if duplicated. Unknown headers are
/// accumulated in order. UTF-8 decoding is lossy.
pub fn TagObject::deserialize(bytes : BytesView) -> TagObject {
  let (header_text, message) = split_headers_message(bytes)
  let headers = parse_headers(header_text)
  let mut object = ""
  let mut object_type = ""
  let mut tag = ""
  let mut tagger = ""
  let extra_headers : Array[(String, String)] = []
  for header in headers {
    let (key, value) = header
    match key {
      "object" => object = value
      "type" => object_type = value
      "tag" => tag = value
      "tagger" => tagger = value
      _ => extra_headers.push((key, value))
    }
  }
  TagObject::{ object, object_type, tag, tagger, message, extra_headers }
}

///|
/// Serialize a commit object payload.
///
/// The header order is fixed and does not preserve the original input order.
/// Headers with empty string values are omitted, except `parent` which is
/// emitted for each entry in `parents`.
pub fn CommitObject::serialize(self : CommitObject) -> BytesView {
  let buf = @buffer.new()
  if self.tree != "" {
    write_header(buf, "tree", self.tree)
  }
  for parent in self.parents {
    write_header(buf, "parent", parent)
  }
  if self.author != "" {
    write_header(buf, "author", self.author)
  }
  if self.committer != "" {
    write_header(buf, "committer", self.committer)
  }
  for header in self.extra_headers {
    let (key, value) = header
    write_header(buf, key, value)
  }
  buf.write_byte(b'\n')
  if self.message != "" {
    buf.write_string_utf8(self.message.to_string_view())
  }
  buf.to_bytes()
}

///|
/// Deserialize a commit object payload from raw bytes.
///
/// Duplicate `tree`, `author`, or `committer` headers are overwritten by the
/// last occurrence. `parent` headers are collected in order. UTF-8 decoding is
/// lossy.
pub fn CommitObject::deserialize(bytes : BytesView) -> CommitObject {
  let (header_text, message) = split_headers_message(bytes)
  let headers = parse_headers(header_text)
  let mut tree = ""
  let parents : Array[String] = []
  let mut author = ""
  let mut committer = ""
  let extra_headers : Array[(String, String)] = []
  for header in headers {
    let (key, value) = header
    match key {
      "tree" => tree = value
      "parent" => parents.push(value)
      "author" => author = value
      "committer" => committer = value
      _ => extra_headers.push((key, value))
    }
  }
  CommitObject::{ tree, parents, author, committer, message, extra_headers }
}

///|
pub enum Object {
  Blob(BlobObject)
  Tree(TreeObject)
  Tag(TagObject)
  Commit(CommitObject)
}

///|
fn sha1_hex(bytes : Bytes) -> String {
  let digest = @sha1.Digest::new()
  for b in bytes {
    let _ = digest.write_byte(b)

  }
  digest.check_sum()
}

///|
fn parse_decimal(text : StringView) -> Int? {
  let digits = @utf8.encode(text.to_string())
  if digits.length() == 0 {
    return None
  }
  let mut value = 0
  for b in digits {
    if b < b'0' || b > b'9' {
      return None
    }
    value = value * 10 + (b.to_int() - b'0'.to_int())
  }
  Some(value)
}

///|
fn zlib_decompress(bytes : Bytes) -> Bytes raise {
  let input = @io.Buffer::from_bytes(bytes)
  let (zr, err) = @zlib.Reader::new(input)
  if err != None {
    fail("zlib reader error: \{err}")
  }
  let (out, read_err) = @io.read_all(zr)
  let close_err = zr.close()
  if read_err != None {
    fail("zlib read error: \{read_err}")
  }
  if close_err != None {
    fail("zlib close error: \{close_err}")
  }
  out.to_bytes()
}

///|
fn zlib_compress(bytes : Bytes) -> Bytes raise {
  let out = @io.Buffer::new()
  let zw = @zlib.Writer::new(out)
  let slice = @io.Slice::new(bytes.to_array())
  let (_, write_err) = zw.write(slice)
  if write_err != None {
    fail("zlib write error: \{write_err}")
  }
  let close_err = zw.close()
  if close_err != None {
    fail("zlib close error: \{close_err}")
  }
  out.to_bytes()
}

///|
pub async fn Repository::read_object(self : Repository, sha : String) -> Object {
  if sha.length() < 4 {
    fail("invalid object id: \{sha}")
  }
  let dir = sha.view(start_offset=0, end_offset=2).to_string()
  let file = sha.view(start_offset=2).to_string()
  let path = "\{self.git_dir}/objects/\{dir}/\{file}"
  if !@fs.exists(path) {
    fail("object \{sha} not found")
  }
  let compressed = @fs.read_file(path).binary()
  let raw = zlib_decompress(compressed)
  match raw.find(b"\x00") {
    None => fail("invalid object header")
    Some(nul_idx) => {
      let header = @utf8.decode_lossy(raw.sub(start=0, end=nul_idx))
      match header.find(" ") {
        None => fail("invalid object header")
        Some(space_idx) => {
          let kind = header.view(end_offset=space_idx).to_string()
          let size_view = header.view(start_offset=space_idx + 1)
          let size = match parse_decimal(size_view) {
            None => fail("invalid object size")
            Some(value) => value
          }
          let payload_start = nul_idx + 1
          let payload_end = payload_start + size
          if payload_end > raw.length() {
            fail("truncated object payload")
          }
          let payload = raw.sub(start=payload_start, end=payload_end)
          match kind {
            "blob" => Object::Blob(BlobObject::deserialize(payload))
            "tree" => Object::Tree(TreeObject::deserialize(payload))
            "tag" => Object::Tag(TagObject::deserialize(payload))
            "commit" => Object::Commit(CommitObject::deserialize(payload))
            _ => fail("unknown object type: \{kind}")
          }
        }
      }
    }
  }
}

///|
pub async fn Repository::write_object(
  self : Repository,
  object : Object,
  dry_run? : Bool = false,
) -> String {
  let (kind, payload) = match object {
    Object::Blob(blob) => ("blob", blob.serialize())
    Object::Tree(tree) => ("tree", tree.serialize())
    Object::Tag(tag) => ("tag", tag.serialize())
    Object::Commit(commit) => ("commit", commit.serialize())
  }
  let header = "\{kind} \{payload.length()}\u0000"
  let buf = @buffer.new(size_hint=header.length() + payload.length())
  buf.write_string_utf8(header.to_string_view())
  buf.write_bytesview(payload)
  let raw = buf.to_bytes()
  let sha = sha1_hex(raw)
  if dry_run {
    return sha
  }
  let dir = sha.view(start_offset=0, end_offset=2).to_string()
  let file = sha.view(start_offset=2).to_string()
  let dir_path = "\{self.git_dir}/objects/\{dir}"
  if !@fs.exists(dir_path) {
    @fs.mkdir(dir_path, permission=0o755, recursive=true)
  }
  let obj_path = "\{dir_path}/\{file}"
  if @fs.exists(obj_path) {
    return sha
  }
  let compressed = zlib_compress(raw)
  @fs.write_file(obj_path, compressed, create=0o444)
  sha
}
