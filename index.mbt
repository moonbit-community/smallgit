///|
/// A single entry in the Git index file.
/// Fields mirror the on-disk layout for index versions 2-4.
pub struct IndexEntry {
  ctime_s : Int
  ctime_ns : Int
  mtime_s : Int
  mtime_ns : Int
  dev : Int
  ino : Int
  mode : Int
  uid : Int
  gid : Int
  size : Int
  oid : Bytes
  flags : Int
  extended_flags : Int
  path : String
}

///|
/// Optional extension payload stored after the entries section.
pub struct IndexExtension {
  signature : String
  data : Bytes
}

///|
/// Parsed Git index file.
pub struct Index {
  version : Int
  entries : Array[IndexEntry]
  extensions : Array[IndexExtension]
  checksum : Bytes
  checksum_valid : Bool
}

///|
/// Return whether the index entry is marked assume-valid.
pub fn IndexEntry::assume_valid(self : IndexEntry) -> Bool {
  (self.flags & 0x8000) != 0
}

///|
/// Return the stage value for the index entry (0-3).
pub fn IndexEntry::stage(self : IndexEntry) -> Int {
  (self.flags >> 12) & 0x3
}

///|
/// Return the stored name length field (0-4095).
pub fn IndexEntry::name_length(self : IndexEntry) -> Int {
  self.flags & 0x0fff
}

///|
/// Return whether the entry uses extended flags (v3+).
pub fn IndexEntry::has_extended(self : IndexEntry) -> Bool {
  (self.flags & 0x4000) != 0
}

///|
/// Return whether the entry is marked "intent-to-add".
pub fn IndexEntry::intent_to_add(self : IndexEntry) -> Bool {
  (self.extended_flags & 0x1) != 0
}

///|
/// Return whether the entry is marked "skip-worktree".
pub fn IndexEntry::skip_worktree(self : IndexEntry) -> Bool {
  (self.extended_flags & 0x2) != 0
}

///|
/// Create an empty index (defaults to version 2).
pub fn Index::empty(version? : Int = 2) -> Index {
  Index::{
    version,
    entries: [],
    extensions: [],
    checksum: Bytes::default(),
    checksum_valid: false,
  }
}

///|
/// Read index file bytes into an `Index` structure.
pub fn Index::from_bytes(bytes : Bytes) -> Index {
  let len = bytes.length()
  if len < 12 {
    return Index::empty()
  }
  if !is_index_signature(bytes) {
    return Index::empty()
  }
  let version = read_u32_be(bytes, 4)
  if version < 2 || version > 4 {
    return Index::empty(version~)
  }
  let count = read_u32_be(bytes, 8)
  let mut offset = 12
  let entries : Array[IndexEntry] = []
  let mut prev_path_bytes : Bytes = Bytes::default()
  let mut i = 0
  while i < count {
    if offset + 62 > len {
      break
    }
    let entry_start = offset
    let ctime_s = read_u32_be(bytes, offset)
    offset = offset + 4
    let ctime_ns = read_u32_be(bytes, offset)
    offset = offset + 4
    let mtime_s = read_u32_be(bytes, offset)
    offset = offset + 4
    let mtime_ns = read_u32_be(bytes, offset)
    offset = offset + 4
    let dev = read_u32_be(bytes, offset)
    offset = offset + 4
    let ino = read_u32_be(bytes, offset)
    offset = offset + 4
    let mode = read_u32_be(bytes, offset)
    offset = offset + 4
    let uid = read_u32_be(bytes, offset)
    offset = offset + 4
    let gid = read_u32_be(bytes, offset)
    offset = offset + 4
    let size = read_u32_be(bytes, offset)
    offset = offset + 4
    if offset + 20 > len {
      break
    }
    let oid = bytes.sub(start=offset, end=offset + 20).to_bytes()
    offset = offset + 20
    if offset + 2 > len {
      break
    }
    let flags = read_u16_be(bytes, offset)
    offset = offset + 2
    let mut extended_flags = 0
    if version >= 3 && (flags & 0x4000) != 0 {
      if offset + 2 > len {
        break
      }
      extended_flags = read_u16_be(bytes, offset)
      offset = offset + 2
    }
    let mut path = ""
    let mut path_bytes = Bytes::default()
    if version == 4 {
      let (strip, new_offset) = read_offset_encoding(bytes, offset)
      offset = new_offset
      let (suffix_bytes, new_offset2) = read_cstring(bytes, offset)
      offset = new_offset2
      let prev_len = prev_path_bytes.length()
      let strip_len = if strip <= prev_len { strip } else { prev_len }
      let prefix_len = prev_len - strip_len
      let prefix = if prefix_len == 0 {
        Bytes::default()
      } else {
        prev_path_bytes.sub(start=0, end=prefix_len).to_bytes()
      }
      path_bytes = prefix + suffix_bytes
      path = @utf8.decode_lossy(path_bytes)
      prev_path_bytes = path_bytes
    } else {
      let (name_bytes, new_offset) = read_cstring(bytes, offset)
      offset = new_offset
      path_bytes = name_bytes
      path = @utf8.decode_lossy(path_bytes)
      prev_path_bytes = path_bytes
      let entry_len = offset - entry_start
      let pad = pad_len(entry_len)
      if offset + pad > len {
        offset = len
      } else {
        offset = offset + pad
      }
    }
    entries.push(IndexEntry::{
      ctime_s,
      ctime_ns,
      mtime_s,
      mtime_ns,
      dev,
      ino,
      mode,
      uid,
      gid,
      size,
      oid,
      flags,
      extended_flags,
      path,
    })
    i = i + 1
  }
  let checksum_start = if len >= 20 { len - 20 } else { len }
  let extensions : Array[IndexExtension] = []
  let mut ext_offset = offset
  while ext_offset + 8 <= checksum_start {
    let sig_bytes = bytes.sub(start=ext_offset, end=ext_offset + 4).to_bytes()
    let signature = @utf8.decode_lossy(sig_bytes)
    let size = read_u32_be(bytes, ext_offset + 4)
    ext_offset = ext_offset + 8
    if ext_offset + size > checksum_start {
      break
    }
    let data = bytes.sub(start=ext_offset, end=ext_offset + size).to_bytes()
    ext_offset = ext_offset + size
    extensions.push(IndexExtension::{ signature, data })
  }
  let checksum = if len >= 20 {
    bytes.sub(start=len - 20, end=len).to_bytes()
  } else {
    Bytes::default()
  }
  let mut checksum_valid = false
  if len >= 20 {
    let computed = sha1_bytes(bytes.sub(start=0, end=len - 20).to_bytes())
    checksum_valid = computed == checksum
  }
  Index::{ version, entries, extensions, checksum, checksum_valid }
}

///|
/// Serialize the index structure into on-disk bytes (including checksum).
pub fn Index::to_bytes(self : Index) -> Bytes {
  let version = if self.version < 2 || self.version > 4 {
    2
  } else {
    self.version
  }
  let buf = @buffer.new()
  buf.write_bytes(b"DIRC")
  write_u32_be(buf, version)
  write_u32_be(buf, self.entries.length())
  let mut prev_path_bytes : Bytes = Bytes::default()
  for entry in self.entries {
    write_u32_be(buf, entry.ctime_s)
    write_u32_be(buf, entry.ctime_ns)
    write_u32_be(buf, entry.mtime_s)
    write_u32_be(buf, entry.mtime_ns)
    write_u32_be(buf, entry.dev)
    write_u32_be(buf, entry.ino)
    write_u32_be(buf, entry.mode)
    write_u32_be(buf, entry.uid)
    write_u32_be(buf, entry.gid)
    write_u32_be(buf, entry.size)
    write_oid(buf, entry.oid)
    let path_bytes = @utf8.encode(entry.path)
    let name_len = if path_bytes.length() > 0x0fff {
      0x0fff
    } else {
      path_bytes.length()
    }
    let has_extended = version >= 3 &&
      ((entry.flags & 0x4000) != 0 || entry.extended_flags != 0)
    let mut flags = (entry.flags & 0xB000) | name_len
    if has_extended {
      flags = flags | 0x4000
    }
    write_u16_be(buf, flags)
    if has_extended {
      write_u16_be(buf, entry.extended_flags)
    }
    if version == 4 {
      let common_len = common_prefix_len(prev_path_bytes, path_bytes)
      let strip = prev_path_bytes.length() - common_len
      write_offset_encoding(buf, strip)
      if common_len < path_bytes.length() {
        buf.write_bytes(path_bytes.sub(start=common_len).to_bytes())
      }
      buf.write_byte(0)
      prev_path_bytes = path_bytes
    } else {
      buf.write_bytes(path_bytes)
      buf.write_byte(0)
      let base_len = 62 + (if has_extended { 2 } else { 0 })
      let entry_len = base_len + path_bytes.length() + 1
      let pad = pad_len(entry_len)
      for _ in 0..<pad {
        buf.write_byte(0)
      }
      prev_path_bytes = path_bytes
    }
  }
  for ext in self.extensions {
    write_extension(buf, ext)
  }
  let body = buf.to_bytes()
  let checksum = sha1_bytes(body)
  buf.write_bytes(checksum)
  buf.to_bytes()
}

///|
/// Read the index file from the repository's .git directory.
pub async fn Index::read_from(repo : Repository) -> Index {
  let index_path = "\{repo.git_dir}/index"
  if !@fs.exists(index_path) {
    return Index::empty()
  }
  let data = @fs.read_file(index_path)
  Index::from_bytes(data.binary())
}

///|
/// Write the index file to the repository's .git directory.
pub async fn Index::write_to(self : Index, repo : Repository) -> Unit {
  let index_path = "\{repo.git_dir}/index"
  let bytes = self.to_bytes()
  @fs.write_file(index_path, bytes)
}

///|
fn is_index_signature(bytes : Bytes) -> Bool {
  bytes.length() >= 4 &&
  bytes[0] == b'D' &&
  bytes[1] == b'I' &&
  bytes[2] == b'R' &&
  bytes[3] == b'C'
}

///|
fn read_u32_be(bytes : Bytes, offset : Int) -> Int {
  if offset + 4 > bytes.length() {
    return 0
  }
  let b0 = bytes[offset].to_int()
  let b1 = bytes[offset + 1].to_int()
  let b2 = bytes[offset + 2].to_int()
  let b3 = bytes[offset + 3].to_int()
  (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
}

///|
fn read_u16_be(bytes : Bytes, offset : Int) -> Int {
  if offset + 2 > bytes.length() {
    return 0
  }
  let b0 = bytes[offset].to_int()
  let b1 = bytes[offset + 1].to_int()
  (b0 << 8) | b1
}

///|
fn write_u32_be(buf : @buffer.Buffer, value : Int) -> Unit {
  buf.write_byte(((value >> 24) & 0xff).to_byte())
  buf.write_byte(((value >> 16) & 0xff).to_byte())
  buf.write_byte(((value >> 8) & 0xff).to_byte())
  buf.write_byte((value & 0xff).to_byte())
}

///|
fn write_u16_be(buf : @buffer.Buffer, value : Int) -> Unit {
  buf.write_byte(((value >> 8) & 0xff).to_byte())
  buf.write_byte((value & 0xff).to_byte())
}

///|
fn read_cstring(bytes : Bytes, start : Int) -> (Bytes, Int) {
  let len = bytes.length()
  let mut i = start
  while i < len && bytes[i] != 0 {
    i = i + 1
  }
  let end = i
  let next = if i < len { i + 1 } else { len }
  (bytes.sub(start~, end~).to_bytes(), next)
}

///|
fn pad_len(length : Int) -> Int {
  let rem = length % 8
  if rem == 0 {
    0
  } else {
    8 - rem
  }
}

///|
fn common_prefix_len(left : Bytes, right : Bytes) -> Int {
  let left_len = left.length()
  let right_len = right.length()
  let limit = if left_len < right_len { left_len } else { right_len }
  let mut i = 0
  while i < limit && left[i] == right[i] {
    i = i + 1
  }
  i
}

///|
fn read_offset_encoding(bytes : Bytes, start : Int) -> (Int, Int) {
  let len = bytes.length()
  if start >= len {
    return (0, start)
  }
  let mut i = start
  let mut c = bytes[i].to_int()
  let mut value = c & 0x7f
  i = i + 1
  while (c & 0x80) != 0 && i < len {
    c = bytes[i].to_int()
    value = (value + 1) << 7
    value = value | (c & 0x7f)
    i = i + 1
  }
  (value, i)
}

///|
fn write_offset_encoding(buf : @buffer.Buffer, value : Int) -> Unit {
  let bytes : Array[Byte] = []
  let mut v = value
  bytes.push((v & 0x7f).to_byte())
  while v > 0x7f {
    v = (v >> 7) - 1
    bytes.push(((v & 0x7f) | 0x80).to_byte())
  }
  let mut i = bytes.length() - 1
  while true {
    buf.write_byte(bytes[i])
    if i == 0 {
      break
    }
    i = i - 1
  }
}

///|
fn write_oid(buf : @buffer.Buffer, oid : Bytes) -> Unit {
  let len = oid.length()
  if len >= 20 {
    buf.write_bytes(oid.sub(start=0, end=20).to_bytes())
  } else {
    buf.write_bytes(oid)
    let pad = 20 - len
    for _ in 0..<pad {
      buf.write_byte(0)
    }
  }
}

///|
fn write_extension(buf : @buffer.Buffer, ext : IndexExtension) -> Unit {
  let sig_bytes = @utf8.encode(ext.signature)
  if sig_bytes.length() >= 4 {
    buf.write_bytes(sig_bytes.sub(start=0, end=4).to_bytes())
  } else {
    buf.write_bytes(sig_bytes)
    let pad = 4 - sig_bytes.length()
    for _ in 0..<pad {
      buf.write_byte(0)
    }
  }
  write_u32_be(buf, ext.data.length())
  buf.write_bytes(ext.data)
}

///|
fn hex_value(byte : Byte) -> Int {
  if byte >= b'0' && byte <= b'9' {
    byte.to_int() - b'0'.to_int()
  } else if byte >= b'a' && byte <= b'f' {
    byte.to_int() - b'a'.to_int() + 10
  } else if byte >= b'A' && byte <= b'F' {
    byte.to_int() - b'A'.to_int() + 10
  } else {
    0
  }
}

///|
fn hex_to_bytes(hex : String) -> Bytes {
  let hex_bytes = @utf8.encode(hex)
  let len = hex_bytes.length()
  let out_len = len / 2
  let buf = @buffer.new()
  let mut i = 0
  while i < out_len {
    let hi = hex_value(hex_bytes[i * 2])
    let lo = hex_value(hex_bytes[i * 2 + 1])
    buf.write_byte(((hi << 4) + lo).to_byte())
    i = i + 1
  }
  buf.to_bytes()
}

///|
fn sha1_bytes(bytes : Bytes) -> Bytes {
  let digest = @sha1.Digest::new()
  for b in bytes {
    let _ = digest.write_byte(b)

  }
  hex_to_bytes(digest.check_sum())
}

pub async fn Repository::write_index(self : Repository, index : Index) -> Unit {
  index.write_to(self)
}

pub async fn Repository::read_index(self : Repository) -> Index {
  Index::read_from(self)
}
