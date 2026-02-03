#if !__has_feature(objc_arc)
# error "ARC is required for this project."
#endif

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <strings.h>

static NSDictionary<NSString *, NSString *> *environment = nil;
static NSString *origin = nil;

static BOOL ignoreEmptyLines = YES;
static BOOL appendSpaces = YES;

NSString *replaceVariables(NSString *input);

NSString *includeFile(NSString *fileName, NSString *workingDirectory)
{
    if (fileName == nil)
        return @"";

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *original = nil;
    
    if (workingDirectory != nil) {
        original = [fileManager currentDirectoryPath];
        [fileManager changeCurrentDirectoryPath:workingDirectory];
    }

    NSData *fileData = [fileManager contentsAtPath:fileName];

    if (workingDirectory != nil) {
        [fileManager changeCurrentDirectoryPath:original];
        original = nil;
    } else {
        workingDirectory = @"";
    }

    if (fileData == nil) {
        NSLog(@"Unable to read the file \"%@\".", fileName);
        return @"";
    }

    NSString *fileString = [[NSString alloc] initWithData:fileData encoding:NSUTF8StringEncoding];
    fileData = nil;

    // This is very inefficient, but it's easy and helps with edge cases
    NSArray<NSString *> *fileLines = [fileString componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    fileString = nil;

    BOOL skippedShebang = NO;
    NSMutableString *processedFile = [[NSMutableString alloc] init];

    for (NSString *line in fileLines) {
        if (!skippedShebang) {
            skippedShebang = YES;

            // The shebang is a magic number, it must come at the beginning
            if ([line hasPrefix:@"#!"])
                continue;
        }

        if ([line length] == 0) {
            if (!ignoreEmptyLines) {
                // The lines are split, so this newline is assumed
                [processedFile appendString:@"\n"];

                if (appendSpaces)
                    [processedFile appendString:@" "];
            }

            continue;
        }

        if (appendSpaces && [processedFile length] != 0) {
            [processedFile appendString:@" "];
        }

        NSCharacterSet *notWhitespace = [[NSCharacterSet whitespaceCharacterSet] invertedSet];
        NSRange range = [line rangeOfCharacterFromSet:notWhitespace];
        notWhitespace = nil;

        if (range.location != NSNotFound && range.location < [line length]-4 && [line characterAtIndex:range.location+2] != 0x22) {
            if ([line characterAtIndex:range.location] == 0x23 && [line characterAtIndex:range.location+1] == 0x21) {
                NSString *includePath = [[line substringFromIndex:range.location+2] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

                // Combine current working directory with the included path
                NSArray<NSString *> *futureComponents = [[NSArray alloc] initWithObjects:workingDirectory, [includePath stringByDeletingLastPathComponent], nil];
                NSString *futureWorkingDirectory = [NSString pathWithComponents:futureComponents];
                futureComponents = nil;

                [processedFile appendString:includeFile(includePath, futureWorkingDirectory)];
                continue;
            }
        }

        [processedFile appendString:replaceVariables(line)];
    }

    return processedFile;
}

NSString *replaceVariables(NSString *input)
{
    if (input == nil)
        return @"";

    NSUInteger length = [input length];
    NSMutableString *output = [[NSMutableString alloc] init];

    NSUInteger rangeStart = 0;
    BOOL varMode = NO;
    BOOL replaceWithFile = NO;

    for (NSUInteger i = 0; i < length; i++) {
        unichar current = [input characterAtIndex:i];
        unichar peek = (i < length-2) ? [input characterAtIndex:i+1] : 0;

        NSRange range = NSMakeRange(rangeStart, i-rangeStart);

        // A file variable is started
        if (!varMode && i != 0 && [input characterAtIndex:i-1] == 0x23 && current == 0x21 && peek == 0x22) {
            varMode = YES;
            replaceWithFile = YES;

            // Skip previous character
            range.location++;
            range.length--;

            // Start after sequence
            rangeStart = ++i + 1;

            if (range.length != 0)
                [output appendString:[input substringWithRange:range]];

            continue;
        }

        // A variable is started
        if (!varMode && current == 0x23 && peek == 0x22) {
            varMode = YES;
            // Start after sequence
            rangeStart = ++i + 1;

            if (range.length != 0)
                [output appendString:[input substringWithRange:range]];

            continue;
        }

        // A variable is ended
        if (varMode && current == 0x22) {
            varMode = NO;
            // Start next range at next character
            rangeStart = i+1;

            if (range.length == 0)
                continue;

            NSString *varContent = [environment objectForKey:[input substringWithRange:range]];

            if (replaceWithFile) {
                replaceWithFile = NO;

                // Don't try to look for a file with no name
                if ([varContent length] != 0) {
                    NSString *fileContent = includeFile(varContent, origin);
                    varContent = fileContent;
                }
            }

            if ([varContent length] != 0)
                [output appendString:varContent];

            continue;
        }

        // The end is reached without a variable
        if (i == length-1) {
            // Include the current character too
            range.length++;

            [output appendString:[input substringWithRange:range]];
            continue;
        }
    }

    return output;
}

void readEnvironment(const char * restrict path)
{
    if (path == NULL)
        return;

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *original = nil;

    if (origin != nil) {
        original = [fileManager currentDirectoryPath];
        [fileManager changeCurrentDirectoryPath:origin];
    }

    NSString* pathString = [[NSString alloc] initWithCString:path encoding:[NSString defaultCStringEncoding]];
    NSData* envData = [fileManager contentsAtPath:pathString];
    pathString = nil;

    if (original != nil) {
        [fileManager changeCurrentDirectoryPath:original];
        original = nil;
    }

    if (envData == nil)
        return;

    NSError *err = nil;
    id envJSON = nil;

    #ifndef __GNU_LIBOBJC__
    NSOperatingSystemVersion minForJSON5 = {.majorVersion = 12};

    if ([[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:minForJSON5]) {
        envJSON = [NSJSONSerialization JSONObjectWithData:envData options:NSJSONReadingJSON5Allowed error:&err];
    } else {
        envJSON = [NSJSONSerialization JSONObjectWithData:envData options:0 error:&err];
    }
    #else
    envJSON = [NSJSONSerialization JSONObjectWithData:envData options:0 error:&err];
    #endif

    envData = nil;

    if (envJSON == nil || err != nil || ![envJSON isKindOfClass:[NSDictionary class]])
        return;

    NSMutableDictionary<NSString *, NSString *> *envFiltered = [[NSMutableDictionary alloc] init];
    
    for (NSString *key in envJSON) {
        id value = [envJSON valueForKey:key];

        if ([value isKindOfClass:[NSString class]]) {
            [envFiltered setObject:value forKey:key];
        }
    }

    environment = envFiltered;
}

int main(int argc, const char *argv[])
{
    if (argc < 2) {
        NSLog(@"Invalid argument count.");
        printf("Usage:\n");
        printf("  copyfile [<environment>] <filename>\n\n");
        printf("For more information, see copyfile(1).\n");
        return 1;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSString *baseFile = [[NSString alloc] initWithCString:argv[(argc == 2) ? 1 : 2] encoding:[NSString defaultCStringEncoding]];

    BOOL baseFilePathIsDir;
    if (![fileManager fileExistsAtPath:baseFile isDirectory:&baseFilePathIsDir] || baseFilePathIsDir) {
        NSLog(@"A file cannot be found at \"%@\".", baseFile);
        return 1;
    }

    origin = [baseFile stringByDeletingLastPathComponent];

    char *emptyLinesVar = getenv("COPYFILE_EMPTY_LINES");
    if (emptyLinesVar != NULL) {
        ignoreEmptyLines = !(strcasecmp(emptyLinesVar, "yes") == 0 || strcasecmp(emptyLinesVar, "true") == 0 || strcmp(emptyLinesVar, "1") == 0);
        free(emptyLinesVar);
        emptyLinesVar = NULL;
    }

    char *lineEndingVar = getenv("COPYFILE_NO_SPACES");
    if (lineEndingVar != NULL) {
        appendSpaces = !(strcasecmp(lineEndingVar, "yes") == 0 || strcasecmp(lineEndingVar, "true") == 0 || strcmp(lineEndingVar, "1") == 0);
        free(lineEndingVar);
        lineEndingVar = NULL;
    }

    if (argc > 2) {
        readEnvironment(argv[1]);

        if (environment == nil)
            NSLog(@"Error reading environment file, continuing without environment variables...");
    }

    NSString *fileContent = includeFile(baseFile, origin);

    if ([fileContent length] != 0) {
        NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
        [pasteboard clearContents];
        [pasteboard setString:fileContent forType:NSPasteboardTypeString];

        printf("Copied \"%s\".\n", argv[(argc == 2) ? 1 : 2]);
    } else {
        printf("Nothing was copied.\n");
    }

    return 0;
}
