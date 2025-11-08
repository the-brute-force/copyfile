#if !__has_feature(objc_arc)
#error "ARC is required for this project."
#endif

#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>

// This is only needed for printf
#import <stdio.h>
#import <string.h>

NSDictionary<NSString *, NSString *> *environment = nil;
NSString *origin = nil;

NSString *replaceEnvironmentVariables(NSString *inputString)
{
    if (inputString == nil)
        return @"";

    NSUInteger length = [inputString length];

    NSMutableString *outputString = [[NSMutableString alloc] init];

    NSUInteger rangeStart = 0;
    BOOL varMode = NO;

    for (NSUInteger i = 0; i < length; i++) {
        unichar current = [inputString characterAtIndex:i];
        unichar peek = 0;

        if (i < length-2) {
            peek = [inputString characterAtIndex:i+1];
        }

        NSUInteger rangeLength = i-rangeStart;

        // A variable is started
        if (!varMode && current == 0x24 && peek == 0x7B) {
            // Current range
            NSRange standardRange = NSMakeRange(rangeStart, rangeLength);

            varMode = YES;
            // Start after sequence
            rangeStart = ++i + 1;

            if (rangeLength == 0)
                continue;

            NSMutableData *charBuffer = [NSMutableData dataWithLength:rangeLength*sizeof(unichar)];
            unichar *standardChars = (unichar *)[charBuffer mutableBytes];

            [inputString getCharacters:standardChars range:standardRange];

            NSString *standardString = [NSString stringWithCharacters:standardChars length:rangeLength];

            [outputString appendString:standardString];

            continue;
        }

        // A variable is ended
        if (varMode && current == 0x7D) {
            NSRange varRange = NSMakeRange(rangeStart, rangeLength);

            varMode = NO;
            // Start at next character
            rangeStart = i+1;

            if (rangeLength == 0)
                continue;

            NSMutableData *charBuffer = [NSMutableData dataWithLength:rangeLength*sizeof(unichar)];
            unichar *varNameChars = (unichar *)[charBuffer mutableBytes];

            [inputString getCharacters:varNameChars range:varRange];

            NSString *varName = [NSString stringWithCharacters:varNameChars length:rangeLength];

            NSString *varValue = [environment objectForKey:varName];
            if (varValue != nil)
                [outputString appendString:varValue];

            continue;
        }

        // The end is reached without a variable
        if (i == length-1) {
            // Include the current character too
            rangeLength++;

            NSRange finalRange = NSMakeRange(rangeStart, rangeLength);

            NSMutableData *charBuffer = [NSMutableData dataWithLength:rangeLength*sizeof(unichar)];
            unichar *finalChars = (unichar *)[charBuffer mutableBytes];

            [inputString getCharacters:finalChars range:finalRange];

            NSString *finalString = [NSString stringWithCharacters:finalChars length:rangeLength];

            [outputString appendString:finalString];
        }
    }

    return outputString;
}

NSString *processFile(NSString *filePath)
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSData *fileData = [fileManager contentsAtPath:filePath];

    if (fileData == nil) {
        NSLog(@"Unable to read the file \"%@\".", filePath);
        return nil;
    }

    // Change the working directory to use paths relative to the current file
    NSString *originalWorkingDirectory = [fileManager currentDirectoryPath];
    NSString *fileParentPath = [filePath stringByDeletingLastPathComponent];

    [fileManager changeCurrentDirectoryPath:fileParentPath];

    if (origin == nil)
        origin = fileParentPath;

    NSString *fileAsString = [[NSString alloc] initWithData:fileData encoding:NSUTF8StringEncoding];
    fileData = nil;

    NSArray<NSString *> *fileLines = [fileAsString componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    fileAsString = nil;

    BOOL skippedShebang = NO;
    NSMutableString *processedFile = [[NSMutableString alloc] init];

    for (NSString *line in fileLines) {
        if ([line length] == 0)
            continue;

        // There's probably a better way to do this
        if ([processedFile length] != 0)
            [processedFile appendString:@" "];

        if ([line hasPrefix:@"#!"]) {
            if (!skippedShebang) {
                skippedShebang = YES;
                continue;
            }

            NSString *includedFilePath = [[line substringFromIndex:2] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSString *includedFile = processFile(includedFilePath);

            if (includedFile != nil)
                [processedFile appendString:includedFile];

            continue;
        }

        // File started without shebang
        if (!skippedShebang)
            skippedShebang = YES;

        if ([line hasPrefix:@"#?"]) {
            NSString *environmentalKeyName = [[line substringFromIndex:2] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSString *environmentalFilePath = [environment objectForKey:environmentalKeyName];

            if (environmentalFilePath == nil)
                continue;

            // Have all environmental inclusions relative to the first file processed
            [fileManager changeCurrentDirectoryPath:origin];
            NSString *environmentalFile = processFile(environmentalFilePath);
            [fileManager changeCurrentDirectoryPath:fileParentPath];

            if (environmentalFile != nil)
                [processedFile appendString:environmentalFile];

            continue;
        }

        [processedFile appendString:replaceEnvironmentVariables(line)];
    }

    [fileManager changeCurrentDirectoryPath:originalWorkingDirectory];

    return processedFile;
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

    NSString *filePath;
    NSString *envPath = nil;

    NSFileManager *fileManager = [NSFileManager defaultManager];

    if (argc == 2) {
        filePath =  [fileManager stringWithFileSystemRepresentation:argv[1] length:strlen(argv[1])];
    } else {
        envPath =  [fileManager stringWithFileSystemRepresentation:argv[1] length:strlen(argv[1])];
        filePath = [fileManager stringWithFileSystemRepresentation:argv[2] length:strlen(argv[2])];
    }

    NSString *fileParentPath = [filePath stringByDeletingLastPathComponent];
    NSString *originalWorkingDirectory = [fileManager currentDirectoryPath];

    BOOL fileParentPathIsDir;

    // Because the origin file isn't being opened, its path needs to be checked
    if (envPath != nil && ([fileManager fileExistsAtPath:fileParentPath isDirectory:&fileParentPathIsDir]) && fileParentPathIsDir) {
        [fileManager changeCurrentDirectoryPath:fileParentPath];
        origin = fileParentPath;
    }

    if (envPath != nil) {
        NSData *envData = [fileManager contentsAtPath:envPath];

        NSError *err = nil;
        id envJSON = nil;

        NSMutableDictionary *envDict = [[NSMutableDictionary alloc] init];

        if (envData == nil) {
            NSLog(@"The environment \"%@\" could not be read.", envPath);
        } else {
            NSOperatingSystemVersion minForJSON5 = {.majorVersion = 12};

            if ([[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:minForJSON5]) {
                envJSON = [NSJSONSerialization JSONObjectWithData:envData options:NSJSONReadingJSON5Allowed error:&err];
            } else {
                envJSON = [NSJSONSerialization JSONObjectWithData:envData options:0 error:&err];
            }
        }

        if (err != nil) {
            NSLog(@"The environment \"%@\" is malformed.", envPath);
        } else if (envJSON != nil && ![envJSON isKindOfClass:[NSDictionary class]]) {
            NSLog(@"The environment \"%@\" has an array instead of objects.", envPath);
        } else {
            [envDict addEntriesFromDictionary:(NSDictionary *)envJSON];
        }

        if (envDict != nil) {
            for (NSString *key in envDict) {
                id value = [envDict objectForKey:key];

                if ([value isKindOfClass:[NSString class]]) {
                    continue;
                }

                if ([value isKindOfClass:[NSNumber class]]) {
                    [envDict setValue:[(NSNumber *)value stringValue] forKey:key];
                    continue;
                }

                [envDict removeObjectForKey:key];
            }

            environment = envDict;
        }
    }

    // It's easier to just change back than to reuse the current working directory
    if (origin != nil)
        [fileManager changeCurrentDirectoryPath:originalWorkingDirectory];

    NSString *processedFile = processFile(filePath);

    if (processedFile == nil) {
        NSLog(@"No usable output.");
        return 1;
    }

    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:processedFile forType:NSPasteboardTypeString];

    printf("Copied \"%s\".\n", argv[(argc == 2) ? 1 : 2]);
    return 0;
}
