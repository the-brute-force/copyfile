# NAME  
**copyfile** - copy a file to the clipboard

# SYNOPSIS  
**copyfile** [<u>environment</u>] <u>filename</u>

### DESCRIPTION
The **copyfile** tool copies a file to the clipboard as a singular line.
**copyfile** allows for other files to be included recursively.

### OPTIONS
[<u>environment]  
A JSON file to be used as the environment.
The JSON file must only contain objects with either string or number values.

> [!NOTE]  
> On macOS 12.0 or newer, JSON5 is used.

<u>filename</u>  
A UTF-8 encoded file to be copied.

### EXIT STATUS  
If copyfile is able to read the file specified, it exits with status code 0.

### FILE STRUCTURE  
**copyfile** follows a simple structure for including files.
There are two ways a file is inluded.

The shebang symbol `#!` is used as the inclusion operator and will always be included.
> [!NOTE]  
> If an inclusion operator is used before any text, the first instance will be ignored as it is seen as a shebang.
> If another file needs to be included immediately, preceding it with an empty variable `${}` will allow that.

> [!NOTE]  
> Inclusions are relative to each file processed.

The environmental inclusion operator `#?` will be included if the environment variable exists.
The environmental inclusion operator will include the file located at the value specified by the environment.
If the value is not specified in the environment, it will be ignored.
> [!NOTE]  
> Environmental inclusions are relative to the first file processed.

**copyfile** also allows variable substitution.
Strings enclosed in `${` and `}` will be replaced with the value specified by the environment.
If the value is not specified in the environment, then it will be replaced with nothing.

> [!WARNING]  
> There are no checks for recursion.

### AUTHORS  
Harry N
