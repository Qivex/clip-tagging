# Clip Tagging
Assign custom tags to your video files. Find what you were looking for by searching tagged files.

## Installation
Before running this tool you need to download & compile several binaries and place them in the `bin` directory:
- [Lua](https://www.lua.org/) ([precompiled](https://luabinaries.sourceforge.net/))
- [IUP](https://www.tecgraf.puc-rio.br/iup/) ([precompiled](https://sourceforge.net/projects/iup/files/3.31/Windows%20Libraries/Dynamic/))
- [IUP Lua bindings](https://www.tecgraf.puc-rio.br/iup/en/iuplua.html) ([precompiled](https://sourceforge.net/projects/iup/files/3.31/Windows%20Libraries/Dynamic/Lua54/))
- [SQLite 3 for Lua](http://lua.sqlite.org/) (compiled using [LuaRocks](https://luarocks.org/))
Checklist of binaries:
- `lua.exe`
- `lua54.dll`
- `iup.dll`
- `iuplua54.dll`
- `lsqlite3complete.dll`

## Usage
### Starting
Open the GUI using the included `start.bat`.
In the config dialog define where the tags are stored, where VLC Player is installed, and the password used to communicate with VLC Player.

### Sections
The first section shows which files you are currently tagging.
Add them using the `Choose` menu option.
Start tagging a file by double clicking.
This will open the file in VLC Player and display all assigned tags in the middle section.
File metadata can be scanned using the button, although this will only work if VLC Player is set to English.
The third section is used to apply (doubleclick) or create new (rightclick) tags.

### Query execution
To find files by tags execute SQL queries in the menu at `Choose` -> `...from Query`.
Nothing can be manipulated by accident because only SELECT queries are allowed.
Files will only be added to the list when (at least) the rows "path" and "name" are included in the query result.
Below you can find the database schema and some example queries.

## Database
### Schema
```sql
CREATE TABLE file (
	id INTEGER PRIMARY KEY,
	name TEXT NOT NULL,
	path TEXT NOT NULL,
	length INTEGER,
	width INTEGER,
	height INTEGER,
	size INTEGER
);
CREATE TABLE tag (
	id INTEGER PRIMARY KEY,
	name TEXT NOT NULL,
	description TEXT,
	parent INTEGER REFERENCES tag(id)
);
CREATE TABLE tagging (
	fileid INTEGER NOT NULL REFERENCES file(id),
	tagid INTEGER NOT NULL REFERENCES tag(id),
	PRIMARY KEY (fileid, tagid)
);
```

### Example queries
Files filmed in portrait mode:
```sql
SELECT name, path
FROM file
WHERE height > width
```

Files of certain tag:
```sql
SELECT file.name, file.path
FROM file
INNER JOIN tagging ON tagging.fileid = file.id
INNER JOIN tag ON tagging.tagid = tag.id
WHERE tag.name = "Highlight"
```

Files of all tags which are direct children of "Replays" (for example Replays > Games or Replays > Desktop):
```sql
SELECT file.name, file.path
FROM file
INNER JOIN tagging ON tagging.fileid = file.id
WHERE tagging.tagid IN (
	SELECT id
	FROM tag
	WHERE parent IN (
		SELECT id
		FROM tag
		WHERE name = "Replays"
	)
)
```

Note: The internal ID of all tags is shown above the tree upon selection. This can be useful to skip query layers - for example, the above query could be simplified into:
```sql
SELECT file.name, file.path
FROM file
INNER JOIN tagging ON tagging.fileid = file.id
WHERE tagging.tagid IN (
	SELECT id
	FROM tag
	WHERE parent = 42
)
```