"""Create tiny original Anki import fixtures with standard Python libraries."""
import base64
import json
import pathlib
import sqlite3
import tempfile
import zipfile
from compression import zstd

ROOT = pathlib.Path(__file__).resolve().parents[1]
out = ROOT / 'Tests/Fixtures'; out.mkdir(parents=True, exist_ok=True)
png = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j3ioAAAAASUVORK5CYII=')

def varint(n):
    result = bytearray()
    while n > 127:
        result.append((n & 127) | 128); n >>= 7
    result.append(n)
    return bytes(result)

def field(number, data):
    return varint((number << 3) | 2) + varint(len(data)) + data

for modern in [False, True]:
    # NamedTemporaryFile remains in the OS temp directory; fixture data contains
    # no user material or secrets. The project never removes user files.
    with tempfile.NamedTemporaryFile(suffix='.sqlite', delete=False) as temporary:
        database_path = pathlib.Path(temporary.name)
    db = sqlite3.connect(database_path)
    db.executescript('CREATE TABLE notes(id INTEGER PRIMARY KEY,flds TEXT); CREATE TABLE cards(id INTEGER PRIMARY KEY,nid INTEGER,did INTEGER,ord INTEGER);')
    if modern:
        db.execute('CREATE TABLE decks(id INTEGER PRIMARY KEY,name TEXT)'); db.execute('INSERT INTO decks VALUES(1,?)', ['Биология'])
    else:
        db.execute('CREATE TABLE col(decks TEXT)'); db.execute('INSERT INTO col VALUES(?)', [json.dumps({'1':{'name':'Биология'}})])
    db.execute('INSERT INTO notes VALUES(1,?)', ['Где идёт фотосинтез?<img src="tiny.png">\x1fВ хлоропластах'])
    db.execute('INSERT INTO notes VALUES(2,?)', ['Столица Франции — {{c1::Париж::город}}.\x1f'])
    db.executemany('INSERT INTO cards VALUES(?,?,?,?)', [(1,1,1,0),(2,1,1,1),(3,2,1,0)])
    db.commit(); db.close()
    database = database_path.read_bytes()
    with zipfile.ZipFile(out / ('modern.apkg' if modern else 'legacy.apkg'), 'w', zipfile.ZIP_DEFLATED) as archive:
        if modern:
            compressor = zstd.ZstdCompressor()
            compressed = compressor.compress(database, mode=zstd.ZstdCompressor.FLUSH_FRAME)
            archive.writestr('collection.anki21b', compressed)
            entry = field(1, b'tiny.png') + varint(2 << 3) + varint(len(png))
            archive.writestr('media', zstd.compress(field(1, entry)))
            archive.writestr('0', zstd.compress(png))
        else:
            archive.writestr('collection.anki2', database)
            archive.writestr('media', json.dumps({'0':'tiny.png'}))
            archive.writestr('0', png)
with zipfile.ZipFile(out / 'broken.apkg', 'w') as archive:
    archive.writestr('collection.anki21b', b'not-a-zstandard-frame')
print('Created legacy, modern (streamed zstd), and invalid Anki fixtures')
