### NAME  
**copyfile** - copy a file to the clipboard

### SYNOPSIS  
**copyfile** [<u>environment</u>] <u>filename</u>

### DESCRIPTION
The **copyfile** tool copies a file to the clipboard as a singular line.
**copyfile** allows for other files to be included recursively.

### OPTIONS
[<u>environment</u>]  
A JSON file to be used as the environment.
The JSON file must only contain objects with string values.
On macOS 12.0 or newer, JSON5 is used.

<u>filename</u>  
A UTF-8 encoded file to be copied.

### EXIT STATUS  
If **copyfile** can find <u>filename</u>, it exits with status code 0.

### FILE STRUCTURE  
**copyfile** supports variable substitution.
Variables can be substituted using the variable operator (**#""**) and the value will be fetched from the environment.
`#"example"` will be replaced with the value of `example` specified by the environment.
If the value does not exist, an empty value is returned instead.

**copyfile** has two ways to include another file.
Using the inclusion operator (**#!**) and the environmental inclusion operator (**#!""**).

The inclusion operator (**#!**) includes the file path that follows relative to the file that includes it.
`#!./README.md` will include the file `./README.md`.
If the first two bytes of a file are the inclusion operator, that line is skipped.
If another file needs to be included immediately, preceding it with an empty variable (**#""**) will allow that.
**NOTE:**
There can only be one inclusion operator on a line.
Only the last inclusion operator on a line is used.

The environmental inclusion operator (**#!""**) includes the file the variable is set to.
`#!"example"` will include the file specified by the value of example.
If example is set to `README.md` then `#!"example"` will include the file `README.md`
**NOTE:**
Environmental inclusions are relative to <u>filename</u>

### AUTHORS  
Harry N
