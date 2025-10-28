#if !__has_feature(objc_arc)
#error "ARC is required for this project."
#endif

#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>

#import <stdio.h>
#import <stdlib.h>

NSDictionary<NSString *, NSString *> *environment = nil;

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

            unichar *standardChars = (unichar *)malloc(rangeLength * sizeof(unichar));
            if (standardChars == NULL)
                continue;

            [inputString getCharacters:standardChars range:standardRange];

            NSString *standardString = [NSString stringWithCharacters:standardChars length:rangeLength];
            free(standardChars);

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

            unichar *varNameChars = (unichar *)malloc(rangeLength * sizeof(unichar));
            if (varNameChars == NULL)
                break;

            [inputString getCharacters:varNameChars range:varRange];

            NSString *varName = [NSString stringWithCharacters:varNameChars length:rangeLength];
            free(varNameChars);

            NSString *varValue = [environment objectForKey:varName];
            if (varValue != nil)
                [outputString appendString:varValue];

            continue;
        }

        // The end is reached without a variable
        if (i == length-1) {
            if (rangeLength == 0)
                break;

            NSRange finalRange = NSMakeRange(rangeStart, rangeLength);

            unichar *finalChars = (unichar *)malloc(rangeLength * sizeof(unichar));
            if (finalChars == NULL)
                break;

            [inputString getCharacters:finalChars range:finalRange];

            NSString *finalString = [NSString stringWithCharacters:finalChars length:rangeLength];
            free(finalChars);

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

    // Change the working directory for paths relative to the current file
    NSString *originalWorkingDirectory = [fileManager currentDirectoryPath];
    [fileManager changeCurrentDirectoryPath:[filePath stringByDeletingLastPathComponent]];

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

            NSString *environmentalFile = processFile(environmentalFilePath);

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
        printf("  copyfile <filename> [<environment>]\n\n");
        printf("For more information, see copyfile(1).\n");
        return 1;
    }

    NSString *filePath = [NSString stringWithUTF8String:argv[1]];
    NSString *fileParentPath = [filePath stringByDeletingLastPathComponent];

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *originalWorkingDirectory = [fileManager currentDirectoryPath];

    BOOL changedDirectory = NO;
    BOOL fileParentPathIsDir;

    if (([fileManager fileExistsAtPath:fileParentPath isDirectory:&fileParentPathIsDir]) && fileParentPathIsDir) {
        [fileManager changeCurrentDirectoryPath:fileParentPath];
        changedDirectory = YES;
    }

    if (argc >= 3) {
        NSString *envPath = [NSString stringWithUTF8String:argv[2]];
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

    if (changedDirectory)
        [fileManager changeCurrentDirectoryPath:originalWorkingDirectory];

    NSString *processedFile = processFile(filePath);

    if (processedFile == nil) {
        NSLog(@"No usable output.");
        return 1;
    }

    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:processedFile forType:NSPasteboardTypeString];

    printf("Copied \"%s\".\n", argv[1]);
    return 0;
}
